# Runbook

Short, because long runbooks don't get read at 3am. Each alert links here via
`runbook_url`.

General first steps for anything in the `podinfo` namespace:

```bash
kubectl -n podinfo get pods -o wide
kubectl -n podinfo describe deploy podinfo | sed -n '/Conditions/,/Events/p'
kubectl -n podinfo logs deploy/podinfo --since=15m | tail -100
```

And open the `podinfo / golden signals` dashboard in Grafana and the service
in Dynatrace (Services → podinfo → Service flow).

---

## PodinfoHighErrorRate

**Fires when:** >5% of requests return 5xx for 5 minutes. `critical`, pages.

**Likely causes, most common first**

1. Bad deploy. `kubectl -n podinfo rollout history deploy/podinfo`. If a
   rollout happened in the last ~30 min, roll back first, investigate second:
   `kubectl -n podinfo rollout undo deploy/podinfo`.
2. Dependency down. podinfo has none, but a real service does. In Dynatrace
   open the service flow and look for the downstream node that turned red;
   Davis will usually have a problem card already correlating it.
3. Pods crashlooping and the survivors are overloaded. See PodinfoPodRestarting.
4. Resource limits. Memory limit hit → OOMKilled → restarts → errors while
   replacement pods warm up. `kubectl -n podinfo get pods` and look for
   `OOMKilled` in last state.

**Verify fixed:** error ratio panel back under 1%, alert resolves after 5 min.

---

## PodinfoLatencyP95High

**Fires when:** p95 > 500ms for 10 minutes. `warning`, ticket.

**Check**

1. Is it all requests or one endpoint? In Dynatrace, service → Response time
   → analyze by request. In Grafana the latency panel is aggregate; if you need
   per-path, query `histogram_quantile(0.95, sum by (le, path) (rate(http_request_duration_seconds_bucket{job="podinfo"}[5m])))`.
2. CPU throttling. `container_cpu_cfs_throttled_periods_total` rising for the
   pods, or the CPU panel pinned at the request line. If the HPA is already at
   max (PodinfoHPAAtMax will also be firing) raise `maxReplicas` or the CPU
   request.
3. Node pressure. `kubectl top nodes`; if the apps pool is saturated and the
   autoscaler isn't adding nodes, check the cluster-autoscaler logs in Log
   Analytics (`AzureDiagnostics | where Category == "cluster-autoscaler"`).
4. A PurePath with a slow span. Pick a slow request in Dynatrace and read the
   waterfall. This is usually where the real answer is for a non-trivial app.

**Verify fixed:** p95 panel under 300ms for 10 min.

---

## PodinfoPodRestarting

**Fires when:** a container restarted more than 3 times in 30 minutes.
`warning`.

```bash
kubectl -n podinfo get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState}'
kubectl -n podinfo logs <pod> --previous | tail -50
```

- `OOMKilled` → memory limit too low or a leak. Compare working set panel
  against the limit line. Bump the limit to stop the bleeding, then find out why.
- `Error` with exit code 1/2 → app crash; the previous logs will say.
- Liveness probe failures in `describe pod` events → either the app is
  genuinely hanging or the probe timeout is too tight for a cold start. Don't
  just loosen the probe without knowing which.

---

## PodinfoNoTraffic

**Fires when:** zero requests for 15 minutes.

For the lab this just means nobody is running `make load`. For a real service
it's usually ingress or DNS, not the app:

1. Service endpoints populated? `kubectl -n podinfo get endpoints podinfo`.
   Empty → readiness probe failing or label selector mismatch.
2. Ingress / gateway healthy? Not in this repo, but that's where to look next.
3. Upstream of you (API gateway, WAF) blocking? Check their dashboards.

---

## PodinfoHPAAtMax

**Fires when:** the HPA has been at `maxReplicas` for 15 minutes.

Not an outage, but you've got no headroom. Decide: raise `maxReplicas` (and
check the apps pool `user_node_max` can actually fit them), or find out why CPU
is high. If latency is fine and errors are fine, raise the ceiling and move on;
if they're not, this alert is a symptom and the latency runbook applies.

---

## NodeNotReady

**Fires when:** a node reports NotReady for 5 minutes. `critical`.

```bash
kubectl get nodes
kubectl describe node <node> | sed -n '/Conditions/,/Addresses/p'
```

- `MemoryPressure` / `DiskPressure` true → something on the node is eating
  resources. `kubectl get pods -A --field-selector spec.nodeName=<node>` and
  look for pods without limits.
- Kubelet stopped posting status → VM-level problem. Check the VMSS instance
  in the node resource group (`obsplat-dev-aks-nodes-rg`) in the portal or
  `az vmss get-instance-view`. Often fastest to just reimage:
  `az vmss reimage --instance-ids <id> -g <node-rg> -n <vmss>`.
- Node image upgrade in progress → it's expected, the alert will resolve.
  `kubectl get nodes -L kubernetes.azure.com/node-image-version`.

If pods on the node are stuck Terminating after it comes back, cordon + drain
and let the autoscaler replace it.

---

## PersistentVolumeFillingUp

**Fires when:** <15% free and the 6h trend says full within 24h.

Almost always Prometheus or Alertmanager in this cluster.

- Prometheus: `retentionSize` is set to 45GB on a 50Gi PVC, so it should
  self-limit. If it's still filling, something changed the PVC size or the
  values. Short-term: `kubectl -n monitoring edit prometheus kps-prometheus`
  and lower retention. Long-term: resize the PVC (managed-csi supports online
  expansion) and bump the values file.
- Anything else: find the pod via
  `kubectl get pvc -A | grep <claim>`, then it's app-specific.

---

## PrometheusTargetDown

**Fires when:** a scrape target we care about has been down 10 minutes.

- `job="podinfo"` → the ServiceMonitor can't reach `:9797`. Pod not ready, or
  a network policy got added that blocks `monitoring` → `podinfo`.
- `kube-state-metrics` / `node-exporter` → the component itself. Check the
  pod in `monitoring`. Node-exporter on one node down usually means that node
  is unhealthy; see NodeNotReady.

Prometheus → Status → Targets shows the exact scrape error.
