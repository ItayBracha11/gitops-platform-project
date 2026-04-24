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
  kubectl get application "$1" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1
}

disable_root_autosync() {
  if app_exists "$ROOT_APP_NAME"; then
    log "Disabling autosync on ${ROOT_APP_NAME}"
    kubectl patch application "$ROOT_APP_NAME" -n "$ARGOCD_NAMESPACE" \
      --type merge \
      -p '{"spec":{"syncPolicy":null}}' >/dev/null || true
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
      .items[] | select((.spec.destination.namespace // "") != $ns) | .metadata.name
    '
  else
    get_child_apps_json | jq -r --arg ns "$CONTROLLER_NAMESPACE" '
      .items[] | select((.spec.destination.namespace // "") == $ns) | .metadata.name
    '
  fi
}

get_app_destination_namespace() {
  kubectl get application "$1" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.destination.namespace}'
}

delete_managed_resources_except_ingress_tgb_namespace() {
  local app="$1"

  if ! app_exists "$app"; then
    return 0
  fi

  log "Deleting managed resources for ${app}, excluding Ingress, TargetGroupBinding, Namespace"

  kubectl get application "$app" -n "$ARGOCD_NAMESPACE" -o json |
    jq -r '.status.resources[]? | @base64' |
    while read -r row; do
      [ -n "$row" ] || continue

      item="$(echo "$row" | base64 -d)"
      kind="$(echo "$item" | jq -r '.kind')"
      name="$(echo "$item" | jq -r '.name')"
      namespace="$(echo "$item" | jq -r '.namespace // empty')"
      group="$(echo "$item" | jq -r '.group // empty')"

      [ "$kind" = "Namespace" ] && continue
      [ "$kind" = "Ingress" ] && continue
      [ "$kind" = "TargetGroupBinding" ] && continue
      [ -z "$name" ] && continue

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

delete_ingresses_in_namespace() {
  local ns="$1"

  log "Deleting ingresses in namespace ${ns}"
  kubectl get ingress -n "$ns" -o name 2>/dev/null |
    while read -r ing; do
      [ -n "$ing" ] || continue
      log "Deleting ${ing}"
      kubectl delete "$ing" -n "$ns" --ignore-not-found=true --wait=false || true
    done
}

wait_for_targetgroupbindings_gone_or_force() {
  local ns="$1"
  local attempts=12
  local sleep_seconds=10

  for i in $(seq 1 "$attempts"); do
    count="$(kubectl get targetgroupbindings -n "$ns" --no-headers 2>/dev/null | wc -l || echo 0)"

    if [ "$count" -eq 0 ]; then
      log "TargetGroupBindings in ${ns} are gone"
      return 0
    fi

    log "Namespace ${ns} still has ${count} TargetGroupBinding(s), waiting (${i}/${attempts})"
    sleep "$sleep_seconds"
  done

  log "TargetGroupBindings still exist in ${ns}; removing finalizers as fallback"

  kubectl get targetgroupbindings -n "$ns" -o name 2>/dev/null |
    while read -r tgb; do
      [ -n "$tgb" ] || continue
      log "Patching finalizers on ${tgb}"
      kubectl patch "$tgb" -n "$ns" --type merge -p '{"metadata":{"finalizers":[]}}' || true
      kubectl delete "$tgb" -n "$ns" --ignore-not-found=true --wait=false || true
    done
}

wait_for_ingresses_gone_or_force() {
  local ns="$1"
  local attempts=12
  local sleep_seconds=10

  for i in $(seq 1 "$attempts"); do
    count="$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | wc -l || echo 0)"

    if [ "$count" -eq 0 ]; then
      log "Ingresses in ${ns} are gone"
      return 0
    fi

    log "Namespace ${ns} still has ${count} ingress resource(s), waiting (${i}/${attempts})"
    sleep "$sleep_seconds"
  done

  log "Ingresses still exist in ${ns}; removing finalizers as fallback"

  kubectl get ingress -n "$ns" -o name 2>/dev/null |
    while read -r ing; do
      [ -n "$ing" ] || continue
      log "Patching finalizers on ${ing}"
      kubectl patch "$ing" -n "$ns" --type merge -p '{"metadata":{"finalizers":[]}}' || true
      kubectl delete "$ing" -n "$ns" --ignore-not-found=true --wait=false || true
    done
}

delete_application_nonblocking() {
  local app="$1"

  if app_exists "$app"; then
    log "Deleting Application ${app}"
    kubectl delete application "$app" -n "$ARGOCD_NAMESPACE" --ignore-not-found=true --wait=false || true
  fi
}

delete_workload_phase() {
  mapfile -t workload_apps < <(get_child_app_names_by_destination_namespace workload)

  if [ "${#workload_apps[@]}" -eq 0 ]; then
    log "No workload child applications found"
    return 0
  fi

  log "Workload child applications:"
  printf ' - %s\n' "${workload_apps[@]}"

  for app in "${workload_apps[@]}"; do
    ns="$(get_app_destination_namespace "$app")"

    delete_managed_resources_except_ingress_tgb_namespace "$app"

    # Important: delete ingress while ALB controller/webhook still exists.
    delete_ingresses_in_namespace "$ns"

    # Important: handle TGB before deleting ALB controller.
    wait_for_targetgroupbindings_gone_or_force "$ns"
    wait_for_ingresses_gone_or_force "$ns"

    delete_application_nonblocking "$app"
  done
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
    delete_application_nonblocking "$app"
  done

  log "Controller applications delete requested"
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