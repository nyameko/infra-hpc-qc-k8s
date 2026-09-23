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

The repository is a work in progress, so distinguish **manifest present** from **capability accepted end to end**. The most recent operator-verified state (September 2026) includes:

### Infrastructure and Kubernetes substrate

- ✅ OpenStack network/VM foundation
- ✅ Rocky Linux base hosts
- ✅ multi-control-plane Kubernetes cluster
- ✅ stable HAProxy Kubernetes API endpoint
- ✅ containerd / CRI
- ✅ Cilium baseline
- ✅ Cinder CSI persistent storage
- ✅ Argo CD application-of-applications
- ✅ cert-manager
- ✅ Traefik ingress
- ✅ Prometheus and Grafana
- ✅ Git-managed platform dashboards
- ✅ edge WireGuard/private-access path

### Quantum Platform deployment

The public/live development portal has been deliberately moved from the mutable `:main` application channel to the `:dev` channel while the product remains under active development.

Verified deployment behavior included:

```text
Argo CD:
OutOfSync → Progressing → Synced / Healthy

Kubernetes:
quantum-platform-blog       :dev  Running
quantum-platform-users      :dev  Running
quantum-platform-user-api   :dev  Running
PostgreSQL                        Running
postgres-exporter                 Running

Django portal migrations:
[X] 0001_initial
[X] 0002_piapplication_auditevent
[X] 0003_agentprincipal
```

The `reconcile_programmes` management command was run for the existing approved PI application and created the corresponding programme membership. These are useful deployment milestones; they do not imply that every planned resource-provisioning integration is complete.

### Not yet accepted as complete

The following are active implementation areas and must not be described as finished merely because manifests, roles or documentation exist:

- ⏳ Wazuh Manager → alerts → Filebeat → Indexer → Dashboard end-to-end acceptance
- ⏳ Suricata EVE alert correlation through the security evidence path
- ⏳ production-quality Slurm user/resource integration from the portal/Jupyter path
- ⏳ JupyterHub end-to-end researcher experience
- ⏳ Agent Control Plane Phase 1 live deployment and persistent Hermes acceptance
- ⏳ persistent researcher coworker across portal/Jupyter/terminal
- ⏳ staging environment and release-candidate conformance suite
- ⏳ QPU provider production integrations beyond controlled SDK/hello-world workflows

Argo "Healthy" proves the declared Kubernetes resources are healthy; it does not by itself prove a cross-system workflow such as `portal → ACP → Slurm → QPU`.

---

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

The architecture is sufficiently defined that the priority is now closing operational loops rather than inventing new layers.

1. **Security evidence:** complete and prove Wazuh end to end, then Suricata correlation.
2. **Deployment correctness:** ensure every new `:dev` build causes a GitOps-visible rollout with the matching Django migration and a recorded rollback point.
3. **Slurm acceptance:** prove controller/accounting/login/compute path and one portal/Jupyter-facing bounded submission path.
4. **Agent Control Plane Phase 1:** deploy API + PostgreSQL, connect one persistent Hermes profile, expose one safe read-only diagnostic, surface task/run history in the Quantum Platform administrator interface.
5. **JupyterHub researcher path:** identity → approved programme → notebook → Slurm/GPU job with explicit authorization and audit.
6. **Staging:** create `quantum-platform-staging`, separate data/secrets/integrations, and a release-candidate conformance suite.
7. **Researcher experience:** events, branded programmes, persistent coworker, then the optional "Starship Enterprise" SSH/terminal cockpit.
8. **Advanced orchestration:** specialist research/security/sysadmin agents, model routing, external clients and progressively stronger—but still reviewed—automation.

---

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
