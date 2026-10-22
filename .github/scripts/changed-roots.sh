#!/usr/bin/env bash
# Maps changed file paths (stdin, one per line) to the Terraform roots they affect.
# Prints one root per line: <env>/<root> (e.g. dev/network) or "backend". Run from the repo root.
set -euo pipefail

while IFS= read -r path; do
  case "$path" in
    infra/environments/*/*/*)
      # infra/environments/<env>/<root>/... -> <env>/<root>
      echo "$path" | cut -d/ -f3,4
      ;;
    infra/modules/*/*/*)
      # A module change affects every root that sources it, read from the roots' own
      # source = "../../../modules/<category>/<module>" lines so the mapping can't go stale.
      module=$(echo "$path" | cut -d/ -f3,4)
      grep -rlE --include='*.tf' "source[[:space:]]*=[[:space:]]*\"[./]*/modules/${module}\"" infra/environments \
        | cut -d/ -f3,4 || true
      ;;
    infra/bootstrap/*)
      echo backend
      ;;
    # gitops/ and workflow files map to no root; the agent traces them from the diff.
  esac
done | sort -u
