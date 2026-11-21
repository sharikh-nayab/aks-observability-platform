#!/usr/bin/env bash
# Generates traffic against podinfo from inside the cluster so the dashboards
# and alerts have something to show. Usage:
#   scripts/load.sh            # normal traffic, 5 min
#   scripts/load.sh errors     # ~20% 5xx, trips PodinfoHighErrorRate
#   scripts/load.sh slow       # 1s delays, trips PodinfoLatencyP95High
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
MODE="${1:-normal}"
DURATION="${DURATION:-300}"

case "$MODE" in
  normal) PATHS=("/" "/version" "/env" "/headers") ;;
  errors) PATHS=("/" "/" "/" "/" "/status/500") ;;
  slow)   PATHS=("/" "/delay/1") ;;
  *) die "unknown mode: $MODE (normal|errors|slow)" ;;
esac

# bash array -> space separated string for the pod's shell
PATH_LIST="${PATHS[*]}"

log "load mode=${MODE} duration=${DURATION}s"
kubectl -n podinfo delete pod load --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl -n podinfo run load --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"load","image":"curlimages/curl:8.10.1","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
  -- sh -c "
    end=\$((\$(date +%s) + ${DURATION}))
    i=0
    while [ \$(date +%s) -lt \$end ]; do
      for p in ${PATH_LIST}; do
        curl -s -o /dev/null -w '%{http_code} ' http://podinfo.podinfo.svc:9898\$p
        i=\$((i+1))
        [ \$((i % 50)) -eq 0 ] && echo
      done
      sleep 0.2
    done
    echo; echo done: \$i requests
  "
