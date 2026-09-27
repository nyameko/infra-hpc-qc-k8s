# infra-hpc-qc-k8s

## Hybrid Quantum-Centric Supercomputing Infrastructure

**Infrastructure as Code for a reproducible hybrid HPC + Kubernetes + AI/ML + quantum-computing platform.**

This repository is both an infrastructure project and a learning environment. It is designed to be useful to its original operator, but also understandable and reproducible by students, collaborators, researchers, engineers, and people encountering the project for the first time.

The goal is not merely to produce a working cluster. The goal is to show, in a practical and reproducible way, **how the layers of a modern research-computing platform fit together, why each layer exists, which tool owns it, how the layers interact, and how the design can be adapted to another environment or cloud.**

---

## Public topology policy

This repository is intentionally public, but the live network map is not part of the public API. Documentation uses semantic placeholders; deployable environment values live in protected Terraform variables and Ansible inventory. Historical Git commits may still contain earlier reference values, so secrecy is provided by access controls and key management rather than by assuming those old values are confidential.

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

## Public reference topology

The public repository documents **roles and trust boundaries**, not the authoritative live address map. Exact CIDRs, fixed addresses, OpenStack IDs and environment node counts belong in protected environment variables/inventory.

### Networks

```text
Management:   <MGMT_CIDR>
Kubernetes:   <K8S_CIDR>
WireGuard:    <VPN_CIDR>
```

The network names used in code are intentionally canonical:

```yaml
mgmt_cidr: <MGMT_CIDR>
k8s_cidr:  <K8S_CIDR>
vpn_cidr:  <VPN_CIDR>
```

### Virtual-machine topology

The public repository documents **roles and relationships**, not the authoritative live host/IP map. Exact addresses, peer mappings, node counts and provider IDs belong in private inventory and private Terraform variables.

| Role pattern | Purpose |
|---|---|
| `edge` | VPN entry, DNS, firewalling and edge security telemetry |
| `agent-oob` | optional out-of-band administrative agent/orchestrator host |
| `slurm-controller-01` | Slurm controller and accounting services |
| `login-01 ... login-N` | user-facing SSH/login and Slurm clients |
| `slurm-cpu-01 ... slurm-cpu-N` | CPU compute fabric |
| `storage-01 ... storage-N` | persistent research storage gateways/services |
| `api-lb-01` | stable Kubernetes API endpoint |
| `k8s-cp-01 ... k8s-cp-N` | Kubernetes control plane |
| `k8s-core-01 ... k8s-core-N` | core/service worker pool |
| `k8s-user-01 ... k8s-user-N` | Jupyter/user-workbench worker pool |
| `k8s-agent-01 ... k8s-agent-N` | optional agent/harness runtime worker pool |

Kubernetes clients use the stable API endpoint:

```text
<K8S_API_VIP>:6443
        │
      HAProxy
     /  |  \
   CP1  CP2  CP3
```

The API load-balancer implementation is intentionally replaceable. The important contract is the stable Kubernetes control-plane endpoint, not HAProxy itself.

Pi-hole at `<EDGE_IP>` is now advertised by Neutron DHCP to the management and Kubernetes subnets. Local OpenStack hosts therefore use the edge DNS service rather than depending only on provider defaults. Kubernetes pods still use CoreDNS; the intended path is `pod → CoreDNS → Pi-hole → upstream DNS`.

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
      ├── control plane × N
      └── worker pools × N
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

The platform now has two persistent-storage planes:

1. **Kubernetes persistent storage** through OpenStack Cinder CSI.
2. **HPC/research shared storage** through `storage-nfs-01`, backed by dedicated Cinder SSD volumes and exported over NFSv4.

Kubernetes currently exposes Cinder-backed StorageClasses for application/PVC workloads. The exact Cinder implementation remains cloud-specific.

The validated M1 research storage layout is:

```text
storage-nfs-01 <STORAGE_IP>

/srv/home      → /home/research on login/compute nodes
/srv/datasets  → /datasets
/srv/staging   → /staging
```

Cinder SSD volumes:

```text
home      512 GiB
datasets  2 TiB
staging   512 GiB
```

All three filesystems use XFS. Quota accounting/enforcement is enabled according to purpose: user quotas for home, project quotas for datasets, and user/project quotas for staging. The NFS exports are restricted to the management network and use `root_squash`.

Scratch remains ephemeral and compute-local. The single NFS gateway is an appropriate M1 shared-filesystem implementation, not a claim of parallel-filesystem or HA performance. BeeGFS/CephFS/Lustre remain later scale-out options.

The Slurm roles treat shared `/home/research` as a prerequisite and reject a local home filesystem on login/compute nodes. This keeps interactive and batch execution consistent before JupyterHub is introduced.

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

Slurm is now an operational independent HPC scheduler and execution plane.

```text
Users / future JupyterHub
          │
          ▼
   login1 / login2
          │
          ▼
       Slurm
          │
    ┌─────┴───────────────┐
    ▼                     ▼
 cpu-small              cpu-large
12 vCPU / 23 GiB      64 vCPU / ~250 GiB
×2 nodes              ×2 nodes
```

The validated controller/accounting topology is:

```text
slurm-controller-01
    ├── slurmctld
    ├── slurmdbd
    └── MariaDB (slurm_acct_db)

login1 / login2
    └── user-facing Slurm clients

slurm-cpu-01 / 02
    └── cpu-small

slurm-cpu-03 / 04
    └── cpu-large
```

Slurm 25.11.8 is built from checksum-pinned official SchedMD source into Rocky Linux 9 RPMs and then staged as one vetted artifact set across the fabric. M1 permits those locally built unsigned RPMs explicitly; issue #41 owns the later signed CI/SBOM/internal-Yum supply chain.

MUNGE authenticates Slurm RPCs. The service identities are deliberately deterministic across the cluster:

```text
slurm  5000:5000
munge  5001:5001
```

The live bring-up demonstrated why numeric identity is part of the distributed authentication contract: inconsistent auto-allocated UIDs produced `Unexpected uid`, malformed RPC and task-launch failures even though account names matched.

Interactive `srun` also requires compute nodes to connect back to the host running `srun` for stdio/control traffic. M1 constrains those callbacks with:

```text
SrunPortRange=60001-61000
```

and permits that range from the Slurm compute security group to the login-node security group. The login tier is the intended user submission boundary; the controller is an infrastructure host, not a normal user-facing execution host.

Validated execution on 27 September 2026 includes:

```text
cpu-small:
srun ... /usr/bin/hostname
→ slurm-cpu-01.novalocal

cpu-large:
32 CPUs + 128 GiB allocation
→ slurm-cpu-03.novalocal
→ nproc = 32
→ free -h ≈ 251 GiB total guest memory
```

CPU and memory isolation use cgroup v2 through `proctrack/cgroup`, `task/cgroup` and `task/affinity`. Slurm accounting is registered as cluster `quantum-cpu`.

The separation between Kubernetes and Slurm remains intentional: Kubernetes runs platform services and the default low-cost Jupyter workbench; Slurm schedules scarce or substantial researcher compute. The primary JupyterHub path is therefore **KubeSpawner for lightweight workbench pods**, with CPU/GPU/QPU work submitted on demand through the platform execution interface. BatchSpawner remains a supported secondary mode for explicit interactive-HPC sessions where the notebook server itself must live inside a Slurm allocation.

For the full recovery history and operational lessons, see [docs/tutorials/slurm-service-identity-recovery.md](docs/tutorials/slurm-service-identity-recovery.md).

## Agent orchestration: Agent Control Plane, Hermes and Heretic

The agent architecture has evolved beyond a single privileged "operations bot". The long-term model deliberately separates **identity and authorization**, **reasoning/runtime**, **skills and memory**, and **the systems that actually own infrastructure or scientific resources**.

```text
                         Users / Researchers / Operators
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
             Quantum Platform     JupyterHub       SSH / terminal
                    │                 │                 │
                    └─────────────────┼─────────────────┘
                                      ▼
                              Agent Control Plane
                         authorization / policy / audit
                                      │
                     ┌────────────────┼────────────────┐
                     │                │                │
                     ▼                ▼                ▼
                   Hermes          Heretic        other harnesses
             persistent runtime   skills/memory   reviewed agents
                     │                │                │
                     └────────────────┼────────────────┘
                                      ▼
                          bounded adapters / tools
                                      │
             ┌────────────────────────┼────────────────────────┐
             ▼                        ▼                        ▼
        Kubernetes                 Slurm             Prometheus/Wazuh/
                                                      Suricata/QPUs
```

The [agent-control-plane](https://github.com/nyameko/agent-control-plane) is the governance boundary. It owns task/run/evidence history, principal identity, policy checks, approvals, and bounded adapters. It does **not** replace Kubernetes RBAC, Slurm accounting, QPU-provider authorization, Git review, or application permissions; it coordinates them.

### Hermes

Hermes is the persistent agent runtime and orchestration environment. Different Hermes profiles can serve different scopes: personal research, programme assistance, security analysis, systems administration, or platform operations. The management/federation Hermes may run outside Kubernetes so that loss of the cluster does not automatically destroy the control root; research-facing profiles may run in Kubernetes with separate persistent state.

Hermes is deliberately not granted unrestricted administrative authority simply because it can observe a system. A useful first administrative vertical slice is intentionally narrow:

```text
operator request
      │
      ▼
Agent Control Plane
      │
      ├── validate principal / scope
      ├── persist task
      └── invoke one approved read-only diagnostic
                         │
                         ▼
                       Hermes
                         │
                  interpret evidence
                         │
                         ▼
                  task/run history
```

The initial diagnostic should be boring and auditable—for example, a fixed Prometheus/Kubernetes query—not arbitrary shell access.

### Heretic and other harnesses

Heretic is complementary to Hermes rather than a second authority plane. It can provide skills, memory, execution helpers, or reviewed harness behavior while ACP remains responsible for authorization and evidence. Future model routers may choose between Ollama, llama.cpp, vLLM, DeepSeek-style harnesses, remote frontier models, CPU VMs, A100/H200 GPUs, or QPU-backed workflows without changing who is allowed to do what.

The governing rule is therefore:

```text
model intelligence != authorization
```

A powerful model may recommend an infrastructure modification, but the safe path is normally:

```text
observe → reason → propose → PR to dev → review/test → promote
```

not:

```text
observe → kubectl apply as cluster-admin
```

The same control-plane boundary should eventually serve the Astro portal, JupyterHub, terminal clients, Discord/Telegram integrations, and external agent clients such as ChatGPT or Claude through typed, policy-controlled interfaces.

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

The repository has grown from bootstrap infrastructure into a GitOps-operated research facility. The exact tree evolves, but ownership remains explicit:

```text
infra-hpc-qc-k8s/
├── terraform/
│   ├── modules/                 # reusable OpenStack infrastructure
│   └── environments/            # site/environment composition
│
├── ansible/
│   ├── inventories/
│   ├── playbooks/
│   └── roles/                   # hosts, edge services, Slurm, security, etc.
│
├── argocd/
│   ├── applications/            # Argo CD Applications / app-of-apps
│   └── resources/               # Git-managed workload resources and overlays
│
├── docs/
│   ├── README.md                # documentation map / ownership
│   ├── INSTALLATION.md          # careful end-to-end deployment guide
│   ├── QUICK_GUIDE.md           # terse operational/deployment path
│   └── tutorials/               # concepts, experiments, failures and lessons
│
├── scripts/
├── Makefile
└── README.md
```

The repository is intentionally layered:

```text
Terraform
    cloud resources
        ↓
Ansible
    hosts + base infrastructure
        ↓
kubeadm / Cilium / Cinder CSI
    Kubernetes substrate
        ↓
Argo CD
    long-lived application desired state
        ↓
quantum-platform / agent-control-plane / observability / security services

Slurm remains a parallel execution authority for HPC work rather than a child of Kubernetes.
```

The application source repositories remain separate:

| Repository | Primary responsibility |
|---|---|
| [`infra-hpc-qc-k8s`](https://github.com/nyameko/infra-hpc-qc-k8s) | facility, cloud, hosts, Kubernetes substrate, GitOps deployment, observability/security integration, Slurm infrastructure |
| [`quantum-platform`](https://github.com/nyameko/quantum-platform) | researcher-facing Astro/Django product, identity, programmes, events, branded experiences, portal UX |
| [`agent-control-plane`](https://github.com/nyameko/agent-control-plane) | governed agent principals, task/run/evidence history, bounded operational adapters and approvals |
| [`quantum-workflows`](https://github.com/nyameko/quantum-workflows) | reproducible scientific/hybrid workflows, simulators, QPU providers, scheduler/provider provenance |

---

## Documentation model

The landing README is intentionally architectural. It should remain useful to somebody encountering the project for the first time and should not collapse into a list of links.

Detailed procedural material remains separate:

| Document | Purpose |
|---|---|
| [`docs/README.md`](docs/README.md) | documentation map and architecture/design-document ownership |
| [`docs/QUICK_GUIDE.md`](docs/QUICK_GUIDE.md) | concise commands for an operator who already understands the architecture |
| [`docs/INSTALLATION.md`](docs/INSTALLATION.md) | careful, ordered deployment and validation guide |
| [`docs/tutorials/`](docs/tutorials/) | educational deep dives, failure analysis, experiments and design lessons |

The normal reading path is:

```text
README: why / what / architecture
      │
      ├── QUICK_GUIDE: fast operational path
      ├── INSTALLATION: complete deployment path
      ├── design decisions: why a choice was made
      └── tutorials: what the implementation teaches
```

A corrective change to installation procedure belongs in `INSTALLATION.md`; a durable architecture decision belongs in the README and/or a design-decision document. Do not remove the architectural overview merely because a lower-level guide exists.

---

## Current verified platform state

The repository is a work in progress, so distinguish **manifest present** from **capability accepted end to end**. The operator-verified state as of 27 September 2026 includes:

### Infrastructure, networking and Kubernetes

- ✅ OpenStack network/VM foundation
- ✅ Rocky Linux base hosts
- ✅ three-control-plane / three-worker Kubernetes cluster
- ✅ stable HAProxy Kubernetes API endpoint at `<K8S_API_VIP>:6443`
- ✅ containerd / CRI
- ✅ Cilium baseline
- ✅ Cinder CSI persistent storage
- ✅ Argo CD application-of-applications
- ✅ cert-manager
- ✅ Traefik ingress
- ✅ Prometheus and Grafana
- ✅ Git-managed platform dashboards
- ✅ edge WireGuard/private-access path
- ✅ Pi-hole internal DNS at `<EDGE_IP>`
- ✅ Neutron DHCP advertises Pi-hole to management and Kubernetes subnets

### M1 persistent research storage

- ✅ dedicated `storage-nfs-01`
- ✅ 512-GiB research-home Cinder SSD
- ✅ 2-TiB datasets Cinder SSD
- ✅ 512-GiB staging Cinder SSD
- ✅ XFS filesystems and quota accounting/enforcement
- ✅ NFSv4 exports
- ✅ `/home/research`, `/datasets`, `/staging` mounted on login/compute nodes
- ✅ storage Node Exporter telemetry

### M1 CPU Slurm fabric

- ✅ official SchedMD 25.11.8 source built as Rocky 9 RPMs
- ✅ controller + slurmdbd + MariaDB accounting
- ✅ MUNGE shared authentication
- ✅ deterministic `slurm=5000:5000` and `munge=5001:5001`
- ✅ two 12-vCPU `cpu-small` nodes
- ✅ two 64-vCPU `cpu-large` nodes
- ✅ corrected allocatable RealMemory values
- ✅ cgroup-v2 CPU/memory enforcement configuration
- ✅ constrained `SrunPortRange=60001-61000`
- ✅ four compute nodes register cleanly and return to `IDLE`
- ✅ `cpu-small` interactive task launch from login tier
- ✅ `cpu-large` 32-CPU / 128-GiB interactive allocation from login tier
- ✅ Node Exporter healthy after service-identity migration

### Quantum Platform deployment

The public/live development portal tracks the `:dev` application channel while the product remains under active development. The current portal includes PostgreSQL-backed identity/programme state and the initial administrator/user surfaces. Resource provisioning into POSIX/Slurm identity remains a later controlled integration.

### Still active / not yet accepted as complete

- ⏳ Slurm operational hardening: formal sbatch/accounting/cancellation/walltime/two-node/MPI acceptance and warning cleanup
- ⏳ scheduler/accounting-specific Prometheus/Grafana metrics
- ⏳ final Wazuh/Suricata end-to-end re-verification after infrastructure changes
- ⏳ JupyterHub end-to-end researcher experience with every notebook scheduled through Slurm
- ⏳ Quantum Platform → POSIX/storage/Slurm provisioning reconciler
- ⏳ Agent Control Plane Phase 1 live deployment and persistent orchestration acceptance
- ⏳ staging environment and release-candidate conformance suite
- ⏳ QPU provider production integrations beyond controlled SDK/hello-world workflows

A green daemon, Kubernetes Pod or Argo application proves only that layer. End-to-end workflows are accepted only after the actual user/research path executes successfully.

## Security evidence architecture

Wazuh, Suricata, Prometheus and Grafana have complementary responsibilities:

```text
HOST / APPLICATION EVENTS                     NETWORK EVENTS
          │                                         │
          ▼                                         ▼
      Wazuh Agent                                Suricata
          │                                      eve.json
          ▼                                         │
      Wazuh Manager                                  │
          │                                          │
       alerts.json ◄─────────────────────────────────┘
          │
          ▼
       Filebeat
          │
          ▼
      Wazuh Indexer
          │
          ▼
      Wazuh Dashboard

Prometheus / Grafana
    availability, capacity, performance and correlated operational telemetry
```

The immediate acceptance test is not "the pod exists". It is:

1. generate one controlled host/application security event;
2. observe it at the Wazuh Manager;
3. find it in the indexed `wazuh-alerts-*` data;
4. view it through the private Dashboard;
5. generate one controlled Suricata event;
6. correlate the network alert with the host/security and operational timeline.

Suricata should be described as IDS until blocking/IPS behavior is deliberately enabled, tested, and recoverable.

Once the private recovery path is proven, remove public TCP/22 from both the OpenStack security group and edge nftables. Re-run the Cilium connectivity test while watching Grafana as an educational/operational exercise. Hubble, ClusterMesh and kube-proxy replacement remain deliberate later work rather than blockers for the baseline platform.

---

## Development, review and release governance

The repository family is moving to a common governance model. `main` is a protected release/review boundary, **not** the place where contributors start ordinary work.

The intended rule for all four repositories is:

```text
                         protected main
                               ▲
                               │ release approval
                        release/vX.Y.Z
                               ▲
                               │ freeze from dev
                          protected dev
                       ▲       ▲       ▲
                       │       │       │
                 feature/*  student/*  agent/*
```

No feature, student or autonomous-agent branch should originate directly from `main`. Contributors and agents branch from `dev` and return changes through reviewed PRs to `dev`. A release candidate is frozen from `dev`, validated in staging, then promoted into `main` and tagged.

If `dev` is absent from `infra-hpc-qc-k8s`, `agent-control-plane`, or `quantum-workflows`, create it from the current known-good `main` and protect both branches. `quantum-platform` already has a `dev` branch and currently publishes/consumes `:dev` images for the live development site.

### Source branch, image channel and deployment environment are different concepts

Do not conflate:

```text
Git source branch
        │
        ▼
container build / immutable digest
        │
        ▼
deployment desired state
        │
        ▼
Kubernetes environment
```

`infra-hpc-qc-k8s/main` may remain the reviewed GitOps source for the currently running facility even when a specific application intentionally consumes `quantum-platform:dev`. Testing infrastructure changes from `infra-hpc-qc-k8s/dev` should use a dedicated validation path rather than repointing the production root Application at an unreviewed branch.

Mutable environment tags (`:dev`, later a release-candidate channel) are convenient interfaces, but changing the digest behind a tag is not automatically a Git-visible change. The deployment pipeline must make a new build visible to GitOps so that the **matching** migration hook executes before the new API image rolls out. Do not return to manual pod deletion as a deployment mechanism.

---

## Staging and production isolation

Staging is a real environment, not merely another hostname pointed at the production database.

The preferred portal staging environment is:

```text
namespace: quantum-platform-staging
hostname:  staging.quantum.nyameko.com
access:    WireGuard / private ingress only
```

Its mutable state and credentials are separate:

| Capability | Production | Staging |
|---|---|---|
| PostgreSQL | production DB | separate staging DB |
| Cinder | production PVCs | separate staging PVCs |
| SealedSecrets | production values | separately sealed staging values |
| SMTP | real sender | sink / restricted allow-list |
| Slurm | production accounts/QOS | dedicated staging/test allocation where possible |
| QPU | controlled production access | simulator/sandbox, later bounded hardware smoke tests |
| Agent Control Plane | production ledger/runtime | separate staging ACP ledger/runtime |
| Hermes | production profiles | separate staging profiles/memory |
| Discord/Telegram | production channels | staging/test channels |
| WireGuard | production peers | separate staging test peers/configuration |
| Prometheus | production telemetry | staging telemetry; optional read-only production visibility |

The governing rule is:

> **Staging may observe production where useful; staging must never mutate production.**

A staging migration must never target the production identity database. Likewise, a staging agent must not inherit production Slurm, WireGuard, QPU, SMTP or chat credentials merely because the namespace is separate.

`quantum-workflows` does not need a Kubernetes namespace merely because a staging scientific job exists; Slurm/QPU execution remains owned by the scheduler/provider. If `quantum-workflows` later gains a persistent API/service, `quantum-workflows-staging` is the preferred `<service>-<environment>` namespace form.

---

## Near-term roadmap

The CPU execution substrate is now real, so the priority shifts from bringing up Slurm to hardening it and connecting the researcher experience.

1. **M1 Slurm hardening:** remove controller-side interactive callback exposure, formalize sbatch/sacct/cancellation/walltime/cgroup/two-node/MPI acceptance, and clean known slurmdbd/MariaDB/plugin warnings.
2. **Service identity:** finish the deterministic infrastructure UID/GID registry for Node Exporter and the RPM builder; future human/research identities remain owned by Quantum Platform.
3. **DNS/time:** finish Pi-hole/CoreDNS/WireGuard resolver validation and formalize the internal DNS and Chrony topology.
4. **Observability/security:** revalidate Slurm/Node Exporter dashboards, Wazuh agents and Suricata/Wazuh evidence using fresh time windows.
5. **JupyterHub workbench + burst compute:** run ordinary notebook servers cheaply with KubeSpawner on dedicated Kubernetes user workers; submit substantial CPU/GPU work to Slurm and QPU work to the future broker only when a cell/workflow needs it. Retain BatchSpawner as an explicit interactive-HPC profile, not the default.
6. **Quantum Platform provisioning:** approved platform identity → deterministic POSIX identity → shared home → SSH/WireGuard keys → Slurm account/association/QoS.
7. **Accelerators and external compute:** add A100/H200 and external Slurm/Lengau adapters only after the CPU/Jupyter path is authoritative.
8. **Agent Control Plane:** layer controlled agent orchestration onto already-authoritative Kubernetes/Slurm/storage/security systems rather than bypassing them.

The next-sprint closeout/hardening work is tracked in issue #56.

## Reproducibility

This project is intended to be reproducible, but reproducibility requires separating **code** from **environment-specific state and secrets**.

The repository should contain:

- reusable Terraform modules
- reusable Ansible roles
- public defaults and templates
- Kubernetes and Argo CD manifests
- SealedSecret ciphertext where deliberately appropriate for the target controller
- validation procedures
- documentation and design decisions

The environment must provide or protect separately:

- OpenStack authentication
- private inventory values
- SSH private keys
- WireGuard private keys
- Sealed Secrets controller recovery key
- application credentials and tokens
- QPU/provider credentials
- kubeconfigs and cluster-admin credentials
- plaintext production data
- institution-specific secrets or restricted endpoints

A public repository can describe a live deployment without publishing the credentials required to control it. Public infrastructure metadata is still useful reconnaissance, so expose only what serves reproducibility and operations.

A new operator should be able to clone the repository and reconstruct the environment by supplying provider/site-specific inputs rather than receiving a copy of the original operator's secret material.

---

## Engineering philosophy

A few principles guide the repository.

### Make the working path boring

The first implementation should prefer stable, understandable components over unnecessary complexity.

### Prove every layer

A service being installed is not the same as a service working:

```text
install
  ↓
configure
  ↓
inspect
  ↓
functional test
  ↓
failure / recovery test where appropriate
```

### Preserve failure knowledge

Troubleshooting is part of the educational value. Incorrect security-group scope, SELinux/service restrictions, CNI/CSI problems, ingress mistakes, mutable-image surprises, migration ordering, DNS/VPN failures and scheduler integration failures should remain understandable from the repository history and tutorials rather than disappearing into unexplained final-state manifests.

### Keep boundaries explicit

```text
Terraform             → cloud resources
Ansible               → hosts + base infrastructure
kubeadm               → Kubernetes bootstrap
Cilium                → cluster networking
Cinder CSI            → persistent storage integration
Argo CD               → long-lived application desired state
Prometheus / Grafana  → operational telemetry
Wazuh / Suricata      → security evidence
Slurm                 → HPC scheduling/resource authority
Quantum Platform      → researcher identity and product experience
Agent Control Plane   → governed agent tasks/tools/evidence
Hermes / harnesses    → reasoning and persistent agent runtime
Quantum Workflows     → scientific execution/provenance
```

### Human and agent contributions use the same engineering discipline

Agents may inspect, reason, create branches, write code and propose PRs. They do not receive a privileged path around branch protection, review, testing, authorization or production change controls.

### Build for the next person

A system is more valuable when another person can understand it, reproduce it, modify it, break it safely, and recover it.

---

## License and contribution

See the repository license and contribution guidance for the current project terms.

Contributions, experiments, provider adapters, documentation fixes, security/recovery tests and reproducibility reports are valuable—particularly where they make the platform easier for students, researchers, engineers and autonomous contributors to understand and safely extend.


## Wazuh & Suricata security milestone (23 September 2026)

The edge-host Wazuh Manager, fleet agents and Suricata IDS now form a verified security-event path through Filebeat into the Kubernetes-hosted, Cinder-backed Wazuh Indexer and private Dashboard. The dated acceptance test recorded 14 Active Wazuh identities (13 connected remote agents plus local Manager) and correlated a harmless Suricata SID 9900001 through Wazuh rule 86601 into a searchable `wazuh-alerts-4.x` index. This is a historical checkpoint—not a claim about live state or guaranteed retention.

**Start here:** [full deployment tutorial](docs/tutorials/wazuh-suricata-deployment.md) · [operational drills and failure analysis](docs/tutorials/wazuh-suricata-operational-drills.md) · [Wazuh & Suricata Grafana dashboard provenance](argocd/resources/grafana/dashboards/wazuh-suricata-observability/README.md). Terraform owns cloud networking and SGs; only edge has nftables; Ansible owns Manager/agents/Filebeat/Suricata; Argo CD owns Indexer/Dashboard; Wazuh evidence and Prometheus metrics remain distinct. The Argo application currently tracks `main`: a documentation merge into `dev` does not silently change a live deployment.

**Future teaching tracks:** Automation and Cloud Engineering Challenge (ACE) and Quantum Computing Challenge (QCC) are cross-repository programme milestones, not additional services installed by this documentation update. Use the challenge planning issues for scope, rules of engagement, isolation and deliverables.
