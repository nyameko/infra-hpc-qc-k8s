# 5. Slurm: the HPC Scheduler

## 5.1 Why Slurm sits next to, not inside, Kubernetes

See `docs/01` §1.5 for the full rationale. Short version: Kubernetes optimises for services; Slurm optimises
for batch and tightly-coupled parallel jobs. This platform runs both, on separate node pools, rather than
forcing one workload type into the wrong scheduler.

```text
Kubernetes  → services, notebooks, APIs, long-running workloads
Slurm       → HPC batch jobs, MPI and scientific workloads
```

## 5.2 Controller placement

```text
slurm-controller-01
     │
     ├── login1
     ├── login2
     │
     ├── slurm-cpu-01
     └── slurm-cpu-02
```

`slurmctld` runs on its **own dedicated VM** — not `edge`, not a login node. [SchedMD describes `slurmctld`
as the central management daemon](https://slurm.schedmd.com/slurmctld.html) and recommends single-purpose
node roles in production. The initial controller also hosts `slurmdbd` (accounting) and MariaDB, purely to
keep the first environment small; a dedicated database VM and a backup controller are both explicitly
deferred, not forgotten.

## 5.3 Login nodes

`login1` and `login2` are redundant user entry points — not the compute pool. Users submit jobs directly
from here with the standard Slurm commands:

| Command | Purpose |
|---|---|
| `sbatch` | Submit a batch job script |
| `srun` | Run a job step (often inside an `sbatch` script, or interactively) |
| `salloc` | Allocate resources for an interactive session |
| `squeue` | View the job queue |
| `scancel` | Cancel a job |

## 5.4 Compute partition

`slurm-cpu-01` and `slurm-cpu-02` are the first pure-CPU partition, each provisioned with **exactly 64
logical CPUs**. Their Ansible role is designed to fail the deployment outright if the OpenStack flavor
doesn't expose 64 CPUs — this is a good, concrete example to walk students through of infrastructure code
enforcing a hardware contract rather than silently degrading.

## 5.5 Roadmap

- `slurm-controller-02` as a backup controller
- A dedicated accounting database VM (separating `slurmdbd`/MariaDB off the controller)
- `slurmrestd` on a dedicated API VM, if the orchestration layer (Hermes, `docs/06`) needs high-volume REST
  access to job/queue state
- GPU partitions for H200/A100-class resources
- Configless operation, where nodes/clients pull their configuration from the controller instead of shipping
  static `slurm.conf` files via Ansible — worth adopting once the basic cluster is stable

> ▶ **Lab.** `ansible/roles/` currently has no `slurm` role, despite `make slurm` already existing as a
> Makefile target (`docs/03` §3.4). This is a genuinely good scoped exercise: write the `slurm` role
> (controller, login, and compute node variants) against the design in this document, including the 64-CPU
> flavor assertion described above. See `COURSE_OUTLINE.md` Module 7 and Module 10.

## 5.6 Sample job submission

A minimal `sbatch` script, useful as the first thing students run once a compute node is `IDLE`:

```bash
#!/bin/bash
#SBATCH --job-name=hello-cluster
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:05:00
#SBATCH --output=hello-%j.out

echo "Running on $(hostname)"
srun hostname
```

```bash
sbatch hello.sbatch
squeue -u $USER
```

**Further reading:** [Slurm documentation](https://slurm.schedmd.com/) · [SchedMD Quick Start Administrator
Guide](https://slurm.schedmd.com/quickstart_admin.html) · [Slurm accounting and QOS](https://slurm.schedmd.com/qos.html) ·
[Slurm configless mode](https://slurm.schedmd.com/configless_slurm.html) · [OpenHPC](https://openhpc.community/) ·
[OpenMPI documentation](https://docs.open-mpi.org/) as the reference MPI implementation most Slurm tutorials
assume.
