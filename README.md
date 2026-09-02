# infra-hpc-qc-k8s

## Hybrid Quantum-Centric Supercomputing Infrastructure

**Infrastructure as Code for a reproducible hybrid HPC + Kubernetes + AI/ML + quantum-computing platform.**

This repository is both an infrastructure project and a learning environment. It is designed to be useful to its original operator, but also understandable and reproducible by students, collaborators, researchers, engineers, and people encountering the project for the first time.

The goal is not merely to produce a working cluster. The goal is to show, in a practical and reproducible way, **how the layers of a modern research-computing platform fit together, why each layer exists, which tool owns it, how the layers interact, and how the design can be adapted to another environment or cloud.**

---

## The platform in one picture

```text
                              Users / Researchers
                                      │
                                      ▼
                               ┌─────────────┐
                               │    Astro    │
                               │ public/user │
                               │   interface │
                               └──────┬──────┘
                                      │
                         ┌────────────┴────────────┐
                         ▼                         ▼
                  ┌────────────┐            ┌────────────┐
                  │ JupyterHub │            │   Hermes   │
                  │ researcher │            │ intelligent│
                  │ interface  │            │ orchestration
                  └──────┬─────┘            └──────┬─────┘
                         │                          │
                         │                          ├──────────────┐
                         ▼                          ▼              ▼
                    Kubernetes                  Slurm          Heretic
                         │                       HPC jobs       controlled
              ┌──────────┼──────────┐                           execution
              │          │          │
              ▼          ▼          ▼
           Argo CD  Prometheus   Cilium
           GitOps   / Grafana    networking
              │          │          │
              └──────────┼──────────┘
                         ▼
                    Platform layer
                         │
                    ┌────┴─────┐
                    ▼          ▼
               Cinder CSI   Kubernetes
                    │         workloads
                    ▼
              OpenStack Cinder

        ─────────────────────────────────────────────

        Terraform → infrastructure
        Ansible    → OS + base infrastructure
        kubeadm    → Kubernetes bootstrap
        Cilium     → networking
        Cinder CSI → storage
        Argo CD    → application lifecycle
        Prometheus/Grafana → observability
        Slurm      → HPC execution
        Hermes     → intelligent orchestration
        JupyterHub → researcher interface
        Astro      → public/user-facing platform
```

The order matters. Each layer establishes a capability required by the next.

---

## Core design principle

The project deliberately gives each tool a clear area of ownership:

```text
Terraform
    ↓
infrastructure

Ansible
    ↓
OS + base infrastructure

kubeadm
    ↓
Kubernetes bootstrap

Cilium
    ↓
networking

Cinder CSI
    ↓
storage

Argo CD
    ↓
application lifecycle

Prometheus/Grafana
    ↓
observability

Slurm
    ↓
HPC execution

Hermes
    ↓
intelligent orchestration

JupyterHub
    ↓
researcher interface

Astro
    ↓
public/user-facing platform
```

This separation is intentional. Terraform does not become an application deployment tool, Ansible does not become the long-term Kubernetes application controller, Slurm does not become a Kubernetes replacement, and Hermes does not become an uncontrolled administrative superuser.

---

## What this repository is trying to accomplish

The project has several simultaneous goals:

1. **Build a real platform.**
   The infrastructure should be usable, not merely illustrative.

2. **Make the engineering reproducible.**
   A technically competent person should be able to reproduce the environment from the repository plus documented provider credentials and environment-specific inputs.

3. **Teach by construction.**
   The implementation history, validation commands, failure analysis, and tutorials are intended to explain the engineering decisions rather than hide them.

4. **Keep infrastructure portable.**
   OpenStack is the current reference cloud, not a conceptual requirement of the platform. Cloud-specific components should be isolated so the same higher-level platform can be adapted to another cloud or bare-metal environment.

5. **Provide a foundation for research.**
   The eventual system combines classical HPC, Kubernetes-native workloads, AI/ML infrastructure, agentic orchestration, and quantum-computing workflows.

6. **Remain understandable to new contributors.**
   Naming, ownership boundaries, validation steps, and documentation should make the repository approachable to someone who did not design the original environment.

---

## Current reference environment

The current implementation uses an OpenStack cloud and Rocky Linux virtual machines. The Kubernetes cluster consists of three control planes and three workers, fronted by a dedicated HAProxy API endpoint.

### Networks

```text
Management:   10.50.0.0/24
Kubernetes:   10.51.0.0/24
WireGuard:    10.60.0.0/24
```

The network names used in code are intentionally canonical:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr:  10.51.0.0/24
vpn_cidr:  10.60.0.0/24
```

### Virtual-machine topology

| Node | Address | Role |
|---|---|---|
| `edge` | `10.50.0.10` | WireGuard, Pi-hole, nftables, Suricata IDS, SSH bastion, Wazuh manager/edge security |
| `hermes-orchestrator-01` | `10.50.0.11` | isolated personal/federation Hermes orchestrator |
| `slurm-controller-01` | `10.50.0.12` | Slurm controller, accounting daemon, initial database |
| `login1` | `10.50.0.20` | user SSH login, Slurm client |
| `login2` | `10.50.0.21` | user SSH login, Slurm client |
| `slurm-cpu-01` | `10.50.0.30` | 64-core Slurm compute node |
| `slurm-cpu-02` | `10.50.0.31` | 64-core Slurm compute node |
| `api-lb-01` | `10.51.0.100` | HAProxy Kubernetes API endpoint |
| `k8s-cp-01` | `10.51.0.11` | Kubernetes control plane |
| `k8s-cp-02` | `10.51.0.12` | Kubernetes control plane |
| `k8s-cp-03` | `10.51.0.13` | Kubernetes control plane |
| `k8s-worker-01` | `10.51.0.21` | Kubernetes worker |
| `k8s-worker-02` | `10.51.0.22` | Kubernetes worker |
| `k8s-worker-03` | `10.51.0.23` | Kubernetes worker |

Kubernetes clients use the stable API endpoint:

```text
10.51.0.100:6443
        │
      HAProxy
     /  |  \
   CP1  CP2  CP3
```

The API load-balancer implementation is intentionally replaceable. The important contract is the stable Kubernetes control-plane endpoint, not HAProxy itself.

---

## Defense in depth

The platform does not rely on one security control.

```text
Internet
   │
   ▼
OpenStack security groups
   │
   ▼
Host firewall / nftables
   │
   ▼
Service controls
   │
   ├── WireGuard
   ├── SSH identities
   ├── Kubernetes API authorization
   ├── Cilium networking / policy
   └── application authentication and authorization
```

The edge host provides the main private access path and network/security services. Wazuh and Suricata provide host/security telemetry and network intrusion detection. Kubernetes provides another security boundary rather than replacing the lower layers.

The bootstrap `rocky` identity is retained for image/bootstrap/recovery purposes while `nyameko` is the normal administrative identity. Public SSH should only be removed after the private recovery path has been fully verified.

---

## Kubernetes architecture

The current Kubernetes layer is intentionally conventional and explicit:

```text
OpenStack VMs
      │
      ▼
containerd
      │
      ▼
kubeadm
      │
      ├── control plane × 3
      └── workers × 3
              │
              ▼
           Cilium
              │
      ┌───────┼────────┐
      ▼       ▼        ▼
   Services  Pods   Network policy
```

The Kubernetes API is fronted by HAProxy. Cilium is the cluster CNI. The current baseline intentionally leaves advanced Cilium capabilities such as kube-proxy replacement, Hubble Relay, and ClusterMesh as later, deliberate exercises rather than prerequisites for the first successful cluster.

The cluster currently uses Kubernetes `1.36.4` and Cilium `1.20.1`.

### Validation milestone

The current Cilium baseline has passed the complete connectivity test suite:

```text
82 tests
780 actions
55 tests skipped
1 scenario skipped
0 failed
```

That milestone is important because it establishes a working network substrate before persistent storage and application deployment are added.

---

## Storage architecture

Kubernetes persistent storage is provided by OpenStack Cinder through the Cinder CSI driver.

The current cloud exposes three public volume types:

```text
SSD
HDD
__DEFAULT__
```

The Kubernetes layer will expose these as three StorageClasses:

```text
cinder-ssd
cinder-hdd
cinder-default
```

`cinder-ssd` is the Kubernetes default class in the reference deployment. `cinder-hdd` is explicitly selected for capacity-oriented workloads. `cinder-default` exists primarily to demonstrate the distinction between a Kubernetes StorageClass and the underlying cloud's default-volume-type behavior.

The exact Cinder configuration is cloud-specific and should not be hard-coded into reusable platform logic. A different cloud or bare-metal environment may require a different CSI driver, a different StorageClass implementation, or a completely different storage system.

---

## GitOps and application lifecycle

After base Kubernetes infrastructure and storage are established, **Argo CD becomes the application deployment boundary**.

```text
Git
 │
 ▼
Argo CD
 │
 ├── platform services
 ├── observability
 ├── research services
 ├── Hermes / Heretic
 ├── JupyterHub
 └── Astro
```

The intended progression is:

```text
Terraform
  → infrastructure

Ansible
  → OS + bootstrap/platform prerequisites

kubeadm / Cilium / CSI
  → Kubernetes substrate

Argo CD
  → persistent application lifecycle
```

This prevents the repository from accumulating an ever-growing collection of one-off imperative application playbooks.

---

## Observability architecture

Prometheus and Grafana are intended to become the central observability plane for more than Kubernetes alone.

```text
                         ┌───────────────┐
                         │    Grafana    │
                         └───────▲───────┘
                                 │
                         ┌───────┴───────┐
                         │  Prometheus   │
                         └───────▲───────┘
                                 │
            ┌────────────────────┼────────────────────┐
            │                    │                    │
            ▼                    ▼                    ▼
       Kubernetes            OpenStack            Management
       + Cilium              + VMs                + services
            │                    │                    │
            │                    │                    ├── Hermes
            │                    │                    └── Heretic
            ▼                    ▼
       workloads             Nova/Cinder
                              Neutron/etc.
```

The intent is to monitor both **infrastructure state** and **application behavior**. A Nova VM being `ACTIVE` is not equivalent to the operating system or service inside that VM being healthy, so cloud-level telemetry and in-guest telemetry complement one another.

As Hermes and Heretic mature, they should expose application-level metrics rather than relying only on generic Linux process metrics.

---

## HPC architecture

Slurm remains an independent HPC scheduler and execution plane.

```text
Users / JupyterHub / Hermes
           │
           ▼
        Slurm
           │
     ┌─────┴─────┐
     ▼           ▼
   CPU pool    future GPU/HPC pools
```

The initial deployment deliberately keeps the Slurm controller separate from the edge host and from login nodes.

The first reference layout is:

```text
slurm-controller-01
    ├── slurmctld
    ├── slurmdbd
    └── MariaDB (initial deployment)

login1 / login2
    └── user access + Slurm client tools

slurm-cpu-01 / slurm-cpu-02
    └── 64-core compute nodes
```

The separation between Kubernetes and Slurm is intentional. Kubernetes handles platform orchestration and services; Slurm handles batch HPC scheduling and resource allocation.

---

## Hermes and Heretic

The platform includes two related but distinct AI/agent concepts.

### Hermes

The management/federation Hermes runs outside Kubernetes as an independent control/orchestration point. A later research Hermes will run inside Kubernetes.

```text
                         Hermes federation
                                │
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
       management Hermes              research Hermes
         outside K8s                     inside K8s
                 │                             │
                 └──────────────┬──────────────┘
                                ▼
                       controlled orchestration
```

The external Hermes is deliberately not given unrestricted administrative authority. A Kubernetes outage should not automatically destroy the external orchestration/control root, and an agent should not gain broad write access merely because it can observe a system.

### Heretic

Heretic is intended as a complementary execution/research component. Its permissions and capabilities should remain explicit and bounded, particularly where it can trigger jobs, access credentials, or interact with infrastructure.

The long-term model is therefore not "AI gets root". It is:

```text
Telemetry / APIs
      │
      ▼
   Hermes
      │
      ├── inspect
      ├── reason
      ├── request action
      └── invoke controlled execution
                     │
                     ▼
                  Heretic
```

This keeps orchestration, execution, and authorization as separable concepts.

---

## From HPC to research platform

The eventual user experience is intended to bridge interactive computing, batch HPC, AI/ML workloads, and quantum workflows.

```text
                         Researcher
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
               JupyterHub             Astro
                    │                   │
              ┌─────┴─────┐             │
              ▼           ▼             │
        Kubernetes      Slurm            │
              │           │             │
              └─────┬─────┘             │
                    ▼                   │
              research workloads       │
                    │                   │
             ┌──────┼───────┐          │
             ▼      ▼       ▼          │
            AI/ML   HPC   quantum      │
                       workflows       │
                                      │
                                      ▼
                              public/user interface
```

The infrastructure should make it possible to experiment with classical and quantum workloads without forcing every application into the same execution model.

---

## Portability and adaptation

The current reference implementation is OpenStack-based, but the project is deliberately intended to generalize.

### What should remain cloud-agnostic

The following concepts should ideally survive a change of infrastructure provider:

```text
Kubernetes
Cilium
Argo CD
Prometheus / Grafana
Slurm
Hermes
Heretic
JupyterHub
Astro
```

### What is currently cloud-specific

The following parts must be treated as provider adapters or deployment-specific modules:

```text
OpenStack Terraform provider
Nova instances
Neutron networks / ports / security groups
Cinder
OpenStack application credentials
OpenStack cloud.conf
OpenStack CCM / CSI configuration
OpenStack-specific metadata / topology
```

For another cloud, these should be replaced rather than copied blindly.

Examples:

```text
OpenStack          → AWS / Azure / GCP / another OpenStack / bare metal
Cinder CSI         → EBS / EFS / Azure Disk / GCE PD / Ceph CSI / local storage
OpenStack network  → provider VPC/VNet / physical network
OpenStack SG       → provider firewall / network policy
OpenStack CCM      → provider integration or none
```

The reusable unit is therefore **the platform architecture**, not a promise that every provider has identical primitives.

### Provider abstraction is an ongoing engineering task

The repository should continue moving toward a structure where:

```text
cloud/
  openstack/
  <future-provider>/

platform/
  kubernetes/
  cilium/
  storage/
  observability/
  slurm/
  agents/
  applications/
```

The exact directory structure may evolve, but cloud-specific code should remain visibly separated from provider-neutral platform definitions.

The same principle applies to bare metal: replacing Nova VMs with physical nodes should not require redesigning the Kubernetes, Slurm, monitoring, GitOps, or application layers.

---

## Repository structure

```text
infra-hpc-qc-k8s/
├── ansible/
│   ├── inventories/
│   ├── playbooks/
│   ├── roles/
│   └── ...
│
├── docs/
│   ├── README.md
│   ├── INSTALLATION.md
│   ├── QUICK_GUIDE.md
│   └── tutorials/
│
├── scripts/
│
├── terraform/
│   ├── modules/
│   └── environments/
│
├── .gitignore
├── FILELIST.txt
├── Makefile
└── README.md
```

The repository is intentionally layered:

```text
terraform/
    cloud infrastructure
        ↓
ansible/
    operating system + bootstrap/base services
        ↓
kubernetes/
    cluster substrate
        ↓
Argo CD
    application lifecycle
```

---

## Documentation

The documentation is intentionally split by purpose.

| Document | Use it when you want to… |
|---|---|
| [`docs/README.md`](docs/README.md) | understand the architecture, repository and deployment strategy |
| [`docs/QUICK_GUIDE.md`](docs/QUICK_GUIDE.md) | deploy quickly with minimal prose |
| [`docs/INSTALLATION.md`](docs/INSTALLATION.md) | perform the deployment carefully and understand each engineering decision |
| [`docs/tutorials/`](docs/tutorials/) | study the concepts, failures, experiments and design decisions in depth |

The normal path is:

```text
README
  ↓
QUICK GUIDE          or          INSTALLATION
  ↓                              ↓
working platform        detailed understanding
             \              /
              ▼            ▼
               TUTORIALS
```

The tutorials are not intended to replace the installation guide. They explain what the deployment teaches.

---

## Current status

### Infrastructure

- ✅ OpenStack network and VM foundation
- ✅ Rocky Linux base configuration
- ✅ Edge services and security baseline
- ✅ WireGuard
- ✅ Pi-hole
- ✅ nftables
- ✅ Suricata IDS
- ✅ Wazuh manager/agent integration
- ✅ Kubernetes API load balancer
- ✅ containerd / CRI

### Kubernetes

- ✅ Kubernetes `1.36.4` prerequisites
- ✅ kubeadm cluster initialization
- ✅ 3 control planes
- ✅ 3 workers
- ✅ HA API endpoint
- ✅ Cilium `1.20.1`
- ✅ Full Cilium connectivity validation

### Current milestone

```text
✅ Infrastructure
✅ Kubernetes
✅ Cilium

→ Cinder CSI
→ Argo CD
→ Prometheus / Grafana
→ Slurm
→ Hermes + Heretic
→ JupyterHub
→ Astro
```

The next immediate implementation step is Cinder CSI, including the three storage classes and deterministic persistence/expansion validation. After that, Argo CD becomes the primary deployment mechanism for the remaining Kubernetes applications.

---

## Reproducibility

This project is intended to be reproducible, but reproducibility requires separating **code** from **environment-specific state and secrets**.

The repository should contain:

- reusable Terraform modules
- reusable Ansible roles
- public defaults and templates
- deployment manifests
- validation procedures
- documentation

The environment should provide separately:

- OpenStack authentication
- private inventory values
- SSH private keys
- WireGuard private keys
- application credentials
- Kubernetes/Helm secrets
- any institution-specific endpoints or identifiers

No private credential should be committed to Git.

A new operator should be able to clone the repository and reconstruct the environment by providing the required provider-specific inputs rather than receiving a copy of the original machine's secret material.

---

## Engineering philosophy

A few principles guide the repository:

### Make the working path boring

The first implementation should prefer stable, understandable components over unnecessary complexity.

### Prove every layer

A service being installed is not the same as a service working. Wherever practical, the project uses explicit validation:

```text
install
  ↓
configure
  ↓
inspect
  ↓
functional test
  ↓
failure test / recovery test where appropriate
```

### Preserve failure knowledge

Troubleshooting is part of the educational value. Problems such as incorrect OpenStack security-group scope, SELinux service restrictions, missing CRI privileges, package/repository differences, and Kubernetes NodePort requirements should remain understandable from the repository history and tutorials rather than being erased into a sequence of unexplained final-state manifests.

### Keep boundaries explicit

Infrastructure ownership should remain understandable:

```text
Terraform → cloud
Ansible   → hosts
kubeadm   → Kubernetes bootstrap
Cilium    → cluster networking
CSI       → cluster storage integration
Argo CD   → applications
Prometheus→ telemetry
Slurm     → HPC scheduling
Hermes    → orchestration
Heretic   → controlled execution/research
```

### Build for the next person

A system is more valuable when another person can understand it, reproduce it, modify it, break it safely, and recover it.

---

## License and contribution

See the repository license and contribution guidance for the current project terms.

Contributions, experiments, improvements, provider adapters, documentation fixes, and reproducibility reports are valuable—particularly where they make the platform easier to understand and reproduce in a different environment.
