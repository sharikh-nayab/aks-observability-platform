#!/usr/bin/env bash
# Tears everything down. Helm releases first so Azure LBs/disks created by
# the cluster are cleaned up before terraform removes the node RG.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl helm terraform

if kubectl cluster-info >/dev/null 2>&1; then
  log "removing helm releases"
  helm -n dynatrace uninstall dynatrace-operator --wait 2>/dev/null || true
  helm -n monitoring uninstall kube-prometheus-stack --wait 2>/dev/null || true
  # PVCs don't go with the release
  kubectl -n monitoring delete pvc --all --ignore-not-found
else
  warn "cluster not reachable, skipping helm cleanup"
fi

log "terraform destroy"
terraform -chdir="$TF_DIR" destroy -auto-approve
