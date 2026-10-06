# Current Platform State — M3 to M4 Handoff

This document is the short operational truth for the platform after the October 2026 M3 integration sprint.

It complements the historical tutorials. Those tutorials preserve the bring-up sequence and failures; this page answers **what is working now, what remains to close M3, and what M4 will build on top of it**.

## Repository boundary

`infra-hpc-qc-k8s` owns the physical and operational substrate:

- OpenStack networks, ports, security groups and VMs;
- Rocky Linux host configuration;
- WireGuard, Pi-hole, Wazuh and Suricata;
- Kubernetes, Cilium, Cinder CSI and Argo CD;
- Prometheus/Grafana;
- Slurm and shared research storage;
- JupyterHub infrastructure;
- deployment of `quantum-platform`, `quantum-workflows` runners and `agent-control-plane`.

It does **not** own research identity business rules, scientific workflow code or canonical agent conversations.

## Four-repository system

```text
infra-hpc-qc-k8s
    infrastructure, schedulers, storage, networking, GitOps
                │
                ▼
quantum-platform
    identity, programme policy, workbench, execution API
                │
                ▼
quantum-workflows
    scientific runners, labs, benchmarks, provenance
                │
                ▼
agent-control-plane
    persistent conversations/projects/memory/skills and agent policy
```

These are peer repositories with explicit ownership boundaries, not four layers that duplicate the same state.

## Validated M3 path

The live vertical slice is:

```text
Quantum Platform
      │
      ├── authenticated research identity
      ├── POSIX UID/GID
      └── execution request
              │
              ▼
       private CoreDNS/Pi-hole
              │
              ▼
     restricted Slurm SSH gateway
              │
              ▼
             sbatch
              │
              ▼
         Slurm compute
              │
              ▼
       Apptainer runner
              │
              ▼
      quantum-workflows
              │
              ▼
 /home/research/<user>/.quantum-platform/runs/
```

The reference M3c acceptance job completed successfully:

```text
workflow:      cpu-smoke
Slurm job:     15
partition:     cpu-small
state:         COMPLETED
exit code:     0:0
executor:      cpu
passed:        true
```

The run produced a structured `manifest.json`, `summary.json` and durable shared-storage result tree.

## CoreDNS private-zone ownership

Private Kubernetes service-to-infrastructure resolution is managed through the dedicated Ansible role:

```text
ansible/roles/kubernetes_coredns/
ansible/playbooks/kubernetes-dns.yml
```

Protected resolver addresses auto-load from private inventory:

```text
ansible/inventories/private/
└── group_vars/
    └── all/
        ├── site.yml
        └── research-users.yml
```

Do not require ad-hoc `-e @...` for normal private site variables.

## Identity and UID/GID state

The established policy is:

```text
0–999        OS/system
1000–4999    local/admin
5000–5999    infrastructure services
6000–19999   reserved
20000–29999  Quantum Platform research identities
30000–59999  future local/platform expansion
60000+       future federation/external space
```

`nlisa` remains the bootstrap identity at `20999:20999`.

Quantum Platform now contains migration `0007_posix_identity_allocator` and a never-reused allocator seeded at `21000`.

The remaining M3 identity acceptance gate is to prove a fresh approved user receives `21000:21000` and is reconciled across storage, SSH, Jupyter and Slurm without manual account construction.

## Workbench model

The default researcher experience is:

```text
Quantum Platform
      │
      ▼
JupyterHub
      │
   KubeSpawner
      │
lightweight per-user workbench
      │
      ├── many JupyterLab workspaces
      └── durable compute submitted externally
```

One Jupyter user currently receives one single-user server. Multiple JupyterLab workspaces/tabs are logical workspaces inside that server, not additional Kubernetes Pods.

Named Jupyter servers are intentionally deferred until after persistent-agent work.

The current workbench is for editing, small local execution, notebooks and agent interaction. Expensive CPU/GPU/QPU execution should not require keeping the notebook Pod on the scarce resource.

## Shared research storage

The current M3 research home remains NFS-backed and authoritative across SSH, Jupyter and Slurm.

That is suitable for the current proof-of-concept, but not the final scale-out storage design. Track parallel-filesystem evolution separately, including metadata-heavy Python environments, MPI/HPL, GPU outputs and persistent agent projects.

## Deferred HPC software stack

Lmod is installed on the login/compute tier, but the final facility software environment remains deferred.

The intended later model is:

```text
shared applications + shared modulefiles
             │
             ▼
            Lmod
    compiler / MPI / CUDA / ROCm
             │
             ▼
     native applications and/or
      Apptainer workflow runners
```

The absolute `/usr/bin/apptainer` path used by the M3 cpu-smoke is a bootstrap simplification, not the final application-software strategy.

## M4 handoff

M4 should not grant agents more infrastructure authority first. It should first establish durable user state:

```text
portal ───────┐
Jupyter ──────┼──► Agent Control Plane
SSH/TUI ──────┤        │
gptel ────────┘        ├── conversations
                       ├── projects
                       ├── memories
                       ├── skills
                       └── task/run history
                              │
                           Hermes
```

M4 acceptance should prove that a conversation/project survives:

- browser close;
- Jupyter Pod deletion;
- SSH disconnect;
- agent worker restart;
- switching to another supported client.

The control plane owns canonical state. Hermes/Paperclip/Herdr remain runtime or client/supervision components, not competing identity or memory authorities.

## Immediate acceptance checklist

Before calling M3 fully closed:

- [x] CoreDNS private-zone forwarding is managed as IaC.
- [x] worker nodes can reach the restricted Slurm login gateway.
- [x] Quantum Platform can submit an `sbatch` job.
- [x] cpu-smoke completes with `0:0`.
- [x] durable workflow artifacts survive under the research home.
- [x] POSIX allocator migration exists and is applied.
- [x] allocator sequence is seeded at `21000`.
- [ ] fresh approved user receives `21000:21000`.
- [ ] that identity is reconciled to NFS/SSH/Jupyter/Slurm.
- [ ] fresh user successfully completes cpu-smoke.

When those final three checks are complete, M3 is closed and all new product work should move into M4 or later milestones.
