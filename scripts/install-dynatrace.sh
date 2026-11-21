#!/usr/bin/env bash
# Installs the Dynatrace Operator and applies the DynaKube.
#
# Needs:
#   DT_API_URL        https://<env-id>.live.dynatrace.com/api  (or .apps. for managed)
#   DT_API_TOKEN      operator token (scopes: InstallerDownload, DataExport,
#                     entities.read, settings.read/write, activeGateTokenManagement.create)
#   DT_INGEST_TOKEN   data ingest token (metrics.ingest, logs.ingest, openTelemetryTrace.ingest)
#
# Put them in a .env (gitignored) and `set -a; source .env; set +a`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl helm envsubst
require_env DT_API_URL DT_API_TOKEN DT_INGEST_TOKEN
CONTEXT="${KUBE_CONTEXT:-$(kubectl config current-context)}"
assert_context "$CONTEXT"

[[ "$DT_API_URL" == */api ]] || die "DT_API_URL should end in /api, got: $DT_API_URL"

OPERATOR_VERSION="${DT_OPERATOR_VERSION:-1.11.0}"
NS=dynatrace

log "installing dynatrace-operator ${OPERATOR_VERSION}"
helm upgrade --install dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --version "$OPERATOR_VERSION" \
  --namespace "$NS" --create-namespace \
  -f "${K8S_DIR}/dynatrace/operator.values.yaml" \
  --atomic --timeout 5m

log "waiting for webhook"
kubectl -n "$NS" rollout status deployment/dynatrace-webhook --timeout=120s

# apply (not create) so re-running with rotated tokens works
log "writing dynakube secret"
kubectl -n "$NS" create secret generic dynakube \
  --from-literal="apiToken=${DT_API_TOKEN}" \
  --from-literal="dataIngestToken=${DT_INGEST_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "applying dynakube"
export DT_API_URL
envsubst '${DT_API_URL}' < "${K8S_DIR}/dynatrace/dynakube.yaml" | kubectl apply -f -

log "waiting for oneagent daemonset (this can take a few minutes on first install)"
for _ in $(seq 1 30); do
  if kubectl -n "$NS" get daemonset dynakube-oneagent >/dev/null 2>&1; then
    kubectl -n "$NS" rollout status daemonset/dynakube-oneagent --timeout=300s
    break
  fi
  sleep 10
done

kubectl -n "$NS" get dynakube
log "done. existing pods need a restart to get code modules injected:"
log "  kubectl -n podinfo rollout restart deployment/podinfo"
