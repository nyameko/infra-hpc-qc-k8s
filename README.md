# infra-hpc-qc-k8s

Infrastructure-as-Code and GitOps platform for hybrid HPC, Kubernetes, AI/ML and quantum-computing research.

`infra-hpc-qc-k8s` is a reproducible, teachable and recoverable platform stack. It is deliberately built as a set of independently owned layers rather than as one monolithic installer:

- **Terraform** owns OpenStack infrastructure.
- **Ansible** owns host configuration and infrastructure services.
- **kubeadm** owns Kubernetes cluster bootstrap.
- **Cilium** owns Kubernetes networking and network policy.
- **Cinder CSI** provides persistent OpenStack-backed storage.
- **Argo CD** owns long-lived Kubernetes applications.
- **Prometheus/Grafana** own platform observability.
- **Wazuh/Siccata** own the security telemetry plane.
- **Slurm** remains authoritative for HPC scheduling.
- **PostgreSQL** stores platform identity and application state.
- **JupyterHub** provides researcher-facing interactive environments.
- **Hermes/Heretic** provide controlled intelligent orchestration and execution workflows.
- **Astro** provides the user/research portal.

The repository is both an infrastructure implementation and a teaching platform: failures, debugging paths, acceptance tests and design trade-offs are part of the material.

## Current status

The foundational platform is operational through the following layers:

```text
OpenStack
  ↓
Rocky Linux hosts
  ↓
Edge security / WireGuard / Pi-hole / Wazuh Manager / Suricata
  ↓
HAProxy Kubernetes API endpoint
  ↓
3-control-plane + 3-worker Kubernetes cluster
  ↓
Cilium
  ↓
OpenStack CCM + Cinder CSI
  ↓
Argo CD
  ↓
Prometheus + Grafana
  ↓
Git-managed Grafana dashboards
```

The reference Kubernetes cluster currently has three control planes and three workers, with Kubernetes 1.36.4, containerd 2.3.4 and Cilium 1.20.1. The Kubernetes API is served through the stable HAProxy VIP `10.51.0.100:6443`.

Cilium baseline connectivity testing has passed. The current observability implementation also includes Prometheus/Grafana GitOps dashboards for Kubernetes, nodes, cAdvisor, Cilium, Envoy, HAProxy, Prometheus and storage. The dashboards are provisioned as labelled ConfigMaps and consumed by the Grafana sidecar rather than imported manually.

## Architecture

```text
                         GitHub
                    ┌─────────────┐
                    │ repository  │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
          Terraform                  Ansible
              │                         │
              ▼                         ▼
         OpenStack                 Rocky Linux
              │                         │
              └────────────┬────────────┘
                           ▼
                    Kubernetes + Slurm
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
     Cilium             Argo CD          Wazuh/Siccata
        │                  │                  │
        │          ┌───────┼────────┐         │
        │          │       │        │         │
        │       Prometheus Grafana  Apps      │
        │                          │          │
        └──────────────────────────┼──────────┘
                                   │
                ┌──────────────────┼─────────────────┐
                │                  │                 │
            JupyterHub          Hermes            Astro
                │                  │                 │
                └──────────────────┼─────────────────┘
                                   │
                              PostgreSQL
```

## Network planes

```text
Management:   10.50.0.0/24
Kubernetes:   10.51.0.0/24
WireGuard:    10.60.0.0/24
```

Important reference endpoints include:

```text
edge                10.50.0.10
api-lb-01            10.51.0.100
k8s-cp-01            10.51.0.11
k8s-cp-02            10.51.0.12
k8s-cp-03            10.51.0.13
k8s-worker-01        10.51.0.21
k8s-worker-02        10.51.0.22
k8s-worker-03        10.51.0.23
WireGuard client      10.60.0.2
```

The edge host is the private security boundary: WireGuard, DNS, nftables, Wazuh Manager and network IDS/IPS live there. The Kubernetes API HAProxy endpoint is separate from the later application-ingress path through HAProxy → Traefik.

## Separation of concerns

The repository intentionally keeps these paths distinct:

### Infrastructure lifecycle

```text
Terraform → OpenStack resources
```

### Host lifecycle

```text
Ansible → Linux hosts, packages, services, firewalls and infrastructure daemons
```

### Kubernetes lifecycle

```text
kubeadm → cluster formation
Cilium  → networking / policy
Argo CD → long-lived applications
```

### HPC lifecycle

```text
Slurm → HPC scheduling and execution
```

### Security lifecycle

```text
Wazuh   → security events / host security
Siccata → IDS/IPS telemetry
```

### Observability lifecycle

```text
Prometheus → metrics
Grafana    → dashboards / operational views
```

### Research platform lifecycle

```text
PostgreSQL → identity / application state
JupyterHub → interactive computing
Hermes     → orchestration / coordination
Heretic    → controlled execution / research workflows
Astro      → user-facing portal
```

## Access model

The current administrative path is WireGuard-first:

```text
Workstation
   ↓
WireGuard
   ↓
edge
   ├── management network
   └── Kubernetes network
```

During platform bring-up, temporary `kubectl port-forward` and SSH tunnels were used for selected graphical interfaces. These are **temporary bootstrap mechanisms**, not the target architecture.

The target application access path is:

```text
Cloudflare DNS / ACME
        ↓
Pi-hole for private DNS where applicable
        ↓
HAProxy
        ↓
Traefik
        ↓
Kubernetes Services
```

The next networking milestone is to complete and validate this path, then remove the remaining GUI port-forwards and SSH tunnels from normal operations.

## Observability

Prometheus and Grafana are now treated as platform infrastructure, not as an afterthought.

The current dashboard set covers:

```text
Platform Overview
Kubernetes
Nodes
cAdvisor
Cilium
Cilium Envoy
HAProxy / Ingress
Prometheus
Storage
```

Dashboards are stored in Git as ConfigMaps under `argocd/resources/grafana/dashboards/`. Argo CD deploys those resources and the Grafana dashboard sidecar provisions them into Grafana.

The important operational rule is:

> A dashboard is not considered complete until its PromQL has been validated against the live metric and label schema.

That rule matters because Prometheus job names are discovery-specific: for example, HAProxy is an explicit `haproxy` job, Cilium agents are discovered through `kubernetes-pods`, and Cilium Envoy through `kubernetes-service-endpoints`.

## Security model

Security is layered:

```text
Cloud security groups
        ↓
Host nftables
        ↓
WireGuard / SSH identities
        ↓
Kubernetes / Cilium policy
        ↓
Application authentication and authorization
```

Wazuh and Siccata complement rather than replace this model.

## Roadmap

### Phase A — Foundation and observability

**Completed / operational:**

- OpenStack/Terraform foundation
- Rocky Linux host bootstrap
- WireGuard and edge security baseline
- HAProxy Kubernetes API endpoint
- kubeadm multi-control-plane cluster
- Cilium baseline and connectivity validation
- OpenStack CCM / Cinder CSI
- Argo CD
- Prometheus
- Grafana
- GitOps-managed observability dashboards
- Temporary GUI access paths documented as transitional only

### Phase B — Security and HPC

**Next:**

1. Wazuh Manager completion
2. Wazuh Indexer
3. Wazuh Dashboard
4. Siccata IDS/IPS integration
5. Wazuh/Siccata/Prometheus/Grafana security observability
6. Slurm completion
7. Slurm Grafana dashboard

### Phase C — Private ingress and DNS

After security and Slurm:

1. HAProxy application ingress
2. Traefik
3. Pi-hole private DNS
4. Cloudflare DNS / ACME integration
5. End-to-end private ingress validation
6. Remove normal dependence on port-forwards and SSH tunnels

### Phase D — Research platform

1. PostgreSQL platform/user database
2. JupyterHub
3. Hermes Orchestrator
4. Heretic controlled execution/research workflows
5. Astro portal
6. Telegram / Discord integrations for Hermes through controlled liaison components
7. LLM inference services (llama.cpp / Ollama)
8. research and quantum-computing workloads

### Phase E — Resource accounting and advanced research

Templates and interfaces will be established early, but detailed accounting is deliberately deferred until identity, Slurm and platform orchestration are authoritative.

Planned accounting dimensions include:

```text
CPU / HPC
GPU
QPU
user
project
job
allocation
runtime
resource consumption
```

### Deferred / later

- advanced Cilium Hubble work
- kube-proxy replacement
- ClusterMesh
- deeper Cilium policy design
- HPC accounting
- GPU accounting
- QPU accounting
- user-facing resource dashboards
- HA and disaster-recovery hardening beyond the current baseline

## Hermes / Heretic direction

Hermes is deliberately split across trust boundaries:

```text
                      Hermes federation root
                              │
                    hermes-orchestrator host
                              │
                read/report by default
                              │
                    ┌─────────┴─────────┐
                    │                   │
             Research Hermes      controlled tools
                (Kubernetes)          / APIs
```

The design goal is not a general-purpose autonomous administrator. Hermes capabilities should be explicit, least-privileged, auditable and human-approvable where changes can affect infrastructure.

Planned integrations include:

- Prometheus/Grafana telemetry
- Wazuh/Siccata security telemetry
- Kubernetes APIs
- Slurm APIs/CLI through controlled capabilities
- PostgreSQL-backed identity and metadata
- JupyterHub lifecycle information
- Telegram and Discord as messaging interfaces
- separate liaison components for external chat systems
- isolated per-user/per-profile execution context
- Heretic for controlled research/execution workflows

External messaging is an interface to the orchestrator, **not a direct path to privileged infrastructure actions**.

## Documentation map

```text
README.md
   ↓
project identity, architecture, current state, roadmap

 docs/README.md
   ↓
documentation map and ownership model

 docs/QUICK_GUIDE.md
   ↓
command-first operational path

 docs/INSTALLATION.md
   ↓
complete deployment, design decisions, validation and troubleshooting

 docs/tutorials/README.md
   ↓
teaching pack and reading order

 docs/tutorials/COURSE_OUTLINE.md
   ↓
lectures, workshops, tutorial checklists and capstone
```

Read the root README to understand the platform, not to learn every command. Detailed procedures belong in `INSTALLATION.md` and the tutorials.

## Teaching philosophy

This repository is intended to be a practical infrastructure classroom. The course teaches:

1. architecture and separation of concerns
2. cloud networking and edge security
3. Terraform and Ansible
4. Kubernetes and Cilium
5. storage and GitOps
6. observability and operations
7. security telemetry and HPC scheduling
8. private ingress and application delivery
9. Hermes/Heretic orchestration and security boundaries
10. AI/ML and quantum-computing platform design

Real failures are preserved as teaching material where useful.

## Start here

- New deployment: `docs/INSTALLATION.md`
- Experienced operator: `docs/QUICK_GUIDE.md`
- Course / teaching: `docs/tutorials/README.md`
- Module map: `docs/tutorials/COURSE_OUTLINE.md`
