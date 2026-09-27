# M2a — KubeSpawner research workbench and burst compute

## Decision

The default JupyterHub session is a lightweight Kubernetes **research workbench**.
It is not an HPC reservation.

```text
browser
   |
JupyterHub
   |
KubeSpawner
   |
cheap user pod on dedicated Jupyter workers
   |
/home/research/<user>
   |
execution client
   +------> Slurm CPU/GPU jobs
   +------> future QPU broker
   +------> quantum-workflows
```

BatchSpawner remains available for explicit interactive-HPC cases, but is not
the default.

## Why

Most notebook time is spent reading, editing, visualising modest results,
preparing circuits/workflows, using Git and talking to the research co-scientist.
Holding 64 CPU cores, an H200 or any QPU entitlement throughout that idle time
would waste the scarce resource.

The workbench should therefore remain cheap and long-lived while expensive
resources are allocated per execution stage and released immediately after use.

## Default pod planning envelope

Start with **requests**, not limits, as the capacity-planning unit:

| resource | initial request | initial limit |
| --- | ---: | ---: |
| CPU | 250m | 2 cores |
| memory | 1 GiB | 4 GiB |
| ephemeral storage | measured/policy-driven | measured/policy-driven |

These are planning defaults, not promises. Measure real JupyterLab/kernel RSS,
CPU, image pull time and spawn latency, then revise.

Examples of requested capacity before cluster/system reserve:

| concurrent workbenches | CPU requests | memory requests |
| ---: | ---: | ---: |
| 50 | 12.5 cores | 50 GiB |
| 100 | 25 cores | 100 GiB |
| 200 | 50 cores | 200 GiB |
| 500 | 125 cores | 500 GiB |

Plan at least ~20–30% headroom for kube-system, DaemonSets, image pulling,
bursts, bin-packing loss and failure of one user worker. Capacity should be
computed from **Kubernetes allocatable**, not nominal VM flavor size.

## Worker-pool architecture

Do not turn the three existing generic workers into one undifferentiated pool.

Target:

```text
control plane x3
        |
core/service workers
  Argo / Prometheus / Grafana
  Quantum Platform / ACP / ingress
        |
dedicated Jupyter user workers
  label: hub.jupyter.org/node-purpose=user
  taint: hub.jupyter.org/dedicated=user:NoSchedule
        |
KubeSpawner workbench pods
```

This protects platform services from a burst of notebook users and gives the
user pool an independent scaling policy.

The current public Terraform template records `k8s_control_plane_flavor` and
`k8s_worker_flavor` as site-specific inputs but does not publish their real
vCPU/RAM values. Do not claim a precise present capacity until the live
OpenStack flavors or Kubernetes allocatable metrics are captured.

## Control-plane sizing

The existing **three-control-plane topology should remain**. Hundreds of
long-lived user pods do not by themselves justify adding control-plane members.

Scale control-plane VMs vertically only when evidence shows pressure, especially:

- sustained CPU or memory saturation;
- API-server request latency/error growth;
- scheduler queue/backlog;
- etcd backend/WAL latency;
- disk I/O contention;
- leader-election instability.

For stacked kubeadm control planes, etcd latency and resource starvation matter
more than raw user-pod memory consumption.

## Worker sizing decision

The likely scaling need is **more user-worker allocatable CPU/RAM**, not a larger
control plane.

Do not resize blindly. First record:

```text
kubectl get nodes
kubectl describe node <worker>
kubectl top nodes
kubectl top pods -A
```

and Prometheus metrics for:

- allocatable CPU/memory;
- requested vs allocatable CPU/memory;
- pending user pods and scheduling latency;
- per-workbench RSS/CPU percentiles;
- spawn time and image-pull time;
- node memory/disk pressure;
- pod eviction/OOM events;
- concurrent active and idle workbenches.

A useful planning formula is:

```text
required_cpu =
  concurrent_users * cpu_request / target_utilisation

required_memory =
  concurrent_users * memory_request / target_utilisation
```

Use a target utilisation around 0.7–0.8 until real failure-domain behavior and
burst patterns are known.

### Example

At 100 concurrent users with 250m CPU and 1 GiB requested, 80% target
utilisation implies roughly:

```text
31.25 allocatable CPU cores
125 GiB allocatable RAM
```

At 200 users:

```text
62.5 allocatable CPU cores
250 GiB allocatable RAM
```

This is a much better basis for selecting OpenStack worker flavors than guessing
from the word "hundreds".

## Persistent home

The KubeSpawner pod must see the **same POSIX home** as SSH and Slurm:

```text
SSH login                  KubeSpawner pod
     \                         /
      \                       /
       /home/research/<user>
                |
          Slurm job stages
```

Do not create an independent per-user Cinder home for Jupyter if SSH uses the
shared research filesystem. Cinder remains appropriate for service databases
and service/runtime PVCs.

The provisioning system must preserve the platform-assigned UID/GID in the
Kubernetes pod security context so NFS ownership is coherent.

## Software environments

JupyterHub's catalog should primarily describe **workbench environments**:

- General Research;
- Qiskit;
- PennyLane;
- Pulser/Pasqal;
- CUDA-Q;
- SQD/chemistry;
- AI/ML.

All may start on the same cheap Kubernetes resource envelope.

The same immutable OCI image family should be usable by the workbench and the
corresponding Slurm/Apptainer execution stage where practical. Environment and
execution resource remain separate objects.

## On-demand execution

Notebook users should not normally type physical Slurm partitions or QoS names.

Preferred user-facing interface:

```python
job = compute.submit(
    "qiskit-aer-large",
    script="simulate.py",
    inputs={"shots": 100000},
)
```

or a future notebook magic such as:

```text
%%qrun qiskit-aer-large
...
```

The platform execution service resolves the logical backend to:

- immutable container image;
- allowed Slurm resource class;
- account/QoS/partition/GRES;
- entitlement and programme budget;
- result/provenance destination.

Advanced SSH users may continue using `sbatch`, `srun`, `squeue` and
`sacct` directly. The product interface hides physical scheduler topology by
default.

Do not place broad Slurm trust material in notebook pods. A later execution
broker may use a tightly protected Slurm gateway or `slurmrestd` behind an
authenticated TLS/policy proxy.

## QPU behavior

A QPU is never held simply because a notebook is open.

```text
cheap notebook
   |
prepare/test/transpile
   |
submit QPU stage
   |
provider/QRMI/QDMI queue
   |
result/progress
   |
notebook continues cheaply
```

QPU workflow state must survive browser closure and notebook restart.

## Acceptance tests

M2a should prove:

- KubeSpawner creates a per-user pod;
- resource requests/limits are enforced;
- user pods schedule only on the dedicated user pool;
- idle culling works without destroying persistent home;
- the pod sees the same UID/GID and `/home/research/<user>` as SSH;
- notebook images are pre-pulled/cached sufficiently for acceptable spawn time;
- a notebook can submit a bounded logical CPU job without learning the physical partition;
- job state/result survives notebook disconnect;
- platform/core services remain schedulable during a user-pod burst;
- one user-worker failure does not corrupt home or platform state;
- Prometheus exposes concurrent-user, pending-pod, request/allocatable and spawn-latency evidence.

## M2b relationship

[M2b](m2-jupyterhub-slurm.md) validates the separate case where an entire
interactive notebook must reside inside a Slurm allocation. Keep it, test it,
and make its scarcity visible to the user—but do not make it the normal path.
