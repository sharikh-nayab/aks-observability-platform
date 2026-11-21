# Architecture

```
                       Azure subscription
 ┌──────────────────────────────────────────────────────────────────┐
 │  obsplat-dev-rg                                                  │
 │                                                                  │
 │   vnet 10.40.0.0/16                                              │
 │   └── aks-nodes 10.40.0.0/22   (nsg: deny inbound internet)      │
 │         │                                                        │
 │   ┌─────┴──────────────────────────────────────────────────┐     │
 │   │ AKS  (cilium overlay, pods 10.244.0.0/16)              │     │
 │   │                                                        │     │
 │   │  system pool (D2s_v5 x2, CriticalAddonsOnly)           │     │
 │   │    kube-system, prometheus, alertmanager, grafana,     │     │
 │   │    dynatrace operator + activegate                     │     │
 │   │                                                        │     │
 │   │  apps pool (D4s_v5, autoscale 1..5, label workload=apps)│    │
 │   │    podinfo x2..6  ◄── oneagent code modules injected   │     │
 │   │                                                        │     │
 │   │  every node: oneagent daemonset, node-exporter         │     │
 │   └────────┬──────────────────────────┬────────────────────┘     │
 │            │ container insights       │                          │
 │   log analytics workspace             │                          │
 │   (kube-audit-admin, autoscaler, guard)                          │
 └───────────────────────────────────────┼──────────────────────────┘
                                         │ activegate (routing)
                                         ▼
                              Dynatrace SaaS tenant
```

## Two observability stacks, on purpose

This mirrors what I've run in production: Dynatrace as the primary APM
(traces, RUM, Davis AI problem detection, the thing the business dashboards
are built on) and Prometheus/Grafana for the platform team's own alerting and
for anything that needs raw PromQL.

They overlap and that's fine. Reasons to keep both:

- Prometheus alerting rules live in git next to the workload and go through
  code review. Dynatrace alerting profiles are configured in the tenant (or via
  Monaco / the settings API), and in practice drift more.
- When Dynatrace itself has an issue (ActiveGate down, tenant maintenance,
  licence cap hit) you still want to know a node is NotReady.
- Dynatrace licences by host unit / GiB; scraping a few hundred cheap metrics
  into Prometheus costs nothing extra.
- Developers who already know PromQL get a datasource they can query directly.

What I deliberately *don't* do is duplicate dashboards. Golden signals for the
app live in Grafana (this repo); service flow, PurePath, RUM and problem cards
live in Dynatrace.

## Terraform layout

```
terraform/
  main.tf            rg, law, diagnostic settings, module wiring
  variables.tf       everything tunable, with lab defaults
  modules/network    vnet, node subnet, nsg
  modules/aks        cluster + user node pool
```

Root module per environment is the intended pattern: `terraform.tfvars` per
env, same code, separate state keys (`obsplat-<env>.tfstate`). I kept it to one
root here rather than adding `envs/dev`, `envs/prod` directories because for a
reference repo that's just noise.

## Cluster decisions

**Cilium overlay** rather than Azure CNI with node subnet IPs. Overlay means
pod IPs don't consume vnet address space, which is what runs out first in a
shared hub/spoke. Cilium gives network policy enforcement without a separate
Calico install.

**Separate system and user pools.** `only_critical_addons_enabled` taints the
system pool so apps can't land there. Prometheus and the Dynatrace components
are explicitly scheduled onto it (tolerations + nodeSelector) because losing
monitoring to a noisy neighbour on the apps pool is the worst time to lose it.

**Ephemeral OS disks.** Faster node boot, no managed disk cost, and nothing
on a node's OS disk should be worth keeping.

**Patch auto-upgrade + NodeImage channel with a Sunday 01:00 IST window.**
Minor version upgrades are a deliberate action (bump `kubernetes_version`,
plan, apply). Patches and node image CVEs shouldn't need a human.

**Workload identity + OIDC issuer on by default.** Even if nothing in this repo
uses it yet, turning it on later forces a cluster update; turning it on at
create time is free.

**Local accounts stay on when no admin group is given.** For a lab, Azure RBAC
on the cluster is friction. The moment `admin_group_object_ids` is set, local
accounts are disabled. Same code, both modes.

## Monitoring decisions

**kube-prometheus-stack with the control-plane scrapes disabled.** AKS doesn't
expose controller-manager / scheduler / etcd metrics endpoints. Leaving the
defaults on gives you `TargetDown` firing forever, which trains people to
ignore alerts.

**`*SelectorNilUsesHelmValues: false`.** Any ServiceMonitor / PrometheusRule in
the cluster is picked up, not just ones labelled with the release name. Teams
ship their own monitors with their app and don't need to know the release name.

**Recording rules in front of alerts.** `job:podinfo_http_error_ratio:rate5m`
is easier to read in an alert and in a dashboard than the raw expression, and
the alert and the panel can't drift apart.

**Alertmanager routes by severity.** `critical` goes to a pager receiver and
`warning` to a ticket receiver. The receiver URLs in the values file point at
an in-cluster relay placeholder so the routing tree is reviewable in git without
committing webhook secrets.

**Dashboards as ConfigMaps via the sidecar.** Export from Grafana, paste the
JSON into the ConfigMap, commit. Not pretty, but it survives Grafana pod
restarts and shows up in PR diffs.

## Dynatrace decisions

**cloudNativeFullStack.** OneAgent as a daemonset for host metrics plus
code-module injection through the operator's mutating webhook. Compared with
classic full stack (host-level injection) it's cleaner to roll back and doesn't
fight with read-only root filesystems. Compared with application-only you keep
the host view, which is what you want for capacity planning.

**CSI driver enabled.** Code modules are mounted from a per-node volume rather
than downloaded per pod. Pods start faster and you don't hammer the tenant on
a big rollout. Image volumes will replace this once the AKS version supports
them.

**Injection excluded from `monitoring`, `dynatrace`, `kube-system`.** Tracing
Prometheus scraping itself is noise and costs licence.

**ActiveGate with `routing` + `kubernetes-monitoring`.** OneAgents talk to the
ActiveGate, so only one component needs egress to the tenant. The
kubernetes-monitoring capability feeds the Kubernetes app in the Dynatrace UI
(workload / namespace / node views) without a separate agent.

## Known gaps

- No ingress controller. podinfo is reached via port-forward. In a real env
  this would be AGIC or nginx behind Application Gateway with WAF.
- No log pipeline into Prometheus-land (Loki). Logs go to Dynatrace and
  Container Insights.
- Alertmanager receivers are placeholders.
- Dynatrace tenant-side config (alerting profiles, management zones, tagging
  rules, SLOs) isn't in this repo. That's a Monaco project in its own right.
- Terraform state bootstrap (the storage account) is assumed to exist.
