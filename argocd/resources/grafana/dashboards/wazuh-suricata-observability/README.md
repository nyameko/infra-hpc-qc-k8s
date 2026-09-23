# Wazuh and Suricata Observability

Additive, Git-managed dashboards for the existing `infra-hpc-qc-k8s` monitoring stack. This folder is deliberately independent of the existing Quantum Platform and general Kubernetes/HAProxy dashboards. Its ConfigMaps are discovered by the already deployed Grafana dashboard sidecar using the `grafana_dashboard: "1"` label.

## Grafana folder

All four ConfigMaps set `metadata.annotations["k8s-sidecar-target-directory"]` to **Wazuh and Suricata Observability**. Grafana's existing dashboard provider has `foldersFromFilesStructure: true`; `argocd/resources/grafana/values.yaml` explicitly enables the corresponding folder annotation. The sidecar writes these dashboard JSON files under a dedicated filesystem subfolder; Grafana provisions that as one UI folder. Existing dashboard files/ConfigMaps remain untouched.

## Dashboard inventory and *data provenance*

| Dashboard | Currently supported by live metrics | Not yet measured by Prometheus |
| --- | --- | --- |
| **Traefik — Security Ingress** | Traefik reload status, HTTP/TLS request rate, latency, routers, connections and certificate expiry from the observed `traefik_*` metric families. | Any Suricata sensor packet counter; do not conflate an HTTP 5xx with a Suricata alert. |
| **Wazuh Operations — Indexer & Ingestion** | Indexer/Dashboard Kubernetes readiness, Indexer container CPU/RAM, restarts, PVC Bound state; kubelet PVC use/capacity *only if available*. | Authenticated OpenSearch JVM heap/GC, cluster/shards/indexing failures, Filebeat publish failures, Wazuh Manager service health and agent-connected counts. |
| **Suricata IDS — Edge** | Explicit sensor identity and the verified EVE → Wazuh alert chain; contextual Traefik ingress/PVC state. | Sensor packets/s, capture/kernel drops, flows/s, signature rate and Suricata resource use **until an actual Suricata exporter is scraped**. |
| **Host Security & Availability — OpenStack** | Kubernetes node readiness and existing node-exporter CPU/RAM/filesystem on **the six Kubernetes nodes**. | Node-exporter/service status for edge, api-lb, Slurm and Hermes; live Wazuh agent status for all fourteen hosts until a dedicated Manager-derived exporter is introduced. |

The recorded 23 September 2026 acceptance evidence is **14 Active Wazuh identities, 0 inactive, 13 remote agents reporting `connected`, and zero duplicate names**. That is a *point-in-time verification*, not a current metric and is never plotted as one. Suricata 8.0.7 on `edge/eth0` emitted SID `9900001`; Wazuh Manager emitted rule `86601` and the exact alert ID `1790160649.584653` was found in `wazuh-alerts-4.x-2026.09.23`.

## Scope and security boundaries

- **Sensor identity:** only `edge` currently runs Suricata. Do not render all fourteen machines as Suricata sensors.
- **Wazuh is event evidence, Prometheus/Grafana is operational metrics.** Do not add alert payloads, VPN identities, secrets, research data or unbounded cardinality to Prometheus labels.
- **No fake metrics:** missing exporters are documented in text panels; a zero exporter-target count means the job is not configured or has no UP target, *not* that the IDS or host process has failed.
- **Backend health:** a TCP-ready Indexer container is not proof of OpenSearch cluster health; an `up` node exporter is not proof of Wazuh agent health.
- **No new ingress or public ports** are introduced by this dashboard-only PR.
- **No retention or backup change** is included. Raw EVE and Wazuh JSON rotation plus Indexer snapshots are tracked in issue #15. Sensor/NAT identity attribution is tracked in issue #17.
- Kubernetes audit, Cilium/Hubble, runtime and admission-policy event collection remains separate from pod-per-agent installation and from this dashboard-only change.

## Deployment and acceptance

The existing `grafana-dashboards` Argo CD Application recursively watches `argocd/resources/grafana/dashboards`. The Grafana chart consumes `argocd/resources/grafana/values.yaml`. Both Applications currently target `main`, so **merging this PR into `dev` does not automatically deploy the dashboards to the live environment**. Promote via the agreed branch/GitOps process or, after approval, use a controlled dev-tracking staging Application. Do not silently change `targetRevision` or merge directly to main.

Review from the repo root:

```bash
kubectl apply --dry-run=client -f argocd/resources/grafana/dashboards/wazuh-suricata-observability/
git diff --check dev...feature/wazuh-suricata-observability-dashboards
```

Once the intended Argo CD environment tracks this revision, verify:

```bash
kubectl -n monitoring get configmap -l grafana_dashboard=1
kubectl -n argocd get application grafana grafana-dashboards
```

In Grafana confirm all four dashboards appear inside **Wazuh and Suricata Observability**, existing dashboards remain in their previous folders, the Traefik and Kubernetes panels show current data, and unavailable exporter panels are explicitly documented rather than given synthetic values.

## Next increments (separate reviewed PRs)

1. Expose restricted Suricata exporter metrics on `edge` and verify actual names and labels before adding packet/flow/drop/RSS PromQL. Include capture drops versus future IPS verdicts and consider SELinux/OpenStack SG access.
2. Add an authenticated Indexer metrics exporter and a secure way to obtain Wazuh Manager/agent health plus Filebeat publishing failures; verify metrics and test alerts.
3. Install restricted host exporters/service-health collectors on the non-Kubernetes OpenStack hosts; use inventory-derived scrape labels. Join the Manager-derived Wazuh agent status to canonical inventory hostname.
4. Build and verify the full fourteen-host view, add sensible per-host resource limits and controlled alerts. Test retention, backup and restore in issue #15.
