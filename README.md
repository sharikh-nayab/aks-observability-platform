# aks-observability-platform

[![ci](https://github.com/sharikh-nayab/aks-observability-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/sharikh-nayab/aks-observability-platform/actions/workflows/ci.yml)

An AKS cluster built with Terraform, monitored by Dynatrace and
Prometheus/Grafana, with a sample workload, alert rules that have a runbook
behind them, and a load generator to prove the alerts actually fire.

This is the setup I've converged on after running Azure Kubernetes platforms
for a few years: Dynatrace for APM and problem detection, Prometheus for
platform alerting that lives in git, both installed by scripts that are safe to
re-run. I've pulled it into one repo so it's reproducible and so the design
decisions are written down somewhere other than my head.

## What you get

| Layer | What | Where |
|---|---|---|
| Infra | RG, vnet/subnet/NSG, AKS (cilium overlay, system + autoscaling user pool), Log Analytics, control-plane diagnostics | `terraform/` |
| APM | Dynatrace Operator + `DynaKube` (cloudNativeFullStack, ActiveGate routing + k8s monitoring) | `k8s/dynatrace/` |
| Metrics | kube-prometheus-stack tuned for AKS, Alertmanager routing by severity | `k8s/monitoring/` |
| Alerts | Recording rules + 8 alerts with `runbook_url` | `k8s/monitoring/rules/` |
| Dashboard | Golden signals for the app, shipped as a ConfigMap | `k8s/monitoring/dashboards/` |
| Workload | podinfo with ServiceMonitor, PDB, HPA, restricted PSS | `k8s/podinfo/` |
| Ops | Install / load / teardown scripts, Makefile | `scripts/`, `Makefile` |
| Docs | [Architecture and decisions](docs/architecture.md), [Runbook](docs/runbook.md) | `docs/` |

## Prerequisites

- Azure subscription + `az` logged in (`az account show`)
- A storage account for Terraform state (see `make init` variables)
- `terraform` >= 1.6, `kubectl`, `helm` >= 3.8, `envsubst`
- For Dynatrace: a SaaS tenant with an operator token and a data ingest token
  ([token scopes](https://docs.dynatrace.com/docs/ingest-from/setup-on-k8s/installation/cloud-native-fullstack))

## Bring it up

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # edit
make init TF_BACKEND_RG=tfstate-rg TF_BACKEND_SA=<your-sa>
make plan
make apply            # ~8 min
make kubeconfig
make app              # podinfo
make monitoring       # prometheus, alertmanager, grafana, rules, dashboard
```

Dynatrace is separate because it needs tenant credentials:

```bash
cat > .env <<EOF
DT_API_URL=https://abc12345.live.dynatrace.com/api
DT_API_TOKEN=dt0c01....
DT_INGEST_TOKEN=dt0c01....
EOF
set -a; source .env; set +a
make dynatrace
kubectl -n podinfo rollout restart deploy/podinfo   # pick up code modules
```

Then:

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
# admin password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
make load             # steady traffic for 5 min
```

Open `podinfo / golden signals` in Grafana. In Dynatrace the service shows up
under Services within a couple of minutes, with PurePaths once traffic flows.

## Break it

The point of alert rules is that they fire. Each of these trips a specific
alert within its `for` window; the runbook entry tells you what you'd do about
it in a real incident.

```bash
make load-errors      # ~20% 5xx  -> PodinfoHighErrorRate   (critical, 5m)
make load-slow        # 1s delays -> PodinfoLatencyP95High  (warning, 10m)
kubectl -n podinfo set resources deploy/podinfo --limits=memory=20Mi   # -> PodinfoPodRestarting
kubectl -n podinfo scale deploy/podinfo --replicas=0                  # -> PodinfoNoTraffic
```

Alertmanager: `kubectl -n monitoring port-forward svc/kps-alertmanager 9093`.
Dynatrace will open a problem card for the error rate and latency cases too,
which is a good way to see the two systems side by side on the same incident.

## Tear it down

```bash
make teardown         # helm uninstall (frees the Azure LBs/disks) then terraform destroy
```

Lab cost with the defaults (2x D2s_v5 + 1x D4s_v5, Free tier, Central India)
is in the region of USD 8-9/day. Don't leave it running over a weekend.

## Repo layout

```
.
├── terraform/
│   ├── main.tf, variables.tf, outputs.tf, providers.tf, versions.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── network/      vnet, subnet, nsg
│       └── aks/          cluster, user pool
├── k8s/
│   ├── podinfo/          deployment, service, pdb, hpa, servicemonitor
│   ├── monitoring/
│   │   ├── kube-prometheus-stack.values.yaml
│   │   ├── rules/        PrometheusRule
│   │   └── dashboards/   grafana ConfigMaps
│   └── dynatrace/        operator values, dynakube
├── scripts/              install-*, deploy-app, load, teardown, ci/check-rules
├── docs/                 architecture.md, runbook.md
└── .github/workflows/    ci.yml
```

## CI

Every push runs:

- `terraform fmt -check`, `terraform validate`, `tflint` with the azurerm ruleset
- `kubeconform` against upstream + CRD schemas for everything under `k8s/`
- `promtool check rules` on the PrometheusRule groups (catches PromQL typos
  that the operator would otherwise silently drop)
- `shellcheck` on the scripts
- `helm template` for both charts with this repo's values, so a values typo
  fails in CI instead of at `helm upgrade`

There's no `terraform plan` in CI because that needs cloud credentials and a
state backend; for a shared environment I'd add it with OIDC federation to a
plan-only service principal and post the plan on the PR.

## Why these choices

Written up in [docs/architecture.md](docs/architecture.md). Short version:
cilium overlay so pod IPs don't eat vnet space; separate system pool so
monitoring never competes with apps; cloudNativeFullStack with the CSI driver
because it's the cleanest injection model on AKS; Prometheus rules kept
alongside Dynatrace because alert definitions belong in code review and
because the day Dynatrace is unreachable is exactly the day you want a
second opinion.

## Not done yet

- Ingress (AGIC or nginx + App Gateway WAF). podinfo is port-forward only.
- Dynatrace tenant config as code (Monaco): alerting profiles, management
  zones, tagging rules, SLOs.
- Loki for logs on the Prometheus side. Logs currently go to Dynatrace and
  Container Insights only.
- `terraform plan` on PRs via OIDC.
- Real Alertmanager receivers (the routes point at a placeholder relay).

## License

MIT
