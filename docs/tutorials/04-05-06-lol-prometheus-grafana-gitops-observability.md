# Tutorial — Prometheus & Grafana: GitOps Observability from Metrics to Dashboards

## Purpose

This tutorial deploys and validates Prometheus and Grafana as the platform observability layer for `infra-hpc-qc-k8s`, using Argo CD as the GitOps control plane and Git-managed Grafana dashboards as Kubernetes `ConfigMap` resources.

The goal is not merely to make Grafana display graphs. The tutorial teaches the complete path from exporter → Prometheus discovery/scrape → PromQL → Grafana provisioning → Argo CD reconciliation, including how to diagnose cases where a component is healthy but a dashboard query is wrong.

## Architecture

```text
                         GitHub
                           │
                           ▼
                        Argo CD
                           │
          ┌────────────────┴────────────────┐
          │                                 │
          ▼                                 ▼
    Prometheus Application          Grafana Application
          │                                 │
          │                         dashboard sidecar
          │                                 │
          ▼                                 ▼
    Prometheus Server              Grafana Dashboard ConfigMaps
          │                                 │
          ├── Kubernetes discovery          │
          ├── cAdvisor                     │
          ├── Cilium agent                 │
          ├── Cilium Envoy                 │
          └── HAProxy :8404                 │
                    │                        │
                    └───────────┬────────────┘
                                ▼
                         Grafana dashboards
```

The repository separates the concerns deliberately:

```text
argocd/
├── applications/
│   ├── prometheus.yml
│   ├── grafana.yml
│   ├── grafana-config.yml
│   └── grafana-dashboards.yml
│
└── resources/
    ├── prometheus/
    │   └── values.yaml
    └── grafana/
        ├── values.yaml
        ├── config/
        └── dashboards/
```

## 1. Deploy Prometheus with Argo CD

Prometheus is installed from the `prometheus-community/prometheus` Helm chart. The repository keeps the chart version pinned and supplies the repository's values through Argo CD's multi-source Application.

The important distinction is that chart values must be placed at the level expected by the chart. In particular, `extraScrapeConfigs` is a chart-level value, not `server.extraScrapeConfigs`.

The HAProxy scrape configuration is therefore:

```yaml
server:
  global:
    scrape_interval: 30s
    evaluation_interval: 30s

extraScrapeConfigs: |
  - job_name: haproxy
    static_configs:
      - targets:
          - 10.51.0.100:8404
```

A valid Prometheus configuration does not prove that the target is reachable. Validate the complete path.

```bash
curl -s http://10.51.0.100:8404/metrics | head
```

Then ask Prometheus whether it has the target:

```bash
kubectl -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- \
  'http://127.0.0.1:9090/api/v1/query?query=up%7Bjob%3D%22haproxy%22%7D'
```

A healthy result has an `up` series with value `1`.

### Lesson: Git state is not enough

If Git contains the configuration but the running Prometheus configuration does not, inspect the rendered/live configuration rather than assuming Argo is broken:

```bash
kubectl -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- http://127.0.0.1:9090/api/v1/status/config \
  | jq -r '.data.yaml' \
  | grep -n -A8 -B3 haproxy
```

This distinguishes Git/Helm rendering problems from networking/exporter problems.

## 2. Deploy Grafana and its Prometheus datasource

Grafana is deployed by its own Argo CD Application. The Prometheus datasource is provisioned declaratively rather than added manually through the Grafana UI.

The important properties are:

```yaml
service:
  type: ClusterIP

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus-server.monitoring.svc.cluster.local
        isDefault: true
        editable: false
```

This keeps the datasource part of the reproducible platform definition.

## 3. GitOps-managed dashboards

Dashboards are ordinary Kubernetes `ConfigMap` objects, managed by a dedicated Argo CD Application:

```text
argocd/resources/grafana/dashboards/
├── platform-overview.yaml
├── kubernetes.yaml
├── nodes.yaml
├── cadvisor.yaml
├── cilium.yaml
├── envoy.yaml
├── haproxy.yaml
├── prometheus.yaml
└── storage.yaml
```

Each dashboard ConfigMap is labelled:

```yaml
metadata:
  labels:
    grafana_dashboard: "1"
```

The Grafana sidecar watches that label and provisions the dashboards. The sidecar provider name, such as `gitops-dashboards`, is an internal Grafana provisioning-provider name; it does not need to match the Kubernetes label or Argo Application name.

### Verify the GitOps dashboard resources

```bash
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

All nine dashboard ConfigMaps should appear.

### Verify Grafana

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana
```

The Grafana pod should be Ready with both Grafana and its dashboard sidecar containers running.

## 4. Understanding Prometheus discovery jobs

One of the most important lessons from this deployment is that a component name is not necessarily the Prometheus `job` label.

For this cluster:

```text
HAProxy exporter:
  job="haproxy"

Cilium agent:
  job="kubernetes-pods"
  app_kubernetes_io_name="cilium-agent"
  port=9962

Cilium Envoy:
  job="kubernetes-service-endpoints"
  service="cilium-envoy"
  app_kubernetes_io_name="cilium-envoy"
  port=9964
```

The live Cilium agent query returns six agents on the six Kubernetes nodes. Cilium Envoy is separately discovered through Kubernetes service endpoints on port 9964.

### Cilium agents

```promql
sum(
  up{
    job="kubernetes-pods",
    namespace="kube-system",
    app_kubernetes_io_name="cilium-agent",
    instance=~".*:9962"
  }
)
```

### Cilium agent scrape health

For a per-agent dashboard panel:

```promql
up{
  job="kubernetes-pods",
  namespace="kube-system",
  app_kubernetes_io_name="cilium-agent",
  instance=~".*:9962"
}
```

Use `{{instance}}` as the legend.

### Cilium Envoy targets

```promql
sum(
  up{
    job="kubernetes-service-endpoints",
    namespace="kube-system",
    app_kubernetes_io_name="cilium-envoy",
    service="cilium-envoy",
    instance=~".*:9964"
  }
)
```

### Cilium Envoy target health

For per-node health:

```promql
up{
  job="kubernetes-service-endpoints",
  namespace="kube-system",
  app_kubernetes_io_name="cilium-envoy",
  service="cilium-envoy",
  instance=~".*:9964"
}
```

Use `{{node}}` or `{{instance}}` as the legend.

Cilium's metrics documentation describes agent metrics on 9962 and Envoy metrics on 9964, and the deployment's live Prometheus labels confirm that distinction.

## 5. HAProxy / Ingress dashboard validation

HAProxy exposes metrics at:

```text
http://10.51.0.100:8404/metrics
```

Prometheus scrapes this endpoint through the explicit `haproxy` job.

### Exporter health

```promql
up{job="haproxy"}
```

### Servers UP

The correct exporter metric is the per-backend aggregate metric:

```promql
sum(haproxy_backend_agg_server_status{state="UP"})
```

### Per-server Backend Server Health

For individual Kubernetes control-plane and Traefik servers, use:

```promql
haproxy_server_status{state="UP"}
```

with:

```text
{{proxy}} / {{server}}
```

This is preferable to the aggregate metric because it exposes the actual server dimension.

### Important JSON/YAML quoting rule

Because the dashboard JSON is embedded inside a YAML block scalar, the PromQL string still has to be valid JSON. This is wrong:

```yaml
"expr": "sum(haproxy_backend_agg_server_status{state="UP"})"
```

This is correct:

```yaml
"expr": "sum(haproxy_backend_agg_server_status{state=\"UP\"})"
```

The same escaping is required for:

```yaml
"expr": "haproxy_server_status{state=\"UP\"}"
```

A YAML file can parse successfully while its embedded dashboard JSON is invalid. That can prevent the dashboard sidecar from accepting the updated dashboard, leaving Grafana showing an older provisioned copy.

## 6. cAdvisor filesystem metrics

The deployment does expose `container_fs_usage_bytes`, but the live series show labels such as:

```text
instance
job
metrics_path
device
id
node-related Kubernetes labels
```

and do not expose `namespace`, `pod`, and `container` on the filesystem series used by the current query.

Therefore this query returns no result:

```promql
sum by(namespace,pod,container) (
  container_fs_usage_bytes{
    container!="",
    container!="POD"
  }
)
```

That is a dashboard-query mismatch, not proof that cAdvisor is broken.

A useful teaching panel for the current deployment can instead show node/filesystem usage using the labels actually present, or the dashboard can explicitly document that per-container filesystem attribution is not available from the current cAdvisor series.

Do not install another cAdvisor instance simply to make this panel produce data.

## 7. Prometheus dashboard design

A panel named `Scrape Sample Limit Usage` is misleading when no per-target sample limit has been configured.

Use `scrape_samples_scraped` for the current platform instead:

```promql
scrape_samples_scraped
```

or aggregate by job:

```promql
sum by(job) (scrape_samples_scraped)
```

Rename the panel to `Scrape Samples`.

A future tutorial can add sample-limit utilisation once explicit limits are introduced as a platform policy.

## 8. How dashboard changes reach Grafana

The normal GitOps path is:

```text
Edit dashboard YAML
        ↓
Commit / push to main
        ↓
Argo CD detects revision
        ↓
grafana-dashboards Application syncs
        ↓
ConfigMap changes in monitoring namespace
        ↓
Grafana dashboard sidecar detects ConfigMap
        ↓
Dashboard is re-provisioned
```

Verify the Argo Application:

```bash
kubectl -n argocd get application grafana-dashboards
```

Verify the ConfigMap:

```bash
kubectl -n monitoring get configmap grafana-dashboard-haproxy -o yaml
```

If the ConfigMap contains the new dashboard but Grafana still shows the old dashboard, inspect the sidecar logs:

```bash
kubectl -n monitoring logs deploy/grafana -c grafana-sc-dashboard
```

A malformed embedded JSON document is a particularly important failure mode to check.

## 9. Validation exercise

The observability stack is considered healthy only when all three layers agree:

### Layer 1 — exporter

The component actually exposes metrics.

```bash
curl -s http://10.51.0.100:8404/metrics | grep '^haproxy_' | head
```

### Layer 2 — Prometheus

Prometheus can scrape and query the metrics.

```promql
up{job="haproxy"}
```

### Layer 3 — Grafana

The dashboard queries the same metric names and label model that Prometheus actually provides.

This distinction is the core observability lesson:

```text
Exporter healthy ≠ Prometheus scraping healthy
Prometheus scraping healthy ≠ dashboard query correct
Dashboard present ≠ dashboard data correct
```

## 10. Success criteria

The deployment is complete when:

- Prometheus is `Synced/Healthy` in Argo CD.
- Grafana is `Synced/Healthy` in Argo CD.
- `grafana-dashboards` is `Synced/Healthy` in Argo CD.
- Nine dashboard ConfigMaps exist in `monitoring`.
- Prometheus reports HAProxy `up == 1`.
- HAProxy reports all three Kubernetes control-plane servers as `UP`.
- HAProxy reports all three Traefik HTTP servers as `UP`.
- HAProxy reports all three Traefik HTTPS servers as `UP`.
- Six Cilium agent metric targets are scrapeable.
- Six Cilium Envoy metric targets are scrapeable.
- Grafana displays the Git-managed dashboards without manual dashboard imports.

## 11. Troubleshooting checklist

### Grafana dashboard exists but shows old queries

```bash
kubectl -n monitoring get configmap grafana-dashboard-haproxy -o yaml
```

Then inspect the Grafana dashboard sidecar logs.

### Prometheus target is absent

Check the Prometheus generated configuration:

```bash
kubectl -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- http://127.0.0.1:9090/api/v1/status/config \
  | jq -r '.data.yaml'
```

### A metric exists but a dashboard panel is empty

Query the raw metric directly:

```promql
metric_name
```

Then inspect its labels with:

```promql
metric_name{}
```

Do not assume that labels such as `namespace`, `pod`, `container`, `service`, or `job` exist simply because they would be useful.

## 12. What this teaches

This deployment establishes the platform observability baseline required before the next major services are introduced.

It also establishes a repeatable GitOps pattern that later platform components can follow:

```text
Application Helm values → Argo CD
Runtime secrets/config → Argo CD resources
Dashboards → Git-managed ConfigMaps
Metrics → Prometheus discovery/scraping
Visualization → Grafana sidecar provisioning
Validation → PromQL + kubectl + exporter endpoints
```

This becomes the observability foundation for Wazuh/Siccata, Slurm, JupyterHub, Hermes, and Astro.
