# 1. Architecture & Design

## 1.1 Scope: this is the personal/admin federation environment

`infra-hpc-qc-k8s` currently defines **one** environment, and it is deliberately the smallest, lowest-stakes
one: a personal/admin federation environment used to prove the automation, not the research production
cluster and not a future Purple Team (attack/defence) range. Everything downstream — how much trust Hermes
gets, how permissive the firewall is, whether Suricata runs in IDS or IPS mode — is calibrated for that
scope. When the environment is cloned to stand up the research cluster, every one of those calibrations
should be re-reviewed, not copied blindly.

**Further reading:** [The Twelve-Factor App — config](https://12factor.net/config) for why environment
separation belongs in infrastructure, not just application code; [NIST SP 800-160 Vol. 1, *Systems Security
Engineering*](https://csrc.nist.gov/pubs/sp/800/160/v1/r1/final) for the general principle of scoping trust
to the smallest viable environment first.

## 1.2 Design philosophy: strict separation of concerns

Four tools, four non-overlapping jobs. This boundary is the single most load-bearing decision in the repo —
almost every other design choice (idempotent Ansible roles, GitOps for apps, no application logic in
Terraform) exists to protect it.

| Layer | Owns | Must never do |
|---|---|---|
| **Terraform** | OpenStack networks, router, security groups, ports, floating IPs, VMs, API load-balancer infrastructure, persistent storage where appropriate | Install OS packages or configure services |
| **Ansible** | Operating system, SSH, time sync, edge services (WireGuard/Pi-hole/nftables/Wazuh/Suricata), Slurm, Kubernetes prerequisites | Replace the Kubernetes application deployment layer |
| **kubeadm** | Bootstrapping the Kubernetes control plane and worker join | Anything outside the cluster it is initializing |
| **Argo CD** | Kubernetes application deployment (the *normal* path for anything running in-cluster after bootstrap) | Touch infrastructure or host configuration |

```text
Terraform  ──▶ OpenStack infrastructure
Ansible    ──▶ operating systems + infrastructure services
kubeadm    ──▶ Kubernetes cluster
Argo CD    ──▶ Kubernetes applications
```

If you ever find yourself writing a `local-exec` provisioner in Terraform to configure a service, or an
Ansible task that `kubectl apply`s an application manifest, that is the boundary being violated — stop and
move the logic to the correct layer.

**Further reading:** [Terraform documentation](https://developer.hashicorp.com/terraform/docs) ·
[Ansible documentation](https://docs.ansible.com/) · [kubeadm docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/) ·
[Argo CD docs](https://argo-cd.readthedocs.io/) · [OpenGitOps principles](https://opengitops.dev/) for the
GitOps rationale behind putting Argo CD, not Ansible, in charge of applications.

## 1.3 VM topology

| VM | IP | Role |
|---|---:|---|
| `edge` | 10.50.0.10 | WireGuard, Pi-hole, nftables, Suricata IDS, SSH bastion, Wazuh manager + agent |
| `hermes-orchestrator-01` | 10.50.0.11 | Isolated personal Hermes orchestrator; read/report-only by default |
| `slurm-controller-01` | 10.50.0.12 | `slurmctld` + `slurmdbd` + initial MariaDB; no user logins |
| `login1` | 10.50.0.20 | SSH user login, Slurm client |
| `login2` | 10.50.0.21 | SSH user login, Slurm client |
| `slurm-cpu-01` | 10.50.0.30 | 64-core pure Slurm compute node |
| `slurm-cpu-02` | 10.50.0.31 | 64-core pure Slurm compute node |
| `k8s-cp-01` | 10.51.0.11 | Kubernetes control plane |
| `k8s-cp-02` | 10.51.0.12 | Kubernetes control plane |
| `k8s-cp-03` | 10.51.0.13 | Kubernetes control plane |
| `k8s-worker-01` | 10.51.0.21 | Kubernetes worker |
| `k8s-worker-02` | 10.51.0.22 | Kubernetes worker |
| `k8s-worker-03` | 10.51.0.23 | Kubernetes worker |

Kubernetes API VIP: **10.51.0.100**. WireGuard client pool: **10.60.0.0/24**.

> ⚠ **Gap.** This table is 13 VMs. `docs/03` (bootstrap sequence) says Terraform's expected result is "13
> VMs plus the Kubernetes API load balancer," and other docs describe that load balancer as its own VM
> (`api-lb-01`, running HAProxy). That VM has no row here and no IP assigned. See `docs/09` for the fix.
> There is also a naming split worth resolving before you deploy: the live repository's committed
> `README.md` calls this node `edge-admin`, while the newer draft docs (this pack included) call it `edge`.
> Pick one and propagate it into the Ansible role name, inventory group, and cloud-init filename together.

## 1.4 Network segments (summary — full detail in `docs/02`)

```yaml
mgmt_cidr: 10.50.0.0/24   # infrastructure management network
k8s_cidr:  10.51.0.0/24   # Kubernetes nodes + API load balancer
vpn_cidr:  10.60.0.0/24   # WireGuard clients
```

Three networks, not one flat `/22`, because a compromise or misconfiguration on the Kubernetes network
should not automatically expose the Slurm controller or the edge node, and WireGuard clients should never
be able to route directly to management infrastructure without transiting `edge`.

## 1.5 Why both Slurm and Kubernetes

This is a genuinely hybrid platform, not "Kubernetes with a Slurm VM bolted on." The two schedulers are
kept because they solve different problems well and neither solves the other's problem well:

```text
Kubernetes  → services, notebooks, APIs, long-running workloads, GitOps-managed platform components
Slurm       → HPC batch jobs, tightly-coupled MPI jobs, scientific/quantum-simulation workloads
```

Kubernetes' bin-packing scheduler and container model are a poor fit for a 256-rank MPI job that needs
topology-aware placement and exclusive node access; Slurm's batch scheduler is a poor fit for a
always-on ingress-fronted web service with rolling updates. Running both, on separate node pools, avoids
forcing either workload type into the wrong abstraction. This is also why `login1`/`login2` are explicitly
*not* part of the compute pool — the entry point and the executor are architecturally separate, matching
standard HPC cluster design.

**Further reading:** [Slurm overview](https://slurm.schedmd.com/overview.html) ·
[Kubernetes vs. HPC schedulers (Kubernetes blog: batch workloads)](https://kubernetes.io/docs/concepts/workloads/controllers/job/) ·
[MPI standard](https://www.mpi-forum.org/docs/) for why tightly-coupled parallel jobs have different
placement requirements than microservices.

## 1.6 Hermes federation (summary — full detail in `docs/06`)

```text
Personal Hermes (hermes-orchestrator-01, outside Kubernetes)
      │
      ├── Infrastructure Hermes
      ├── Research Hermes (research-hermes, inside Kubernetes, deployed later)
      └── future environment agents
```

The orchestrator lives outside Kubernetes on purpose: a Kubernetes control-plane failure should never be
able to take the orchestration/reporting root down with it.

## 1.7 Domain plan

| Domain | Purpose |
|---|---|
| `nyameko.com` | Primary/root domain |
| `research.nyameko.com` | Research cluster (later environment) |
| `jupyter.research.nyameko.com` | JupyterHub |
| `grafana.research.nyameko.com` | Observability dashboards |
| `argo.research.nyameko.com` | Argo CD UI |
| `hermes.research.nyameko.com` | Research Hermes endpoint |
| `quantum.nyameko.com` | Astro public site (first end-to-end deployment target) |
| `omra.nyameko.com` | Future nonprofit, intentionally unrelated to the technical platform |

DNS for the public hostnames sits at Cloudflare; internal resolution runs through Pi-hole on `edge` (see
`docs/02` §2.6). Keep these two DNS layers mentally separate: Cloudflare answers for the public internet,
Pi-hole answers for anything inside `mgmt_cidr`/`k8s_cidr`/`vpn_cidr`.

**Further reading:** [Cloudflare DNS docs](https://developers.cloudflare.com/dns/) ·
[Pi-hole docs](https://docs.pi-hole.net/).

## 1.8 Environment evolution roadmap

```text
Initial environment (this repo, today)
   │  personal/admin federation — proves the automation, minimal trust surface
   ▼
Research production cluster
   │  same layer boundaries, larger/GPU-capable node pools, hardened Wazuh IPS posture,
   │  Research Hermes goes live, real user accounts and quotas
   ▼
Purple Team environment(s)
   │  intentionally vulnerable/instrumented clones for offensive+defensive training;
   │  should be network-isolated from the above, not just namespace-isolated
```

> ⚠ **Gap.** "Purple Team environments" is named in the root README as a downstream deliverable but nowhere
> defined — no network isolation model, no data-sensitivity boundary from the research cluster, no stated
> relationship to Hermes's telemetry access. Treat this as an open design question, not an implementation
> detail; see `docs/09` recommendation #6 and `COURSE_OUTLINE.md` Module 10 for a proposed way to turn this
> gap into a capstone exercise instead of leaving it unresolved.

## 1.9 Deployment order

1. **Terraform** — OpenStack networks, router, security groups, ports, VMs, and the Kubernetes API load
   balancer.
2. **Ansible** — OS hardening, SSH, Wazuh agent, edge services, Hermes orchestrator host, Slurm nodes,
   Kubernetes prerequisites.
3. **kubeadm** — bootstrap 3 control-plane + 3 worker Kubernetes cluster.
4. **Cilium + OpenStack CCM + Cinder/shared-storage CSI.**
5. **Argo CD.**
6. **Platform services** — ingress, cert-manager, Prometheus/Grafana/Loki, Wazuh indexer/dashboard,
   JupyterHub, Ollama, llama.cpp.
7. **Research Hermes**, inside Kubernetes, once the layers above are healthy.

Slurm is configured independently of this chain, after the base OS layer — it doesn't depend on Kubernetes
being up.

**Further reading:** [CNCF Cloud Native Landscape](https://landscape.cncf.io/) for how this stack maps onto
the broader ecosystem · [Site Reliability Engineering (Google, free online book)](https://sre.google/books/)
chapters on infrastructure layering, as general background for why ordered, dependency-aware bootstrap
sequences matter at this scale.
