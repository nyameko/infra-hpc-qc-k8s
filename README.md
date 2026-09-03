# infra-hpc-qc-k8s

## Hybrid Quantum-Centric Supercomputing Infrastructure

Infrastructure as Code for a reproducible, provider-adaptable research-computing platform combining cloud infrastructure, Kubernetes, classical HPC, AI/ML, agentic systems, and future quantum-computing workflows.

This repository is both a working infrastructure project and a teaching environment. The intended audience is not only the original operator: students, researchers, collaborators, engineers, contributors, and people encountering the repository for the first time should be able to understand it, reproduce it, modify it, break it safely, and recover it.

## Platform in one picture

```text
                              Researchers / Users
                                      │
                         ┌────────────┴────────────┐
                         ▼                         ▼
                    ┌─────────┐              ┌──────────┐
                    │  Astro  │              │JupyterHub│
                    │ public / │              │ research │
                    │ user UX  │              │ gateway  │
                    └────┬────┘              └────┬─────┘
                         │                        │
                         │                 ┌──────┴──────┐
                         │                 │             │
                         │                 ▼             ▼
                         │            Kubernetes       Slurm
                         │              workloads     HPC jobs
                         │                 │             │
                         │                 └──────┬──────┘
                         │                        │
                         │                  research plane
                         │                        │
                         ▼                        ▼
                   Application layer       Compute layer
                              │                  │
                 ┌────────────┴───────┐          │
                 │                    │          │
                 ▼                    ▼          ▼
             Hermes               Heretic      HPC/GPU
          orchestration         controlled      resources
                                  execution
                 │
                 └───────────────────────┐
                                         │
                                         ▼
                               Kubernetes platform
                                         │
                    ┌────────────────────┼─────────────────────┐
                    ▼                    ▼                     ▼
                 Argo CD          Prometheus/Grafana         Cilium
                GitOps lifecycle     observability         networking
                    │
                    ▼
               Cinder CSI
                    │
                    ▼
                  Cinder
                    │
                    ▼
               cloud storage

  ---------------------------------------------------------------------------

  Terraform       → infrastructure
  Ansible         → OS + base infrastructure
  kubeadm         → Kubernetes bootstrap
  Cilium          → networking
  Cinder CSI      → storage integration
  Argo CD         → application lifecycle
  Prometheus/Grafana → observability
  Slurm           → HPC execution
  Hermes          → intelligent orchestration
  Heretic         → controlled execution / research
  JupyterHub      → researcher interface
  Astro           → public / user-facing platform
```

The ordering and ownership boundaries are intentional. The project uses each tool for the layer it is good at rather than allowing a single tool to become responsible for the entire stack.

## Architecture and ownership

```text
Terraform
    ↓
OpenStack / cloud infrastructure

Ansible
    ↓
Rocky Linux + host configuration + base services

kubeadm
    ↓
Kubernetes cluster bootstrap

Cilium
    ↓
Kubernetes networking

Cinder CSI
    ↓
Kubernetes persistent storage integration

Argo CD
    ↓
Kubernetes application lifecycle / GitOps

Prometheus + Grafana
    ↓
observability

Slurm
    ↓
HPC scheduling and execution

Hermes
    ↓
intelligent orchestration

Heretic
    ↓
controlled execution / research actions

JupyterHub
    ↓
researcher interface

Astro
    ↓
public/user-facing applications
```

The boundary around Argo CD is especially important:

```text
Terraform
  owns cloud resources

Ansible
  owns machines and bootstrap

Argo CD
  owns Kubernetes applications

Slurm
  owns HPC scheduling
```

This does not mean Kubernetes is incomplete before Argo CD. It means that once the Kubernetes substrate exists, we use Kubernetes-native GitOps tooling for long-lived application lifecycle rather than continually expanding Ansible into an application controller.

## Current reference environment

The current reference implementation is an OpenStack cloud using Rocky Linux virtual machines.

### Network planes

```text
Management:    10.50.0.0/24
Kubernetes:    10.51.0.0/24
WireGuard/VPN: 10.60.0.0/24
```

Kubernetes API access uses a stable endpoint:

```text
10.51.0.100:6443
        │
      HAProxy
     /  |  \
   CP1  CP2  CP3
```

The API load balancer is replaceable. The stable endpoint is the contract.

### Reference VM topology

| Node | Address | Purpose |
|---|---:|---|
| edge | 10.50.0.10 | WireGuard, Pi-hole, nftables, Suricata IDS, SSH bastion, Wazuh manager/edge security |
| hermes-orchestrator-01 | 10.50.0.11 | management/federation Hermes outside Kubernetes |
| slurm-controller-01 | 10.50.0.12 | Slurm controller, accounting and initial database |
| login1 | 10.50.0.20 | user login and Slurm client |
| login2 | 10.50.0.21 | user login and Slurm client |
| slurm-cpu-01 | 10.50.0.30 | 64-core Slurm compute node |
| slurm-cpu-02 | 10.50.0.31 | 64-core Slurm compute node |
| api-lb-01 | 10.51.0.100 | Kubernetes API HAProxy endpoint |
| k8s-cp-01 | 10.51.0.11 | Kubernetes control plane |
| k8s-cp-02 | 10.51.0.12 | Kubernetes control plane |
| k8s-cp-03 | 10.51.0.13 | Kubernetes control plane |
| k8s-worker-01 | 10.51.0.21 | Kubernetes worker |
| k8s-worker-02 | 10.51.0.22 | Kubernetes worker |
| k8s-worker-03 | 10.51.0.23 | Kubernetes worker |

## Kubernetes status

The reference cluster uses Kubernetes `1.36.4` with Cilium `1.20.1`.

The Cilium baseline has passed the complete connectivity test suite:

```text
82 tests
780 actions
55 tests skipped
1 scenario skipped
0 failed
```

This establishes a known-good network substrate before persistent storage and higher-level applications are layered on top.

## Argo CD: the application lifecycle boundary

Argo CD is bootstrapped by Ansible, but applications are thereafter intended to be managed by Argo CD.

The current bootstrap path is:

```text
Ansible
   │
   │ SSH to k8s-cp-01
   ▼
existing Kubernetes admin kubeconfig + kubectl
   │
   ▼
install Argo CD
   │
   ▼
Argo CD inside Kubernetes
   │
   ▼
Kubernetes API via in-cluster identity
```

Argo CD does **not** need the operator's kubeconfig. For the in-cluster destination it authenticates through its Kubernetes ServiceAccount/RBAC and talks to `https://kubernetes.default.svc`. The standard Argo installation is explicitly designed for an Argo instance managing applications in the same cluster. citeturn523162search1turn523162search3

The current application controller is a StatefulSet. That is an implementation detail of Argo CD's controller/sharding model, not an indication that the controller stores application state on a persistent disk. Argo's current high-availability documentation describes cluster sharding across `argocd-application-controller` StatefulSet replicas. citeturn883343search0turn883343search1

### Why the controller is a StatefulSet

A Deployment treats replicas as interchangeable. Argo's application controller historically uses stable pod identity to associate replicas with controller shards. The predictable names (`...-0`, `...-1`, etc.) participate in that model. Argo's documentation discusses both StatefulSet-based sharding and a later dynamic-distribution approach that can use a Deployment, but the latter is an explicit feature with different behavior and is not our reason to change the default deployment. citeturn883343search0turn883343search3

For this cluster, one healthy controller replica is appropriate initially. We do not need to treat the StatefulSet as a storage requirement or an application data store.

## Cinder CSI: first GitOps-managed platform application

The current OpenStack cloud exposes three public Cinder volume types:

```text
SSD
HDD
__DEFAULT__
```

Kubernetes exposes three StorageClasses:

```text
cinder-ssd       → Cinder SSD
cinder-hdd       → Cinder HDD
cinder-default   → omit type and let Cinder select its configured default
```

`cinder-ssd` is the Kubernetes default in the reference deployment.

The Cinder CSI application is represented in Git under:

```text
argocd/applications/cinder-csi/
```

The Application uses the upstream `openstack-cinder-csi` Helm chart and a Git source for our StorageClasses. The destination is the in-cluster Kubernetes API. citeturn662409view4turn438820view0

The OpenStack credential is intentionally not committed to Git. The CSI driver consumes a Kubernetes Secret containing the `cloud.conf` configuration. The long-term platform direction is to move that secret into a dedicated secret-management workflow rather than placing plaintext credentials in Git.

## Slurm is intentionally outside Kubernetes

Slurm is not another Kubernetes application.

It owns **HPC scheduling, resource allocation, and batch execution** for the dedicated HPC resources.

```text
                Research platform
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
     Kubernetes                   Slurm
     services                    batch/HPC
     APIs                        MPI
     notebooks                   scientific jobs
     portals                     GPU/CPU scheduling
```

The initial Slurm deployment therefore remains an Ansible-managed host deployment:

```text
slurm-controller-01
    ├── slurmctld
    ├── slurmdbd
    └── MariaDB (initial reference deployment)

login1 / login2
    └── user access + Slurm clients

slurm-cpu-01 / slurm-cpu-02
    └── compute
```

Slurm should be deployed **after the Kubernetes/storage/Argo boundary is established, but before Hermes and JupyterHub depend on HPC execution**. It can technically be deployed independently of Argo CD, because it lives outside Kubernetes, and its Ansible playbook remains the correct owner.

This is a deliberate exception to the "Argo manages the remaining deployments" rule: **Argo manages Kubernetes applications; Slurm manages HPC execution outside Kubernetes.**

## Hermes and Heretic

Hermes is intentionally split across trust boundaries.

```text
Management / federation Hermes
        │
        │ observe / orchestrate
        ▼
Infrastructure APIs

Research Hermes
        │
        ▼
Kubernetes research workloads

Heretic
        │
        ▼
controlled execution actions
```

The management Hermes remains outside Kubernetes so that a Kubernetes outage does not automatically eliminate the management/federation control point. Research Hermes will run inside Kubernetes. Heretic is a complementary execution/research component whose permissions should remain explicit and constrained.

The long-term model is not "AI gets root":

```text
telemetry / APIs
       ↓
    Hermes
       ↓
inspect → reason → request → controlled action
       ↓
    Heretic
```

## Observability

Prometheus/Grafana are intended to become the central observability plane across the whole system, not only Kubernetes.

```text
                         Grafana
                            │
                       Prometheus
                            │
       ┌────────────────────┼────────────────────┐
       ▼                    ▼                    ▼
   Kubernetes           OpenStack             Management
   + Cilium             + VM telemetry        + services
       │                    │                    │
       │                    │                 Hermes
       │                    │                 Heretic
       ▼                    ▼
   workloads            Nova/Cinder/etc.
```

This lets us distinguish cloud state (`ACTIVE`) from actual guest/service health and eventually correlate infrastructure telemetry with scheduler, agent, and application behavior.

## Portability is an architectural objective

OpenStack is the current reference provider, not a requirement of the platform architecture.

### Provider-neutral layers

```text
Kubernetes
Cilium
Argo CD
Prometheus/Grafana
Slurm
Hermes
Heretic
JupyterHub
Astro
```

### Provider-specific adapters

```text
OpenStack Terraform provider
Nova
Neutron
Cinder
OpenStack application credentials
OpenStack CCM / CSI
provider-specific network/security primitives
```

A different environment may use:

```text
OpenStack       → another OpenStack / AWS / Azure / GCP / bare metal
Cinder CSI      → EBS / Azure Disk / GCE Persistent Disk / Ceph CSI / local storage
Neutron/SG      → VPC/VNet/firewall/physical network
OpenStack CCM   → cloud-specific integration or none
Terraform       → another provider or a different IaC engine
```

The project should therefore continue isolating provider assumptions instead of leaking them into platform-neutral definitions.

## Repository structure

```text
infra-hpc-qc-k8s/
├── ansible/                 # hosts + bootstrap/base infrastructure
│   ├── inventories/
│   ├── playbooks/
│   └── roles/
│
├── argocd/                  # GitOps applications
│   └── applications/
│
├── kubernetes/              # provider-facing / cluster resource definitions
│   └── cinder-csi/
│
├── terraform/               # cloud infrastructure
│   ├── environments/
│   └── modules/
│
├── docs/                    # project documentation + tutorials
├── scripts/                 # helper/validation scripts
├── Makefile
└── README.md
```

## Documentation

```text
docs/README.md
    ↓
project documentation landing page

QUICK GUIDE
    ↓
fast command path

INSTALLATION
    ↓
full guided deployment

TUTORIALS
    ↓
concepts, experiments, failures, design lessons
```

Directory-specific documentation lives with the code it explains:

```text
ansible/README.md
terraform/README.md
argocd/README.md
kubernetes/README.md
```

## Deployment progression

```text
1. Terraform
      ↓
2. Ansible host/base configuration
      ↓
3. kubeadm Kubernetes bootstrap
      ↓
4. Cilium network validation
      ↓
5. Argo CD bootstrap
      ↓
6. Cinder CSI + StorageClasses through Argo
      ↓
7. Prometheus / Grafana
      ↓
8. Slurm (outside Kubernetes, via Ansible)
      ↓
9. Hermes + Heretic
      ↓
10. JupyterHub
      ↓
11. Astro
      ↓
12. research and quantum-computing applications
```

The stages are capabilities, not a prohibition on parallel work. For example, Slurm can be prepared independently once the underlying VMs exist. The sequence simply makes dependencies and teaching milestones explicit.

## Engineering principles

### Prove every layer

```text
install
  ↓
configure
  ↓
inspect
  ↓
functional test
  ↓
recovery / failure test where appropriate
```

### Preserve failure knowledge

The project keeps lessons from real incidents: OpenStack security-group scope, HAProxy + SELinux, CRI permissions, package/repository differences, NodePort behavior, Cilium node-health requirements, kubeconfig placement, Helm installation, and the distinction between host automation and Kubernetes application lifecycle.

### Keep secrets out of Git

Environment-specific credentials belong in the private environment, a secret manager, or a deliberate secret-encryption workflow—not in public manifests or Terraform configuration committed to the repository.

### Build for the next person

A successful deployment is not enough. The repository should make the system understandable, reproducible, modifiable, and teachable.

## Current milestone

```text
✅ OpenStack infrastructure
✅ Rocky Linux base configuration
✅ Edge/security baseline
✅ Kubernetes HA cluster
✅ Cilium
✅ Cilium connectivity validation
✅ Argo CD bootstrap

→ Cinder CSI via Argo CD
→ Prometheus / Grafana
→ Slurm integration / operational deployment
→ Hermes + Heretic
→ JupyterHub
→ Astro
```

## License and contribution

See the repository license for current terms. Contributions are welcome, especially improvements that make the platform easier to reproduce, adapt to another provider, teach, validate, or operate safely.
