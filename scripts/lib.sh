#!/usr/bin/env bash
# shellcheck disable=SC2034  # TF_DIR/K8S_DIR are used by the scripts that source this
# shared bits for the scripts in this dir. source it, don't run it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
K8S_DIR="${ROOT_DIR}/k8s"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "missing dependency: $bin"
  done
}

require_env() {
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || die "env var $v is not set"
  done
}

# fail fast if kubectl is pointed at something unexpected
assert_context() {
  local want="$1"
  local have
  have="$(kubectl config current-context 2>/dev/null || true)"
  [[ "$have" == "$want" ]] || die "kubectl context is '$have', expected '$want'. Run: make kubeconfig"
}
