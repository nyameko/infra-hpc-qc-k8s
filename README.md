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

The ownership boundary is particularly important:

```text
Terraform
  owns cloud resources

Ansible
  owns machines, host configuration and bootstrap

kubeadm
  owns the initial Kubernetes control-plane/node bootstrap

Cilium
  owns Kubernetes networking

Argo CD
  owns long-lived Kubernetes applications

Slurm
  owns HPC scheduling and execution
```

Ansible deliberately does not become a giant Kubernetes application installer. Once the Kubernetes substrate and Argo CD exist, long-lived Kubernetes applications are deployed through GitOps.

## Bootstrap versus application lifecycle

The project has a small, explicit bootstrap boundary.

```text
Terraform
    ↓
OpenStack infrastructure
    ↓
Ansible
    ↓
Rocky Linux + base configuration
    ↓
kubeadm
    ↓
Kubernetes
    ↓
Cilium
    ↓
Argo CD bootstrap
    ↓
GitOps
```

Ansible is therefore responsible for getting the platform to the point where GitOps can take over.

After that:

```text
GitHub
   ↓
CI validation
   ↓
Argo CD
   ↓
Kubernetes applications
```

The first application deployment is deliberately a proof of this boundary:

```text
Git
 ├── Cinder CSI definition
 ├── StorageClasses
 └── encrypted credentials
       ↓
    Argo CD
       ↓
    Kubernetes
```

There may be unavoidable bootstrap actions such as creating the initial Argo root Application and placing a secret-encryption key into the cluster. These are bootstrap operations, not the normal application deployment mechanism.

## Secrets and GitOps

Secrets must never be committed to this public repository in plaintext.

The current direction is:

```text
Developer workstation
        │
        ├── SOPS
        └── age
             │
             ▼
      encrypted Kubernetes
      Secret manifests
             │
             ▼
           GitHub
             │
             ▼
         Argo CD
             │
             ▼
       Kubernetes Secret
```

The workstation does not need Kubernetes tooling or cluster credentials merely to create encrypted Git artifacts.

For example, the Cinder CSI credential is represented as an encrypted Kubernetes Secret containing the CSI driver's `cloud.conf`.

The plaintext source file is local-only and is ignored by Git. The encrypted `*.sops.yaml` artifact is the object stored in Git.

The age public key can be present in `.sops.yaml`. The corresponding private key must never be committed.

The cluster-side decryption key is a bootstrap secret. It is provisioned separately from the public Git repository and made available to the Argo manifest-rendering path.

The intent is that production operation does not depend on a developer laptop or a workstation Vault being online. A local Vault may remain useful as an administrative/root-of-trust tool, but it is not a runtime dependency of the platform.

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

The application uses the upstream `openstack-cinder-csi` Helm chart together with Git-managed resources.

The OpenStack credential is intentionally not committed in plaintext. The CSI driver consumes a Kubernetes Secret containing the `cloud.conf` configuration.

The intended lifecycle is:

```text
encrypted cloud.conf Secret
        ↓
Argo CD / GitOps
        ↓
Cinder CSI
        ↓
Kubernetes PVC
        ↓
OpenStack Cinder volume
```

This is deliberately a storage-interface contract rather than an application hard-coded to OpenStack. A different cloud provider can provide a different CSI implementation behind the same Kubernetes PVC/StorageClass abstraction.

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

The next validation step is to repeat the Cilium connectivity test while observing the Prometheus/Grafana telemetry stack. This turns network validation into an operational observability exercise rather than a one-time installation check.

## Argo CD

Argo CD is bootstrapped by Ansible, but applications are thereafter intended to be managed by Argo CD.

The architecture is:

```text
Ansible
   │
   │ bootstrap only
   ▼
Argo CD
   │
   ▼
Git repository
   │
   ▼
applications
   │
   ▼
Kubernetes
```

Argo CD itself is a Kubernetes application and therefore becomes part of the bootstrap boundary. Once running, Argo authenticates to the local Kubernetes API through its in-cluster ServiceAccount and RBAC rather than consuming the operator's kubeconfig.

The application controller currently uses a StatefulSet. This is an Argo implementation detail used for controller/sharding identity; it is not an indication that application state is being stored on a persistent disk.

The initial deployment intentionally remains small. High availability of the Argo control plane is a later hardening milestone.

## GitOps root application

The platform uses a root Application to establish the GitOps application tree.

```text
root
 ├── Cinder CSI
 ├── Prometheus
 ├── Grafana
 ├── Wazuh
 ├── JupyterHub
 ├── Hermes
 └── other platform applications
```

The root Application is the last explicit application bootstrap step. Once it exists, child applications are created and reconciled by Argo CD.

This keeps the bootstrap responsibility small and makes the Git repository the durable description of the platform's Kubernetes application state.

For the public reference repository, application definitions are generic and provider-aware where necessary. A private deployment repository can later select environment-specific values, credentials and overlays without forking the entire framework.

## CI/CD and the security boundary

CI validates changes. Argo deploys them.

```text
Hermes / developer
       ↓
      Pull Request
       ↓
GitHub Actions
       ↓
validation / tests
       ↓
human review + merge
       ↓
Argo CD
       ↓
Kubernetes
```

Hermes and other agents may propose code, configuration or infrastructure changes, but they should not receive direct production deployment authority.

In particular, an agent should not need:

```text
Kubernetes cluster-admin
Argo CD admin
OpenStack admin
SSH deployment credentials
direct CI/CD trigger privileges
```

This creates a deliberate separation between:

```text
reasoning
   ↓
proposed change
   ↓
validation
   ↓
human-controlled merge
   ↓
reconciliation
```

The same model applies to infrastructure changes where practical.

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
   + Cilium             + VM telemetry         + services
       │                    │                    │
       │                    │                 Hermes
       │                    │                 Heretic
       ▼                    ▼                    ▼
   workloads            Nova/Cinder        agents / services
```

The observability layer should eventually cover:

```text
Kubernetes
Cilium
nodes and VMs
OpenStack services
Cinder
Slurm
Hermes
Heretic
JupyterHub
Astro
Wazuh
Suricata
application workloads
```

Prometheus is the metrics plane. It should not be treated as a raw log store.

Security telemetry remains appropriately separated:

```text
Wazuh
  → security alerts, FIM, SCA, vulnerability and agent data

Suricata
  → IDS events and security telemetry

Prometheus
  → operational metrics

Grafana
  → unified operational/security visualization
```

The aim is correlation: cloud resource state, host health, Kubernetes state, scheduler behaviour, security events and application metrics should eventually be observable together.

## Wazuh and Suricata

The edge/security layer remains outside the Kubernetes application lifecycle where appropriate.

The reference edge host provides:

```text
WireGuard
Pi-hole
nftables
Suricata IDS
Wazuh manager / security services
SSH bastion
```

Wazuh agents can provide endpoint security telemetry from the relevant hosts.

The Kubernetes cluster can run Wazuh agents where that is useful, while Wazuh remains a security platform rather than being forced into a Prometheus-shaped architecture.

Suricata is treated primarily as an IDS/event source, with selected operational metrics exposed to Prometheus where useful.

## Slurm is intentionally outside Kubernetes

Slurm is not another Kubernetes application.

It owns:

- HPC scheduling
- resource allocation
- batch execution
- MPI workloads
- CPU/GPU scheduling

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

The initial Slurm deployment remains an Ansible-managed host deployment:

```text
slurm-controller-01
    ├── slurmctld
    ├── slurmdbd
    └── database

login1 / login2
    └── user access + Slurm clients

slurm-cpu-01 / slurm-cpu-02
    └── compute
```

Future GPU/HPC resources can be added without turning Slurm itself into a Kubernetes application.

The important boundary is:

```text
Argo CD
  → Kubernetes applications

Ansible / Slurm tooling
  → HPC execution environment
```

Slurm can therefore be integrated with the research platform without surrendering ownership of scheduling to Kubernetes.

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

The management/federation Hermes remains outside Kubernetes so that a Kubernetes outage does not automatically eliminate the management and federation control point.

Research-oriented Hermes services can run inside Kubernetes.

Heretic is a complementary controlled-execution/research component. Its permissions should remain explicit and constrained.

The long-term model is not "AI gets root":

```text
telemetry / APIs
       ↓
    Hermes
       ↓
inspect → reason → propose/request
       ↓
policy / review / controlled execution
       ↓
    Heretic
```

This boundary is especially important as multiple Hermes and Heretic agents begin operating together.

## Researcher interface

JupyterHub is the research gateway.

The intended user experience is:

```text
Researcher
    ↓
JupyterHub
    ↓
Python / notebooks / scientific workflows
    ↓
Hermes
    ↓
Kubernetes / Slurm / GPU / QPU resources
```

The researcher should not need to know which infrastructure layer executes a workload.

The platform should progressively abstract:

```text
CPU
GPU
MPI
Slurm
Kubernetes
QPU
hybrid workflows
```

behind a consistent research interface.

## Astro

Astro is the public/user-facing platform layer.

The immediate objective is to build a scientific research portal with:

```text
public landing page
research/project discovery
authentication/login
user identity
researcher dashboard
links into JupyterHub
links into scientific services
```

The near-term milestone is to deploy several Astro templates/themes and establish the portal/login experience.

Astro is therefore deliberately positioned above the infrastructure and research execution layers:

```text
Astro
  ↓
research portal / user experience
  ↓
JupyterHub / services
  ↓
Kubernetes / Slurm / hybrid compute
```

The website should not become coupled to OpenStack internals.

## Identity and PostgreSQL

PostgreSQL is intended to become the platform's application/user state store where a durable relational database is required.

The database should not become an authority over external providers.

For example, quantum-provider integration can maintain references such as:

```text
platform user
    ↓
external provider identity
    ↓
provider instance / CRN
    ↓
permitted execution context
```

while credentials remain controlled by the relevant provider and secret-management boundary.

The same principle applies to other external systems:

```text
PostgreSQL
  → platform state and relationships

Provider IAM
  → provider access authority

Kubernetes RBAC
  → Kubernetes authorization

Slurm
  → HPC scheduling authorization
```

This avoids turning the application database into a universal credential store.

## Quantum-computing direction

The infrastructure repository is the systems foundation for a later scientific software stack.

The expected separation is:

```text
infra-hpc-qc-k8s
    ↓
infrastructure + platform

UYUYU.africa
    ↓
student/research ecosystem

intro-hpc-qc
    ↓
educational / introductory workflows

hybrid-hpc-qc
    ↓
advanced hybrid HPC/QC platform and research workflows
```

Scientific Python, numerical validation and benchmarks should live in the appropriate scientific/software repositories rather than turning this infrastructure repository into a scientific-code monolith.

A future scientific repository is expected to organise testing separately from infrastructure:

```text
quantum/
├── qrmi/
├── simulators/
├── applications/
│   ├── finance/
│   └── hep/
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

The infrastructure platform therefore provides the execution substrate while scientific repositories own scientific correctness.

## Testing philosophy

Declarative Infrastructure as Code does not remove the need for tests.

The project uses a testing pyramid that distinguishes policy, security, materialisation, convergence and functionality.

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

### Terraform policy tests

Ask:

```text
Is this infrastructure configuration allowed?
```

Examples:

- required networks exist in configuration
- forbidden public exposure is rejected
- naming conventions are respected
- resource sizes are within policy

### Terraform security tests

Ask:

```text
Is the proposed infrastructure safely exposed?
```

Examples:

- security-group rules
- management-plane exposure
- Kubernetes API exposure
- SSH exposure
- network segmentation
- public/floating access

### Terraform infrastructure tests

Ask:

```text
Did the declared infrastructure actually materialise?
```

These may require provider-backed integration environments and should not necessarily run destructively on every pull request.

### Ansible convergence tests

Ask:

```text
Does repeatedly applying the configuration converge?
```

A correctly written role should not continuously change the system on every run.

### Ansible functional tests

Ask:

```text
Does the resulting host/service actually work?
```

Examples:

- service availability
- ports/listeners
- authentication
- configuration correctness
- integration with dependent services

Scientific tests and performance benchmarks remain distinct:

```text
tests
  → is it correct?

benchmarks
  → how well does it perform?
```

The eventual goal is to connect benchmark results with platform telemetry without making every pull request depend on scarce H100/H200/QPU resources.

## Real-world failure knowledge

This repository intentionally preserves lessons from actual deployment failures.

These include:

- OpenStack flavor name versus flavor ID handling
- OpenStack service-policy authorization versus service availability
- Cinder CSI and volume-type semantics
- Kubernetes kubeconfig placement
- Cilium node-health and networking requirements
- Kubernetes API load-balancer security-group scope
- HAProxy and SELinux interactions
- containerd package/repository differences
- CRI socket permissions
- NodePort/network behaviour
- stale package repositories
- separation of host automation from Kubernetes application lifecycle
- the need for observability before declaring infrastructure healthy

Failures are part of the teaching material. A useful tutorial should explain not only the final command but also why a plausible command failed.

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

The application layer should continue consuming stable platform contracts rather than provider-specific implementation details.

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

## Repository structure

```text
infra-hpc-qc-k8s/
├── ansible/                 # hosts + bootstrap/base infrastructure
│   ├── inventories/
│   ├── playbooks/
│   └── roles/
│
├── argocd/                  # GitOps applications + bootstrap
│   ├── bootstrap/
│   └── applications/
│
├── secrets/                 # encrypted GitOps secrets only
│   └── cinder/
│
├── kubernetes/              # provider-facing / cluster resource definitions
│   └── cinder-csi/
│
├── terraform/               # cloud infrastructure
│   ├── environments/
│   ├── modules/
│   └── tests/
│
├── tests/
│   ├── terraform/
│   │   ├── policy/
│   │   ├── security/
│   │   └── infrastructure/
│   └── ansible/
│       ├── convergence/
│       └── functional/
│
├── docs/                    # project documentation + tutorials
├── scripts/                 # helper/validation scripts
├── Makefile
└── README.md
```

The repository intentionally separates:

```text
infrastructure
host automation
GitOps applications
secrets
tests
documentation
```

rather than creating one undifferentiated automation tree.

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
tests/README.md
```

The tutorials are part of the project architecture, not an afterthought. They should explain both implementation and reasoning, with failures preserved as teaching material.

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
6. SOPS/age bootstrap + encrypted-secret path
       ↓
7. GitOps root Application
       ↓
8. Cinder CSI + StorageClasses
       ↓
9. Prometheus / Grafana
       ↓
10. Wazuh agents / security telemetry
       ↓
11. Slurm operational deployment
       ↓
12. Hermes + Heretic
       ↓
13. JupyterHub
       ↓
14. PostgreSQL / platform userdb
       ↓
15. Astro research portal
       ↓
16. research and quantum-computing applications
```

The stages are capabilities rather than an absolute prohibition on parallel work. Slurm, for example, can be prepared independently once the underlying VMs exist.

The order exists to make dependencies explicit:

```text
network
  ↓
cluster
  ↓
storage
  ↓
observability
  ↓
execution
  ↓
identity/state
  ↓
research interface
```

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
observe
  ↓
recovery / failure test where appropriate
```

Infrastructure should not be considered complete merely because an installer exited successfully.

### Separate ownership

Use the tool that owns the problem.

```text
Terraform
  → infrastructure

Ansible
  → hosts / bootstrap

kubeadm
  → Kubernetes bootstrap

Cilium
  → Kubernetes networking

Argo CD
  → Kubernetes application lifecycle

Slurm
  → HPC scheduling

Prometheus/Grafana
  → observability

Hermes
  → orchestration

Heretic
  → controlled execution
```

### Keep secrets out of Git

Plaintext credentials do not belong in the public repository.

Use SOPS/age or an appropriate secret-management workflow, with decryption keys outside the repository.

### Keep production independent of the workstation

A developer laptop should be capable of creating deployment artifacts, but production runtime must not depend on that laptop remaining online.

### Do not give agents unnecessary authority

Automation and AI agents should operate under least privilege and proposal/review boundaries.

### Build for portability

OpenStack is a reference implementation. Platform contracts should remain portable.

### Preserve failure knowledge

A failed deployment teaches something valuable when the failure, cause and correction are captured.

### Build for the next person

A successful deployment is not enough. The repository should make the system understandable, reproducible, modifiable, teachable and recoverable.

## Current milestone

```text
✅ OpenStack infrastructure
✅ Rocky Linux base configuration
✅ Edge/security baseline
✅ Kubernetes HA cluster
✅ Cilium
✅ Cilium connectivity validation
✅ Argo CD bootstrap
✅ SOPS/age encrypted Cinder credential committed

→ Argo SOPS/age runtime integration
→ GitOps root Application
→ Cinder CSI via Argo CD
→ Prometheus / Grafana
→ Wazuh agents / security telemetry
→ Slurm integration / operational deployment
→ Hermes + Heretic
→ JupyterHub
→ PostgreSQL / platform userdb
→ Astro research portal
→ scientific / quantum-computing applications
```

## Immediate objective

The immediate implementation objective is deliberately narrow:

```text
Kubernetes
   ↓
Argo CD
   ↓
encrypted secret support
   ↓
root GitOps application
   ↓
Cinder
   ↓
Prometheus/Grafana
```

Once that path works, the platform can stop relying on manual Kubernetes application deployment.

The next visible product milestone is the Astro scientific research portal: deploy several themes/templates, establish the public site, and complete the first login experience while keeping the research execution stack behind the platform boundaries described above.

## License and contribution

See the repository license for current terms. Contributions are welcome, especially improvements that make the platform easier to reproduce, adapt to another provider, teach, validate, operate safely, and extend into advanced HPC/AI/quantum research.
