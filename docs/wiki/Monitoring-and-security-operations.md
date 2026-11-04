# Monitoring, security events and operational evidence

## Monitoring domains

Prometheus and Grafana provide system/workload metrics; node exporters, cAdvisor/Kubernetes, Slurm host metrics, GPU exporter where installed, HAProxy, Cilium and storage dashboards explain different layers of a user-facing failure. Wazuh and Suricata add host and network security telemetry, not automatic proof of compromise or correct enforcement.

## Routine inspection

On the Kubernetes admin host, identify monitoring applications, Pods and provisioned dashboards:

```sh
kubectl -n argocd get applications
kubectl -n monitoring get pods
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

Use Git-managed Grafana dashboards, not one-off manual copies. An empty panel may reflect missing scrape targets, wrong labels, exporter permissions, no data or genuine availability loss. Check timestamps, cardinality and the correct metric source before concluding hardware is down. GPU telemetry and model token usage are not substitutes for schedulers' usage accounting.

## Incident classification

Separate outage, performance regression, security signal and scientific failure. Capture the time window, user-visible impact, affected namespace/host role, relevant alert series, deployment Git SHA and digest, scheduler run IDs, and a redacted symptom. Preserve original logs securely; never copy credentials, private addresses or user research content into a public dashboard screenshot/issue.

## Security enforcement

Provider SG, host nftables, Kubernetes Cilium policies, SSH/WireGuard, application authentication and ACP scopes implement different layers. Validate deny behavior, not only allowed behavior. IDS alerts should be correlated with system evidence and authorised response, not blindly treated as a reason for disruptive cluster restarts.

Sources: [security observability dashboards](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/argocd/resources/grafana/dashboards/wazuh-suricata-observability/README.md), [security drills](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/wazuh-suricata-operational-drills.md), [monitoring tutorial](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/04-05-06-lol-prometheus-grafana-gitops-observability.md).