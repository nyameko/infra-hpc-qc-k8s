# ADR — Hybrid Research Execution and State Boundaries

Status: **Accepted for M2/M3 design**
Date: 2026-09-27

## Decision

The platform separates five concerns that must not collapse into one scheduler,
filesystem or database:

1. **Product/control plane** — Kubernetes
2. **Scarce compute allocation** — Slurm and future QPU resource brokers
3. **Application environment** — immutable OCI images executed with Apptainer
4. **Research workspace** — POSIX identity plus persistent `/home/research/<user>`
5. **Durable platform/agent/workflow state** — PostgreSQL plus object/result storage

JupyterHub is a catalog-driven interactive client of this architecture. It is
not itself the resource scheduler and it does not define application
environments by installing packages on compute nodes.

## Target architecture

```text
                            Quantum Platform
                identity / programmes / entitlements
                  catalog / allocations / usage UI
                              |
              +---------------+----------------+
              |                                |
              v                                v
       JupyterHub / SSH                 agent chat surfaces
         interactive                       portal/Jupyter/CLI
              |                                |
              +---------------+----------------+
                              |
                              v
                       control APIs (K8s)
                              |
             +----------------+----------------+
             |                                 |
             v                                 v
        Slurm scheduler                 Agent Control Plane
 CPU / RAM / GPU allocations        sessions / tools / routing
             |                                 |
             v                                 v
      Apptainer environment              model endpoints
             |                      CPU/GPU inference as scheduled
             |
     +-------+---------+
     |                 |
     v                 v
/home/research      quantum-workflows
persistent data    staged CPU/GPU/QPU DAGs
                       |
              +--------+---------+
              |                  |
              v                  v
         classical Slurm       QRMI/QDMI/provider
         CPU / GPU stages       QPU allocation
```

## JupyterHub catalog model

A user-visible offering is not the same thing as a Slurm partition or a
container image. Keep these concepts separate from the beginning.

### Offering

Human/product-facing item such as:

- PennyLane Lightning — 2 vCPU / 4 GiB / 2 h
- Qiskit Aer — 64 vCPU / 232 GiB / 4 h
- accelerated simulator — 1 H200 / 2 h
- future vendor/QPU-backed environment

An offering refers to, but does not duplicate, an environment, resource class
and allocation policy.

### Environment

Defines the reproducible software stack:

- immutable OCI image digest
- Apptainer/SIF realization
- entry point
- container flags
- approved mounts
- accelerator requirements
- software/provenance metadata

Application images belong with the application/workflow repository that builds
them. Infrastructure owns admission, caching and execution policy. Mutable tags
are acceptable for development; production offerings resolve to an immutable
digest.

### Resource class

Defines what the scheduler allocates:

- partition
- CPUs
- RAM
- GPUs/GRES
- walltime ceiling
- account/QoS
- node/features/constraints where necessary

The same environment may run on multiple resource classes. The same resource
class may host multiple environments.

### Allocation policy

Defines scarcity and entitlement independently of software:

- who/programme may use the offering
- maximum concurrent sessions
- maximum walltime
- per-user and per-programme budget
- priority/QoS
- interactive vs batch permission
- expiry/event window
- optional approval requirement

For CPU/RAM/GPU, Slurm accounting and TRES are authoritative for consumed
resources. Quantum Platform owns product-facing entitlement and aggregates
usage. External QPU/provider allocations require a platform/provider ledger in
addition to Slurm because provider queue time, shots, credits and hardware
access are not accurately represented by CPU/GPU TRES alone.

## Container execution contract

Slurm allocates the resource envelope. Apptainer starts the selected immutable
application environment inside that allocation.

```text
JupyterHub
   |
   | sbatch
   v
Slurm allocation
   |
   | srun
   v
Apptainer exec <immutable SIF>
   |
   v
batchspawner-singleuser / JupyterLab
```

The compute host is intentionally thin. It needs scheduler/runtime integration,
drivers and the common HPC substrate; application Python stacks do not belong
on the host.

### Image distribution

Initial path:

```text
repo CI -> GHCR OCI image -> controlled staging -> root-owned SIF/cache
```

Do not pull mutable application images from the Internet every time a user
spawns a notebook. Resolve and stage approved immutable artifacts ahead of
time. A private registry/cache such as Harbor can be introduced later for
replication, retention, vulnerability scanning and controlled private images
without changing the execution contract.

For accelerator containers, the host driver remains authoritative and is
injected through the supported Apptainer accelerator path. Do not bake kernel
drivers into application images.

## Lmod

Lmod remains useful, but its job changes.

Use modules for the **facility substrate**:

- Apptainer
- MPI/compiler toolchains where host integration is required
- debugging/profiling utilities
- selected native HPC libraries
- QRMI/QDMI/SPANK-facing client tools

Do not use Lmod as the primary distribution mechanism for every Qiskit,
PennyLane, Pulser, chemistry or ML Python environment. Those application
stacks belong in versioned containers.

SSH users therefore receive a normal HPC shell with modules. A notebook
offering receives the same persistent home but starts inside a selected
container.

## Persistent user workspace

The POSIX identity and home are shared across login and compute:

```text
SSH login:
  /home/research/alice

Jupyter Slurm allocation:
  /home/research/alice -> same backing filesystem

workflow stages:
  /home/research/alice and approved /datasets /staging mounts
```

A container must never replace or hide the researcher's persistent home.
Interactive environments bind the authoritative home into the same absolute
path so shell, notebook and workflow views are coherent.

Long-lived high-volume datasets and workflow results should migrate to
programme/project storage instead of turning every user home into a data lake.

## Agent state and user experience

The research co-scientist is a platform capability, not a process tied to a
particular notebook pod or SSH session.

The same authenticated user may access it through:

- Quantum Platform
- JupyterLab extension/sidebar
- SSH/terminal client
- future Discord/Telegram adapters where policy permits

All clients address the same Agent Control Plane and conversation identity.

### Canonical state

Canonical durable state belongs in platform-owned persistence:

- conversation/thread metadata — PostgreSQL
- user/agent associations and policy — PostgreSQL
- durable memory records — PostgreSQL and/or versioned object documents
- attachments/evidence/large artifacts — object or research storage
- task/run/audit provenance — Agent Control Plane PostgreSQL

A Kubernetes PVC is **not** the authoritative personal-memory database.

Hermes or another harness may retain runtime-native session files on a
profile-specific PVC, but they are adapter/runtime state. They must be
reconstructable or refer back to stable platform conversation IDs.

### User-controlled research context

`/home/research/<user>` may contain explicitly user-owned material such as:

```text
~/.quantum/
  context/
  skills/
  notebooks/
  prompts/
  exports/
```

These are portable research artifacts and optional user-authored skills, not
the sole source of truth for platform memory.

Shared/reviewed skills belong in Git/versioned packages. Personal enabled-skill
metadata belongs in the platform database. Runtime copies may be materialized
into home or an agent workspace as needed.

## Where components live

| Component | Primary home |
| --- | --- |
| Quantum Platform web/API | Kubernetes |
| Identity/programmes/catalog/entitlements | Quantum Platform + PostgreSQL |
| JupyterHub control plane | Kubernetes |
| interactive notebook compute | Slurm |
| application environments | OCI registry -> Apptainer/SIF on Slurm |
| Lmod | login + Slurm compute hosts |
| user POSIX home | shared HPC storage |
| Agent Control Plane API/workers | Kubernetes |
| agent canonical chat/memory | platform/ACP PostgreSQL + object storage |
| harness-native cache/session files | dedicated runtime PVC where required |
| inference service | Kubernetes for service routing; GPU execution may be dedicated GPU service or Slurm-backed depending workload |
| deterministic scientific workflows | quantum-workflows |
| CPU/GPU workflow stages | Slurm |
| QPU stages | QRMI/QDMI/provider path |
| workflow result provenance | quantum-workflows contract + durable research/result storage |

## Scarcity and interactive accelerators

An H200 should not normally be held simply because a browser tab is open.

Provide two modes:

1. **Interactive accelerator offering** — explicitly scarce, short walltime,
   low concurrency, entitlement/QoS enforced.
2. **Dispatch from a cheap interactive notebook** — the notebook remains on a
   small CPU allocation while expensive GPU/QPU stages are submitted as batch
   work and released immediately when each stage completes.

The second mode becomes the normal QCSC model.

## quantum-workflows end state

JupyterHub and SSH remain human interaction surfaces. `quantum-workflows`
becomes the deterministic execution/orchestration layer for scientific work.

A future run may look like:

```text
small interactive notebook
       |
       v
submit workflow
       |
       +--> CPU preprocessing allocation
       |        complete -> release
       |
       +--> GPU simulator stage
       |        complete -> release
       |
       +--> request QPU allocation
       |        queue / submit shots
       |        partial evidence/results
       |        retry/resubmit under policy
       |        complete -> release
       |
       +--> CPU/GPU postprocessing
                complete -> release
       |
       v
structured result + provenance + usage
```

The workflow state machine must persist independently of any notebook session,
agent worker, Slurm allocation or QPU reservation. Resources are acquired per
stage and released as early as possible.

Agents may assist with planning, explanation, anomaly detection and reviewed
recovery. They do not replace the deterministic workflow state machine,
scheduler or authorization policy.

## Decisions to preserve through future phases

1. Kubernetes is the service/control plane, not the universal compute plane.
2. Slurm remains authoritative for HPC CPU/GPU allocation and accounting.
3. Software environments are immutable containers; hosts remain thin.
4. Jupyter offerings reference separate environment/resource/policy objects.
5. Real catalog/entitlement state ultimately belongs to Quantum Platform; the
   M2 ConfigMap is only a bootstrap implementation of the same schema.
6. Persistent POSIX home is identical through SSH, Jupyter and workflow stages.
7. Agent memory is platform data, not ephemeral notebook state.
8. Harness PVCs are runtime persistence, not the canonical user-memory store.
9. Expensive accelerators/QPUs should be acquired per stage whenever possible.
10. quantum-workflows owns scientific execution state/provenance; agents and
    notebooks are clients of it.
11. Credentials are brokered/injected just in time and are never baked into
    images or home-directory templates.
12. Infrastructure may change implementation details (registry, storage
    backend, federation, GPU sites) without changing these contracts.
