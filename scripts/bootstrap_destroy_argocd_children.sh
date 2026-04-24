#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ROOT_APP_NAME="${ROOT_APP_NAME:-root-app}"
CONTROLLER_NAMESPACE="${CONTROLLER_NAMESPACE:-kube-system}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required binary: $1" >&2
    exit 1
  }
}

app_exists() {
  local app="$1"
  kubectl get application "$app" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1
}

disable_root_autosync() {
  if app_exists "$ROOT_APP_NAME"; then
    log "Disabling autosync on ${ROOT_APP_NAME}"
    kubectl patch application "$ROOT_APP_NAME" -n "$ARGOCD_NAMESPACE" \
      --type merge \
      -p '{"spec":{"syncPolicy":null}}' >/dev/null || true
  else
    log "Root app ${ROOT_APP_NAME} not found"
  fi
}

get_child_apps_json() {
  kubectl get applications -n "$ARGOCD_NAMESPACE" \
    -l "argocd.argoproj.io/instance=${ROOT_APP_NAME}" \
    -o json
}

get_child_app_names_by_destination_namespace() {
  local mode="$1"
  if [ "$mode" = "workload" ]; then
    get_child_apps_json | jq -r --arg ns "$CONTROLLER_NAMESPACE" '
      .items[]
      | select((.spec.destination.namespace // "") != $ns)
      | .metadata.name
    '
  else
    get_child_apps_json | jq -r --arg ns "$CONTROLLER_NAMESPACE" '
      .items[]
      | select((.spec.destination.namespace // "") == $ns)
      | .metadata.name
    '
  fi
}

get_app_destination_namespace() {
  local app="$1"
  kubectl get application "$app" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.destination.namespace}'
}

delete_managed_resources_except_namespaces() {
  local app="$1"

  if ! app_exists "$app"; then
    log "Application ${app} not found, skipping managed resource deletion"
    return 0
  fi

  log "Deleting managed resources for ${app} (excluding Namespaces)"

  kubectl get application "$app" -n "$ARGOCD_NAMESPACE" -o json \
    | jq -r '.status.resources[]? | @base64' \
    | while read -r row; do
        [ -n "$row" ] || continue

        local item kind name namespace group resource
        item="$(echo "$row" | base64 -d)"
        kind="$(echo "$item" | jq -r '.kind')"
        name="$(echo "$item" | jq -r '.name')"
        namespace="$(echo "$item" | jq -r '.namespace // empty')"
        group="$(echo "$item" | jq -r '.group // empty')"

        [ -z "$name" ] && continue
        [ "$kind" = "Namespace" ] && continue

        if [ -n "$group" ] && [ "$group" != "null" ]; then
          resource="${kind,,}.${group}"
        else
          resource="${kind,,}"
        fi

        if [ -n "$namespace" ] && [ "$namespace" != "null" ]; then
          log "Deleting ${resource} ${namespace}/${name}"
          kubectl delete "$resource" "$name" -n "$namespace" --ignore-not-found=true --wait=false || true
        else
          log "Deleting ${resource} ${name}"
          kubectl delete "$resource" "$name" --ignore-not-found=true --wait=false || true
        fi
      done
}

delete_application_nonblocking() {
  local app="$1"
  if app_exists "$app"; then
    log "Deleting Application ${app}"
    kubectl delete application "$app" -n "$ARGOCD_NAMESPACE" --ignore-not-found=true --wait=false || true
  fi
}

wait_until_apps_gone() {
  local apps=("$@")
  local attempts=40
  local sleep_seconds=15

  if [ "${#apps[@]}" -eq 0 ]; then
    log "No applications to wait for"
    return 0
  fi

  for i in $(seq 1 "$attempts"); do
    local remaining=0

    for app in "${apps[@]}"; do
      if app_exists "$app"; then
        log "Application ${app} still exists"
        remaining=1
      fi
    done

    if [ "$remaining" -eq 0 ]; then
      log "Target applications are gone"
      return 0
    fi

    log "Waiting for applications to disappear (attempt ${i}/${attempts})"
    sleep "$sleep_seconds"
  done

  log "Timed out waiting for applications to disappear"
  return 1
}

wait_until_no_ingresses_in_namespaces() {
  local namespaces=("$@")
  local attempts=40
  local sleep_seconds=15

  if [ "${#namespaces[@]}" -eq 0 ]; then
    log "No namespaces to check for ingresses"
    return 0
  fi

  for i in $(seq 1 "$attempts"); do
    local found=0

    for ns in "${namespaces[@]}"; do
      [ -n "$ns" ] || continue
      local count
      count="$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | wc -l || echo 0)"
      if [ "$count" -gt 0 ]; then
        log "Namespace ${ns} still has ${count} ingress resource(s)"
        found=1
      fi
    done

    if [ "$found" -eq 0 ]; then
      log "All ingresses in workload namespaces are gone"
      return 0
    fi

    log "Waiting for ingress cleanup (attempt ${i}/${attempts})"
    sleep "$sleep_seconds"
  done

  log "Timed out waiting for ingress cleanup"
  return 1
}

delete_workload_phase() {
  mapfile -t workload_apps < <(get_child_app_names_by_destination_namespace workload)

  if [ "${#workload_apps[@]}" -eq 0 ]; then
    log "No workload child applications found"
    return 0
  fi

  log "Workload child applications:"
  printf ' - %s\n' "${workload_apps[@]}"

  local workload_namespaces=()
  for app in "${workload_apps[@]}"; do
    ns="$(get_app_destination_namespace "$app")"
    workload_namespaces+=("$ns")
    delete_managed_resources_except_namespaces "$app"
    delete_application_nonblocking "$app"
  done

  wait_until_apps_gone "${workload_apps[@]}" || true
  wait_until_no_ingresses_in_namespaces "${workload_namespaces[@]}" || true
}

delete_controller_phase() {
  mapfile -t controller_apps < <(get_child_app_names_by_destination_namespace controller)

  if [ "${#controller_apps[@]}" -eq 0 ]; then
    log "No controller child applications found"
    return 0
  fi

  log "Controller child applications:"
  printf ' - %s\n' "${controller_apps[@]}"

  for app in "${controller_apps[@]}"; do
    delete_managed_resources_except_namespaces "$app"
    delete_application_nonblocking "$app"
  done

  wait_until_apps_gone "${controller_apps[@]}" || true
}

main() {
  need kubectl
  need jq
  need base64

  disable_root_autosync
  delete_workload_phase
  delete_controller_phase

  log "Bootstrap child teardown phase completed"
}

main "$@"