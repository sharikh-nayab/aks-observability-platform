#!/usr/bin/env bash
# PrometheusRule CRs aren't directly readable by promtool; pull out spec.groups
# into a plain rules file and check that. Catches PromQL typos before they
# reach the operator (which would otherwise just silently drop the rule group).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

status=0
for f in k8s/monitoring/rules/*.yaml; do
  out="${tmp}/$(basename "$f")"
  python3 - "$f" "$out" <<'EOF'
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
docs = [d for d in yaml.safe_load_all(open(src)) if d and d.get("kind") == "PrometheusRule"]
groups = [g for d in docs for g in d["spec"]["groups"]]
yaml.safe_dump({"groups": groups}, open(dst, "w"), sort_keys=False)
EOF
  echo "== $f"
  promtool check rules "$out" || status=1
done
exit $status
