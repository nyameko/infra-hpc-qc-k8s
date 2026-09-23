# Installation and Operations Guide

A complete deployment and operational guide for `infra-hpc-qc-k8s`.

This document is deliberately more detailed than the root README. It explains what is being deployed, why each layer exists, validation gates, failure modes and the operational path from bootstrap to the research platform.

---

# 1. Build in layers

The platform is intentionally built in acceptance-gated layers:

```text
OpenStack
  ↓
Rocky Linux hosts
  ↓
Network / edge security
  ↓
Kubernetes API load-balancer
  ↓
Container runtime
  ↓
Kubernetes
  ↓
Cilium
  ↓
OpenStack CCM / Cinder CSI
  ↓
Argo CD
  ↓
Prometheus / Grafana
  ↓
Wazuh / Siccata
  ↓
Slurm
  ↓
Private ingress / DNS
  ↓
PostgreSQL
  ↓
JupyterHub
  ↓
Hermes / Heretic
  ↓
Astro
```

Every arrow is an acceptance gate. A successful command is not itself proof of system health.

# 2. Reference network topology

```text
Management: 10.50.0.0/24
Kubernetes: 10.51.0.0/24
WireGuard:  10.60.0.0/24
```

Reference hosts:

```text
edge             10.50.0.10
hermes host      10.50.0.11
slurm controller 10.50.0.12
login1           10.50.0.20
login2           10.50.0.21
api-lb-01        10.51.0.100
k8s-cp-01        10.51.0.11
k8s-cp-02        10.51.0.12
k8s-cp-03        10.51.0.13
k8s-worker-01    10.51.0.21
k8s-worker-02    10.51.0.22
k8s-worker-03    10.51.0.23
```

The edge provides WireGuard, Pi-hole, nftables, Wazuh Manager and network security telemetry. The Kubernetes API is fronted by HAProxy at `10.51.0.100:6443`.

# 3. Security boundaries

OpenStack security groups and host firewalls are separate controls:

```text
OpenStack SG = what traffic may reach a VM?
nftables      = what traffic may the host accept/forward?
```

Kubernetes nodes do not have a host nftables/firewalld layer in this project unless explicitly added later. Do not apply edge firewall instructions to Kubernetes nodes.

Validate firewall configuration before loading it:

```bash
sudo nft -c -f /etc/nftables.conf
sudo nft list ruleset
```

Keep the recovery/console path available while changing host firewall policy.

# 4. Edge and WireGuard

WireGuard is the normal private administrative path:

```text
client 10.60.0.2
       ↓
edge 10.60.0.1
       ↓
10.50.0.0/24 + 10.51.0.0/24 + 10.60.0.0/24
```

Validate:

```bash
sudo wg show
ip addr show wg0
ip route
```

# 5. Pi-hole and DNS baseline

Pi-hole runs at the edge because DNS is foundational infrastructure.

```text
client / host
   ↓
edge :53
   ↓
Pi-hole
   ↓
upstream DNS
```

Validate:

```bash
sudo ss -lunpt | grep ':53'
dig @10.60.0.1 pi.hole
```

A DNS daemon being active is not proof that clients can resolve names. Test from the client network.

A Pi-hole GUI/password-rendering issue is tracked separately from the critical platform path; do not let that issue delay the rest of the deployment.

# 6. HAProxy: Kubernetes API endpoint

The Kubernetes API has a stable endpoint:

```text
10.51.0.100:6443
```

Validate the HAProxy host:

```bash
ssh api-lb-01
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl is-active haproxy
sudo ss -lntp | grep 6443
```

HAProxy SELinux policy must be adjusted narrowly if required; do not disable SELinux globally.

# 7. Kubernetes bootstrap

Kubernetes consists of three control planes and three workers. kubeadm owns cluster formation; Cilium owns cluster networking.

Validate:

```bash
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
```

# 8. Cilium baseline

Cilium is intentionally deployed conservatively before advanced features are introduced.

Current baseline:

```text
CNI
VXLAN
service networking
network policy foundation
Prometheus metrics
```

Deferred exercises:

```text
Hubble
kube-proxy replacement
ClusterMesh
advanced eBPF routing
advanced policy design
```

Validate:

```bash
cilium status --wait
cilium connectivity test --debug
```

The validated baseline has passed the current connectivity suite. Treat skipped tests separately from failures and understand why they were skipped.

# 9. OpenStack CCM and Cinder CSI

Persistent storage path:

```text
PVC
 ↓
StorageClass
 ↓
Cinder CSI
 ↓
OpenStack Cinder volume
 ↓
PV
 ↓
Pod
```

The persistence test must survive Pod recreation.

Likely consumers include Wazuh Indexer, Grafana, PostgreSQL, JupyterHub and user/application state.

# 10. Argo CD GitOps

Argo CD owns long-lived Kubernetes applications.

The canonical pattern is:

```text
argocd/applications/<app>.yml
          │
          ├── upstream Helm chart / vendor source
          ├── argocd/resources/<app>
          └── encrypted / sealed secrets
```

Use a flat child-Application directory where practical. Do not turn Ansible into a long-lived Kubernetes application installer.

Check application state with:

```bash
kubectl -n argocd get applications
```

Remember:

```text
Synced  = Git desired state applied
Healthy = resulting Kubernetes resources healthy
```

# 11. Prometheus and Grafana

Prometheus and Grafana are platform infrastructure because every later layer depends on operational visibility.

The current Prometheus application uses the prometheus-community Helm chart and repository-owned values. One important lesson from the deployment was that `extraScrapeConfigs` is a top-level chart value; placing it under `server` produced valid-looking YAML but did not render the scrape job.

The working HAProxy job is conceptually:

```yaml
extraScrapeConfigs: |
  - job_name: haproxy
    static_configs:
      - targets:
          - 10.51.0.100:8404
```

Validate the running configuration rather than trusting Git alone:

```bash
kubectl -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- http://127.0.0.1:9090/api/v1/status/config
```

And query actual targets directly.

## 11.1 Grafana GitOps dashboards

Dashboards live in:

```text
argocd/resources/grafana/dashboards/
```

The `grafana-dashboards` Argo Application deploys the ConfigMaps, which carry:

```text
grafana_dashboard=1
```

The Grafana sidecar consumes those ConfigMaps and provisions the dashboards.

Validate:

```bash
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

Do not manually import or maintain Git-managed dashboards in the Grafana UI.

## 11.2 Discovery jobs matter

Prometheus job names come from the scrape configuration, not from the product name.

Examples validated in this platform:

```text
HAProxy       → job="haproxy"
Cilium agent  → job="kubernetes-pods"
Cilium Envoy  → job="kubernetes-service-endpoints"
```

Therefore dashboard selectors must follow the live labels.

## 11.3 HAProxy dashboard validation

HAProxy exports server health as:

```promql
haproxy_server_status{state="UP"}
```

Backend aggregate health is available as:

```promql
haproxy_backend_agg_server_status{state="UP"}
```

Use the aggregate metric for a total server count and the per-server metric only when individual server dimensions are useful.

The current operational dashboard does not need an elaborate individual-backend-health chart if the aggregate availability and backend/frontend traffic panels are clearer.

# 12. Temporary GUI access

During bring-up, temporary access may use:

```text
kubectl port-forward
SSH local forwarding
```

This is a bootstrap technique, not the desired long-term architecture.

The final path will be:

```text
Cloudflare DNS / ACME
        ↓
Pi-hole private DNS where applicable
        ↓
HAProxy
        ↓
Traefik
        ↓
Kubernetes Service
```

Once this path is validated, remove normal-use GUI port-forwards and SSH tunnels.

# 13. Wazuh security plane

The existing edge Wazuh Manager is the security-plane anchor.

Current Manager state is intended to remain outside Kubernetes:

```text
edge
 └── Wazuh Manager
```

Kubernetes will add:

```text
Wazuh Indexer
Wazuh Dashboard
```

The Manager remains authoritative for agent communication and security event processing. The Indexer provides search/storage and the Dashboard provides Wazuh-native security analysis.

## 13.1 Wazuh agent networks

The current and future external compute nodes include additional Wazuh agents. The required manager ports are conceptually:

```text
1514/TCP  agent communication
1515/TCP  enrollment
55000/TCP Wazuh API / API-based enrollment
```

`1516/TCP` is a Wazuh Manager cluster port and is **not** required for ordinary agents. Keep it closed until a second Manager is intentionally introduced.

Open ports only from the networks that actually need them, in both OpenStack security groups and the edge nftables policy.

Future A100/H200 environments should join the same Manager via explicitly permitted network paths rather than introducing a second security architecture.

## 13.2 Security observability boundaries

```text
Wazuh
  → security events / host security / investigation

Siccata
  → IDS/IPS network events

Prometheus/Grafana
  → operational metrics / platform health / security telemetry
```

Grafana supplements, rather than replaces, the Wazuh Dashboard.

# 14. Slurm

Slurm remains outside Kubernetes and remains authoritative for HPC scheduling.

Initial topology:

```text
slurm-controller
   ├── login1
   ├── login2
   └── compute nodes
```

Validate:

```bash
sinfo
squeue
scontrol show nodes
```

The minimum acceptance gate is a partition with at least one usable node and a sample job that completes.

A Slurm Grafana dashboard should be added after the scheduler is operational.

# 15. PostgreSQL

PostgreSQL is the platform/application data and identity store for services that need durable relational state.

It is not the authority for external provider credentials.

The first operational deployment should establish:

```text
PostgreSQL
  ↓
platform/user database
  ↓
JupyterHub / Hermes / application metadata
```

Backups and HA remain later hardening concerns.

# 16. JupyterHub

JupyterHub provides researcher-facing interactive computing.

The intended resource model will allow notebooks and user environments to interact with Kubernetes and, through controlled integration, Slurm resources.

Quantum-computing toolkits and profiles belong here rather than in the infrastructure layer.

# 17. Hermes / Heretic

Hermes is an orchestration layer, not an unrestricted administrator.

The architecture separates:

```text
federation / infrastructure Hermes
        ↓
research Hermes in Kubernetes
        ↓
explicit least-privilege capabilities
```

External chat interfaces such as Telegram and Discord are planned as **liaison interfaces** to Hermes. They are not direct privileged infrastructure channels.

The Hermes capability model distinguishes:

```text
read
propose
approve
apply
```

The default posture is read/report. Destructive or infrastructure-changing operations require explicit capability scope and human approval.

Heretic remains the controlled execution/research complement to Hermes.

# 18. Astro

Astro is the user/research portal and the first user-facing end-to-end application milestone.

The target application path is:

```text
DNS
 ↓
HAProxy
 ↓
Traefik
 ↓
Astro
 ↓
platform services / Hermes / APIs
```

# 19. DNS and Cloudflare

The private path should not require public exposure merely to resolve internal services.

Target model:

```text
Cloudflare
  → public DNS / ACME DNS-01

Pi-hole
  → private DNS overrides

HAProxy
  → private ingress VIP

Traefik
  → Kubernetes services
```

Cloudflare API credentials should be narrowly scoped and kept outside Git.

# 20. GPU/QPU accounting templates

Create schemas and dashboard interfaces early, but defer detailed accounting implementation until identity, Slurm and Hermes provide authoritative attribution.

Conceptual dimensions:

```text
user
project
job
resource
allocation
start/end time
runtime
consumption
```

GPU additions:

```text
GPU ID
GPU memory
GPU time
node
job
user
project
```

QPU additions:

```text
provider
backend
QPU time
shots
circuit executions
job
user
project
```

# 21. Final acceptance gates

## Infrastructure

```bash
openstack server list
openstack network list
openstack security group list
```

## Ansible

```bash
ansible-inventory -i inventories/private/hosts.yml --graph
ansible all -i inventories/private/hosts.yml -m ping
```

## Edge

```bash
sudo nft list ruleset
sudo wg show
systemctl is-active wazuh-manager
systemctl is-active haproxy
```

## Kubernetes

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw='/readyz?verbose'
```

## Cilium

```bash
cilium status --wait
cilium connectivity test --debug
```

## Storage

```bash
kubectl get storageclass
kubectl get csidrivers
```

## Prometheus/Grafana

```bash
kubectl -n argocd get applications
kubectl -n monitoring get pods
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

## Slurm

```bash
sinfo
squeue
scontrol show nodes
```

# 22. Troubleshooting method

Diagnose from the outside in:

```text
Cloud
  ↓
OpenStack SG / port / route
  ↓
VM / OS
  ↓
firewall / SELinux / systemd
  ↓
TCP / UDP / socket
  ↓
container runtime / CRI
  ↓
Kubernetes
  ↓
Cilium
  ↓
service
  ↓
application
  ↓
Prometheus metric
  ↓
Grafana query
```

The project deliberately preserves real incidents as teaching material. Examples include OpenStack security-group scoping, HAProxy SELinux policy, package provenance, CRI permissions, Cinder secret/config mismatches and dashboard queries that did not match the live metric schema.

# 23. Production hardening still required

Before treating the platform as a production multi-user research service, review:

- HA for single-instance services
- backup/restore tests
- credential rotation
- stronger secret management where justified
- certificate and key rotation
- Cilium policy defaults
- ingress/TLS hardening
- PostgreSQL backups/HA
- Cinder backup strategy
- Wazuh sizing and retention
- Prometheus/Grafana retention and persistence
- Slurm controller/database HA
- public DNS/Cloudflare policy
- disaster recovery
- account lifecycle and RBAC


# 24. Wazuh & Suricata — completed reference security sprint

The detailed, replayable sequence lives in [Wazuh & Suricata deployment](tutorials/wazuh-suricata-deployment.md); [operational drills](tutorials/wazuh-suricata-operational-drills.md) covers common failures and an evidence template. Read these alongside sections 3, 10, 11 and 13 above. The security path is **edge Wazuh Manager → alerts.json → staged and then TLS-enabled Filebeat → private Cinder-backed Wazuh Indexer → private Dashboard**; edge Suricata 8 emits EVE JSON into that Manager, not directly into Grafana.

At the 23 September 2026 acceptance checkpoint the Manager reported 14 Active identities (including its local identity); the benign Suricata SID 9900001 was correlated to Wazuh rule 86601 and a searchable alert in `wazuh-alerts-4.x-2026.09.23`. This is historical verification, not a current cluster-health or backup claim. Indexer availability, authentication, durable retention and restore must be checked individually. The `wazuh` Argo Application currently targets `main`; merging the tutorial into `dev` does not reconfigure that live application. Keep edge nftables separate from non-edge OpenStack security-group enforcement.
