# Changelog

Notable changes to this repo. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Planned work is tracked in [issues](https://github.com/sharikh-nayab/aks-observability-platform/issues):
ingress (#1), Dynatrace config as code (#2), plan-on-PR (#3), Loki (#4),
real Alertmanager receivers (#5), screenshots from a live run (#6).

## [0.1.0] - 2026-11-21

First usable version.

### Added
- Terraform: resource group, vnet/subnet/NSG, AKS with cilium overlay, tainted
  system pool and autoscaling `apps` pool, Log Analytics with control-plane
  diagnostics (`kube-audit-admin`, `cluster-autoscaler`, `guard`).
- Dynatrace Operator 1.11 values and a `v1beta6` DynaKube (cloudNativeFullStack,
  CSI driver, ActiveGate routing + kubernetes-monitoring, injection excluded
  from `monitoring`/`dynatrace`/`kube-system`).
- kube-prometheus-stack 65.5.1 values tuned for AKS: control-plane scrapes
  disabled, selectors open to all namespaces, Alertmanager routed by severity.
- Recording rules and eight alerts for podinfo, nodes, PVCs and scrape
  targets, each with a `runbook_url`.
- Golden-signals Grafana dashboard delivered as a sidecar ConfigMap.
- podinfo sample workload with ServiceMonitor, PDB, HPA and restricted PSS.
- Scripts: idempotent monitoring and Dynatrace installs, load generator with
  `normal|errors|slow` modes, teardown that removes Helm releases before
  `terraform destroy`.
- CI: terraform fmt/validate/tflint, kubeconform, promtool rule check,
  shellcheck, helm template for both charts.
- Docs: architecture and decisions, runbook.

[Unreleased]: https://github.com/sharikh-nayab/aks-observability-platform/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sharikh-nayab/aks-observability-platform/releases/tag/v0.1.0
