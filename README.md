# infra-hpc-qc-k8s

Infrastructure-as-Code and GitOps platform for hybrid HPC, Kubernetes, AI/ML and quantum-computing research.

The project is designed to be reproducible, teachable and portable: a student, researcher, collaborator or stranger should be able to understand how the platform is built, reproduce it, modify it and eventually recover it from scratch.

## What this project is

`infra-hpc-qc-k8s` builds the infrastructure and platform underneath a research environment combining:

- OpenStack infrastructure
- Rocky Linux
- Kubernetes
- Cilium
- OpenStack Cinder CSI
- Argo CD
- Prometheus and Grafana
- Wazuh and Suricata security telemetry
- Slurm HPC scheduling
- Hermes intelligent orchestration
- Heretic controlled execution/research workflows
- JupyterHub research environments
- local and cluster LLM inference with llama.cpp and Ollama
- PostgreSQL-backed platform identity and application data
- Astro-based user/research portal
- hybrid classical/HPC/GPU/quantum workloads

The project deliberately separates infrastructure provisioning, host configuration, Kubernetes application lifecycle, HPC scheduling and research workloads.

## Architecture

```text
                                      GitHub
                                         │
                         ┌───────────────┴───────────────┐
                         │                               │
                    Terraform                        Ansible
                         │                               │
                         ▼                               ▼
                  OpenStack resources             Rocky Linux + base
                         │                        platform services
                         └───────────────┬───────────────┘
                                         │
                                         ▼
                                  Kubernetes cluster
                                         │
                  ┌──────────────────────┼──────────────────────┐
                  │                      │                      │
                Cilium                 Argo CD                Slurm
                  │                      │                      │
                  │           ┌──────────┼──────────┐           │
                  │           │          │          │           │
                  │        Helm       resources   secrets      HPC
                  │                    │          │             │
                  │                    │     Sealed Secrets     │
                  │                    │                         │
                  ▼                    ▼                         ▼
               networking        applications             HPC execution

                                         │
                              ┌──────────┼───────────┐
                              │          │           │
                           Storage   Observability Security
                              │          │           │
                           Cinder   Prometheus/Grafana Wazuh/Suricata
                              │
                              ▼
                        Research services
                              │
          ┌───────────────────┼──────────────────────┐
          │                   │                      │
       JupyterHub         Hermes/Heretic      LLM inference
          │                   │              llama.cpp/Ollama
          │                   │
          └───────────────────┼──────────────────────┘
                              │
                              ▼
                         PostgreSQL
                              │
                              ▼
                         Astro portal
```

## Ownership model

Each system owns one clear layer.

### Terraform

Terraform owns OpenStack infrastructure:

- networks
- subnets
- routers
- ports
- security groups
- virtual machines
- API load-balancer infrastructure

Terraform answers:

> What infrastructure exists?

### Ansible

Ansible owns host and platform bootstrap:

- Rocky Linux configuration
- users and SSH
- packages
- host firewalling
- containerd
- Kubernetes prerequisites
- kubeadm bootstrap
- Cilium prerequisites/bootstrap where required
- Slurm
- Hermes management/orchestrator hosts
- Argo CD bootstrap
- Sealed Secrets bootstrap

Ansible does **not** become the long-lived Kubernetes application installer.

### kubeadm

`kubeadm` forms the Kubernetes cluster.

### Cilium

Cilium owns Kubernetes networking and network policy.

### Cinder CSI

Cinder CSI provides the Kubernetes-to-OpenStack block-storage integration.

### Argo CD

Argo CD owns the lifecycle of long-lived Kubernetes applications.

### Prometheus/Grafana

Observability owns metrics, dashboards and alerting.

### Slurm

Slurm remains outside Kubernetes and owns HPC scheduling and execution.

### Hermes

Hermes provides intelligent orchestration and coordination across the platform.

### Heretic

Heretic provides controlled execution/research capabilities complementary to Hermes.

### JupyterHub

JupyterHub provides the researcher-facing interactive computing environment.

### Astro

Astro provides the public/user-facing portal.

### PostgreSQL

PostgreSQL stores platform application data and identity/application metadata. It is not the authority for external provider credentials such as IBM Quantum credentials.

---

# Current platform state

## Kubernetes

The current reference cluster is:

- 3 control planes
- 3 workers
- Kubernetes 1.36.4
- containerd 2.3.4
- Cilium 1.20.1

The Kubernetes API is exposed through an HAProxy VIP:

```text
10.51.0.100:6443
```

Cilium baseline connectivity testing has already passed.

## Network layout

```text
Management: 10.50.0.0/24
Kubernetes: 10.51.0.0/24
VPN:        10.60.0.0/24
```

Important systems include:

```text
edge                  10.50.0.10
hermes-orchestrator   10.50.0.11
slurm-controller      10.50.0.12
login1                10.50.0.20
login2                10.50.0.21
slurm-cpu-01          10.50.0.30
slurm-cpu-02          10.50.0.31
```

Kubernetes nodes live on `10.51.0.0/24`.

The edge host provides the private access/security boundary, including WireGuard, DNS filtering, host firewalling and security telemetry components.

## Storage

OpenStack Cinder CSI is now fully operational and has passed an end-to-end persistence test.

Current Kubernetes StorageClasses:

```text
cinder-ssd       default
cinder-hdd
cinder-default
```

Validated path:

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
 ↓
write data
 ↓
Pod deleted
 ↓
new Pod
 ↓
data survives
```

The test data survived Pod recreation, proving that this is functional persistent storage rather than merely an installed CSI driver.

---

# Argo CD GitOps model

The final application structure is intentionally simple.

```text
argocd/
├── applications/
│   ├── cinder-csi.yml
│   ├── prometheus.yml
│   ├── grafana.yml
│   ├── wazuh.yml
│   ├── jupyterhub.yml
│   └── hermes.yml
│
├── bootstrap/
│   └── root-application.yaml
│
└── resources/
    ├── cinder-csi/
    ├── prometheus/
    ├── grafana/
    ├── wazuh/
    ├── jupyterhub/
    └── hermes/

secrets/
├── cinder/
├── prometheus/
├── grafana/
├── wazuh/
├── jupyterhub/
└── hermes/
```

The root Application points directly to the flat `argocd/applications` directory.

There is deliberately no Kustomize layer and no ApplicationSet for the application registry.

One file represents one child Application.

---

# Canonical application prescription

Cinder CSI established the reference pattern for Argo-managed applications.

Each application should normally consist of three concerns:

```text
Application definition
        +
Repository-owned Kubernetes resources
        +
Encrypted secrets
```

Conceptually:

```text
argocd/applications/<app>.yml
        │
        ├── upstream Helm chart or other vendor source
        ├── argocd/resources/<app>
        └── secrets/<app>
```

This pattern keeps vendor software, local policy/configuration and secrets separate.

## Example: Cinder

```text
cinder-csi Application
│
├── Cinder CSI Helm chart
├── argocd/resources/cinder-csi
└── secrets/cinder
```

The Cinder application uses automated sync with pruning and self-healing.

The same pattern is the starting prescription for:

```text
Prometheus
Grafana
Wazuh
JupyterHub
Hermes
Heretic
llama.cpp
Ollama
Astro portal
PostgreSQL
```

Not every application will have all three sources, but the boundary remains the same.

---

# Secrets

The project originally explored SOPS + age and then KSOPS.

That approach was ultimately rejected for this platform because it unnecessarily complicated Argo CD repo-server configuration and Ansible bootstrap.

The chosen solution is Bitnami Sealed Secrets.

The workflow is:

```text
plaintext Secret on workstation
        │
        ▼
     kubeseal
        │
        ▼
  SealedSecret
        │
        ▼
      GitHub
        │
        ▼
     Argo CD
        │
        ▼
Sealed Secrets controller
        │
        ▼
 Kubernetes Secret
```

The private sealing key remains with the controller and is backed up securely outside Git.

The workstation uses the controller's public certificate for offline sealing.

`kubeseal` does not need to be installed on Kubernetes control-plane nodes.

---

# Cinder CSI troubleshooting lessons

Tutorial 4c documents the complete debugging journey because the failures are valuable training material.

Several tiny configuration errors produced a system that initially looked fundamentally broken:

```text
missing Application destination
wrong Git resources path
wrong Secret key
clouds.conf vs cloud.conf
clouds.yaml vs cloud.conf
swapped application credential ID and secret
wrong Helm filename
```

The final diagnostic chain was:

```text
Git                         ✅
Argo CD                     ✅
Sealed Secrets              ✅
Kubernetes Secret           ✅
Helm Deployment             ✅
OpenStack authentication    ✅
Cinder CSI                  ✅
Dynamic provisioning        ✅
PVC/PV                      ✅
Volume attach/mount         ✅
Persistence                 ✅
```

The most important lesson is:

> Inspect the actual rendered runtime configuration before adding more frameworks.

In particular, always verify agreement between:

```text
SealedSecret key
Kubernetes Secret key
Helm secret.filename
mounted filename
container --cloud-config argument
```

For Cinder the final invariant is:

```text
cloud.conf
    ↓
/etc/config/cloud.conf
    ↓
--cloud-config=/etc/config/cloud.conf
```

Argo `Synced` and `Healthy` also mean different things:

```text
Synced  = desired Git state has been applied
Healthy = the resulting Kubernetes resources are healthy
```

Both conditions matter.

---

# Roadmap

The project now moves from foundational infrastructure into platform services.

## Phase 0 — Foundation

Status: largely complete.

```text
Terraform
Rocky Linux
Networking
Security groups
VMs
HAProxy
kubeadm
3 control planes
3 workers
Cilium
```

## Phase 1 — GitOps and storage

Status: complete for the current milestone.

```text
Argo CD
Sealed Secrets
Cinder CSI
StorageClasses
PVC/PV validation
persistent-volume recovery test
```

This phase established the canonical Argo Application prescription.

## Phase 2 — Observability

Next critical platform milestone.

Deploy in this order:

```text
Prometheus
    ↓
Grafana
    ↓
Cilium dashboards
    ↓
Kubernetes dashboards
    ↓
OpenStack/VM metrics
    ↓
Slurm metrics
    ↓
Wazuh/Suricata operational telemetry
```

The purpose is to make the platform observable before adding more complex services.

## Phase 3 — Security operations

```text
Wazuh agents
Wazuh manager/integration
Suricata telemetry
host security visibility
security dashboards and alerting
```

The security stack should feed operational visibility into Grafana without confusing metrics with logs/events.

## Phase 4 — Researcher compute environment

```text
JupyterHub
    ↓
per-user environments
    ↓
Cinder-backed persistence
    ↓
Kubernetes CPU/GPU workloads
    ↓
Slurm HPC workloads
```

JupyterHub becomes the primary interactive research interface.

## Phase 5 — Intelligent orchestration

```text
PostgreSQL
    ↓
platform identity/application metadata
    ↓
Hermes
    ↓
Heretic
    ↓
execution routing
```

Hermes should determine where work should run rather than replacing the underlying schedulers.

Example decision path:

```text
user request
    ↓
Hermes
    ├── CPU
    ├── GPU
    ├── Slurm/HPC
    ├── simulator
    └── QPU
```

Agents should have bounded permissions. Hermes should not become an unrestricted cluster-admin deployment bot.

## Phase 6 — Local and cluster LLM inference

Treat llama.cpp and Ollama as applications of the same Argo prescription.

```text
llama.cpp
    ↓
low-level/local inference runtime

Ollama
    ↓
managed model runtime/API
```

The desired architecture is to expose inference as a service while retaining explicit GPU/resource boundaries.

Model serving can later feed Hermes and research applications.

## Phase 7 — Platform identity and data

Deploy PostgreSQL before building the full user portal.

PostgreSQL provides the application's durable data layer for things such as:

```text
platform users
roles
projects
research groups
provider identity mappings
execution records
job metadata
portal configuration
```

External-provider credentials remain with the provider's identity system rather than becoming arbitrary plaintext database records.

For example:

```text
platform user
    ↓
external-provider identity/reference
    ↓
provider-controlled credentials
```

## Phase 8 — Astro user portal

The portal becomes the public and researcher-facing entry point.

```text
Astro
  ↓
login
  ↓
platform identity
  ↓
user/projects
  ↓
JupyterHub
  ↓
Hermes
  ↓
HPC / GPU / QPU services
```

The portal should eventually provide:

- public landing pages
- scientific/research areas
- user authentication
- project/workspace selection
- job/execution status
- research resources
- service entry points
- documentation

Astro is a user interface, not the infrastructure control plane.

## Phase 9 — Scientific applications

Once the platform is stable, connect the separate scientific/research repositories.

Planned application domains include:

```text
quantum
QRMI
simulators
quantum finance
high-energy physics
variational networks
hybrid CPU/GPU/QPU workflows
```

Scientific code should remain separate from infrastructure code where practical.

---

# Target service order

The near-term deployment sequence is:

```text
Cinder CSI                  ✅
    ↓
Prometheus                  next
    ↓
Grafana
    ↓
Wazuh agents/security
    ↓
PostgreSQL
    ↓
JupyterHub
    ↓
Hermes
    ↓
Heretic
    ↓
llama.cpp
    ↓
Ollama
    ↓
Astro user portal
    ↓
research/scientific services
```

Some services have prerequisites or may be reordered during implementation. The important point is that every Kubernetes service should follow the same GitOps contract established by Cinder.

---

# Slurm boundary

Slurm is intentionally not moved into the Argo application stack.

Its ownership remains:

```text
Ansible
    ↓
Slurm controller
login nodes
compute nodes
partitions
accounts
Munge
HPC software environment
```

Kubernetes applications may submit work to Slurm, but Slurm remains the scheduler for HPC resources.

This creates a clean hybrid model:

```text
Kubernetes
    ├── services
    ├── APIs
    ├── interactive research
    └── cloud-native workloads

Slurm
    ├── MPI
    ├── CPU HPC
    ├── GPU HPC
    └── batch research
```

---

# Testing philosophy

Infrastructure tests and scientific tests have different jobs.

## Infrastructure

```text
tests/
├── terraform/
│   ├── policy/
│   ├── security/
│   └── infrastructure/
└── ansible/
    ├── convergence/
    └── functional/
```

### Policy

Is the infrastructure configuration permitted?

### Security

Is the exposure safe?

### Infrastructure

Did the declared resources materialise?

### Convergence

Does repeated Ansible execution converge cleanly?

### Functional

Does the resulting service actually work?

## Scientific/research tests

```text
quantum/
├── tests/
│   ├── unit/
│   ├── numerical/
│   ├── integration/
│   ├── reference/
│   └── e2e/
└── benchmarks/
    ├── circuits/
    ├── gpu/
    ├── mpi/
    ├── slurm/
    ├── finance/
    └── hep/
```

Tests answer:

> Is it correct?

Benchmarks answer:

> How well does it perform?

Scarce H100/H200 resources should not be required for every pull request.

---

# Security model

The platform uses multiple independent layers:

```text
OpenStack security groups
        +
host nftables
        +
WireGuard private access
        +
Cilium network policy
        +
Wazuh
        +
Suricata
        +
application RBAC
        +
Sealed Secrets
```

The private network is the preferred administrative path.

The edge node is the controlled boundary into the platform.

SSH public exposure should be removed once the VPN/recovery path is fully validated.

---

# Portability

Applications should depend on stable platform contracts rather than provider-specific implementation details.

For storage:

```text
Kubernetes StorageClass
        ↓
provider-specific CSI
```

For compute:

```text
Kubernetes workload
        ↓
Kubernetes scheduler
or
Slurm scheduler
```

For inference:

```text
application API
        ↓
llama.cpp / Ollama / other runtime
```

For quantum execution:

```text
platform identity
        ↓
execution service
        ↓
provider-specific QPU integration
```

This lets the research environment evolve without rewriting every application when the underlying infrastructure changes.

---

# Bootstrap versus day-2 operations

Bootstrap is intentionally small:

```text
Terraform
    ↓
OpenStack
    ↓
Ansible
    ↓
Kubernetes + Argo CD + Sealed Secrets
```

Once Argo CD is established:

```text
GitHub
    ↓
Argo CD
    ↓
Kubernetes applications
```

The control plane does not need a clone of this repository for ordinary GitOps operation.

The workstation owns the repository.

Ansible copies only the small bootstrap artifacts it actually needs.

---

# Failure lessons

This repository is intentionally a record of engineering decisions, including things that did not work.

## SOPS + age / KSOPS

Attractive in theory, but repo-server plugin configuration and Ansible bootstrap complexity were disproportionate to the requirement.

Final choice: Sealed Secrets.

## Kustomize

Useful elsewhere, but unnecessary for the simple Application registry.

Final choice: flat Argo Directory source.

## ApplicationSet

Powerful, but unnecessary for a small explicit set of applications.

Final choice: one Application manifest per service.

## Giant Ansible Kubernetes installer

Rejected because it blurs infrastructure bootstrap and application lifecycle.

Final choice: Ansible bootstraps; Argo CD reconciles applications.

## Cinder debugging

The Cinder ordeal demonstrated that tiny configuration mismatches can create cascading failures.

The lesson is not to add another framework.

The lesson is to inspect the actual dependency chain.

---

# Tutorials

The tutorials document the platform as a sequence rather than merely a collection of commands.

Key milestones include:

```text
Tutorial 1 — OpenStack infrastructure
Tutorial 2 — Rocky Linux + Kubernetes bootstrap
Tutorial 3 — Argo CD + Sealed Secrets
Tutorial 4c — Cinder CSI and GitOps troubleshooting
```

Tutorial 4c is the current reference example for subsequent Kubernetes applications.

---

# What comes next

The platform has crossed an important boundary.

We are no longer proving that Kubernetes can boot.

We have now proven that Kubernetes can:

```text
consume OpenStack infrastructure
        ↓
manage persistent storage
        ↓
receive encrypted credentials
        ↓
reconcile declaratively from Git
```

The next objective is to make the cluster **observable before making it more complicated**.

Therefore the immediate next milestone is:

```text
Prometheus
    ↓
Grafana
    ↓
platform dashboards
    ↓
Cilium validation with observability
```

After that the platform can grow into the full research environment.

---

# Philosophy

This project follows a simple principle:

> Build a platform that is understandable enough to teach, reproducible enough to rebuild, and useful enough to run real research.

Prefer explicit ownership over clever automation.

Prefer stable interfaces over provider-specific coupling.

Prefer boring infrastructure over unnecessary frameworks.

And when something breaks:

> inspect what is actually running before redesigning what you think should be running.

