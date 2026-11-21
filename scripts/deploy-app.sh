#!/usr/bin/env bash
# Deploys the podinfo sample app and waits for it.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
CONTEXT="${KUBE_CONTEXT:-$(kubectl config current-context)}"
assert_context "$CONTEXT"

log "applying podinfo"
kubectl apply -f "${K8S_DIR}/podinfo/namespace.yaml"
kubectl apply -f "${K8S_DIR}/podinfo/"
kubectl -n podinfo rollout status deployment/podinfo --timeout=180s

log "podinfo is up. try:"
log "  kubectl -n podinfo port-forward svc/podinfo 9898:9898"
log "  curl localhost:9898/            # hello"
log "  curl localhost:9898/delay/2     # slow request, pushes p95 up"
log "  curl localhost:9898/status/500  # error, pushes 5xx ratio up"
