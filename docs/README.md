# infra-hpc-qc-k8s — Documentation

> Infrastructure-as-Code and GitOps for a hybrid **HPC + Kubernetes + AI/ML + quantum-computing** research platform.

The documentation is intentionally layered:

```text
README.md
  ↓
What is this? What is the architecture? What is the current state?

QUICK_GUIDE.md
  ↓
What commands do I run?

INSTALLATION.md
  ↓
What am I doing, why, and how do I validate it?

TUTORIALS/
  ↓
What should I learn from the platform?
```

## Documentation map

| Document | Purpose |
|---|---|
| `README.md` | Project identity, architecture, current state and roadmap |
| `docs/README.md` | Documentation navigation and ownership model |
| `docs/QUICK_GUIDE.md` | Command-first deployment / operations |
| `docs/INSTALLATION.md` | Complete deployment, rationale, validation and troubleshooting |
| `docs/tutorials/README.md` | Teaching pack and module reading order |
| `docs/tutorials/COURSE_OUTLINE.md` | Course structure, workshop/checklist model and capstone |

## Design principle: separation of concerns

The documentation uses the same ownership boundaries as the implementation:

| Layer | Owner | Responsibility |
|---|---|---|
| Cloud | Terraform | OpenStack networks, ports, SGs, VMs and cloud resources |
| Host | Ansible | Rocky Linux, packages, services, hardening and infrastructure daemons |
| Cluster bootstrap | kubeadm | Kubernetes control-plane and worker formation |
| Cluster networking | Cilium | CNI, service networking, network policy and Cilium telemetry |
| Persistent storage | Cinder CSI | Kubernetes ↔ OpenStack Cinder |
| Kubernetes apps | Argo CD | GitOps reconciliation of long-lived applications |
| Metrics | Prometheus | Metrics collection and querying |
| Dashboards | Grafana | Operational visualization and platform dashboards |
| Security | Wazuh / Siccata | Security events and IDS/IPS telemetry |
| HPC | Slurm | Scheduling and execution of HPC workloads |
| Research apps | JupyterHub / Hermes / Astro | Interactive computing, orchestration and portal |

Do not move responsibility across layers just because another tool can technically perform the work.

## Current deployment state

The foundational path is operational:

```text
OpenStack
  ↓
Rocky Linux
  ↓
Edge security + WireGuard + Pi-hole + Wazuh Manager + Suricata/Siccata
  ↓
HAProxy API VIP
  ↓
Kubernetes
  ↓
Cilium
  ↓
Cinder CSI
  ↓
Argo CD
  ↓
Prometheus + Grafana
```

The Kubernetes API remains on `10.51.0.100:6443` through HAProxy. The later application-ingress path is separate:

```text
private/public DNS
  ↓
HAProxy application ingress
  ↓
Traefik
  ↓
Kubernetes Services
```

During the bring-up period, selected UIs used temporary `kubectl port-forward` and SSH tunnels. Those are transitional bootstrap tools and should disappear from normal operations after the DNS/ingress milestone.

## Observability milestone

Prometheus/Grafana is now a first-class platform layer.

Git owns dashboards under:

```text
argocd/resources/grafana/dashboards/
```

Argo CD deploys the dashboard ConfigMaps, and Grafana's dashboard sidecar provisions them. The current dashboard family includes:

```text
platform-overview
kubernetes
nodes
cadvisor
cilium
envoy
haproxy
prometheus
storage
```

The operating rule is:

> Dashboard queries must be validated against the live metric names, labels and discovery jobs before a dashboard is considered authoritative.

## Security observability model

Keep these concerns separate:

- **Wazuh:** security events, host security, integrity, vulnerabilities and agent/security investigation.
- **Siccata:** IDS/IPS network events and signatures.
- **Prometheus/Grafana:** service health, infrastructure metrics, Cilium telemetry, resource usage and operational security indicators.
- **Wazuh Dashboard:** security investigation and Wazuh-native security workflows.
- **Grafana:** cross-platform operational/security health, not a replacement for Wazuh.

## Platform roadmap

### Security + HPC first

1. Wazuh Manager completion
2. Wazuh Indexer
3. Wazuh Dashboard
4. Siccata IDS/IPS
5. Prometheus/Grafana security dashboards
6. Slurm completion
7. Slurm Grafana dashboard

### Private ingress and DNS second

1. HAProxy application ingress
2. Traefik
3. Pi-hole private DNS
4. Cloudflare DNS / ACME
5. end-to-end private ingress
6. remove remaining normal-use port-forwards and SSH tunnels

### Research platform third

1. PostgreSQL user/platform database
2. JupyterHub
3. Hermes Orchestrator
4. Heretic controlled execution
5. Astro portal
6. Telegram/Discord liaison integrations for Hermes
7. AI/ML and quantum workloads

### Accounting later

Create interfaces/templates early, but defer full accounting until identity and scheduling are authoritative:

```text
CPU / HPC
GPU
QPU
```

## Hermes / Heretic documentation boundary

Hermes is an orchestration system, not an unrestricted root account.

The intended model is:

```text
external message
   ↓
Telegram / Discord liaison
   ↓
Hermes
   ↓
explicit capability
   ↓
read / propose / approve / apply
```

The infrastructure Hermes should default to read/report behavior. Research Hermes can operate inside Kubernetes with separate credentials and storage. Heretic provides controlled execution/research capabilities. External chat integrations must not become direct privileged infrastructure channels.

## Troubleshooting method

When a component fails, classify the failure first:

```text
OpenStack
  ↓
Security group / port / route
  ↓
VM / OS
  ↓
nftables / SELinux / systemd
  ↓
TCP / UDP / socket
  ↓
container runtime / CRI
  ↓
Kubernetes
  ↓
Cilium
  ↓
Service / application
  ↓
Prometheus metric / Grafana query
```

Inspect actual runtime state before adding another framework.

## Teaching use

The tutorials deliberately preserve real failures and debugging lessons. The course format is based on a lecture + workshop + checklist + deliverable pattern suitable for intensive student-cluster or semester delivery.
