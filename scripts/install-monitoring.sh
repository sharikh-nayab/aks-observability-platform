#!/usr/bin/env bash
# Installs kube-prometheus-stack plus our rules and dashboards.
# Idempotent; re-run after editing anything under k8s/monitoring.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl helm
CONTEXT="${KUBE_CONTEXT:-$(kubectl config current-context)}"
assert_context "$CONTEXT"

CHART_VERSION="${KPS_CHART_VERSION:-65.5.1}"
NS=monitoring

log "ensuring namespace ${NS}"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

# grafana admin creds live in a secret the chart references; generate once
if ! kubectl -n "$NS" get secret grafana-admin >/dev/null 2>&1; then
  log "creating grafana-admin secret"
  pw="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 20)"
  kubectl -n "$NS" create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$pw"
  warn "grafana admin password: $pw  (also: kubectl -n $NS get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
fi

log "helm repo"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community >/dev/null

log "installing kube-prometheus-stack ${CHART_VERSION}"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "$NS" \
  --version "$CHART_VERSION" \
  -f "${K8S_DIR}/monitoring/kube-prometheus-stack.values.yaml" \
  --wait --timeout 10m

log "applying rules and dashboards"
kubectl apply -f "${K8S_DIR}/monitoring/rules/"
kubectl apply -f "${K8S_DIR}/monitoring/dashboards/"

log "done. grafana: kubectl -n ${NS} port-forward svc/kps-grafana 3000:80"
