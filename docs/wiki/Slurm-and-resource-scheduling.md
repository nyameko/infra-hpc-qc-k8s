# Slurm HPC and scientific execution

## Scheduler role

Slurm is authoritative for CPU/GPU resource allocations, partitions, walltime, QOS/accounting and job lifecycle. Kubernetes operates the portal, Jupyter control plane and services; ACP is not a job scheduler. Durable scientific execution should be submitted through Quantum Platform's restricted gateway or an approved Slurm login host, with research identities reconciled to NFS and accounting.

## Authorized user operations

```sh
sinfo
squeue -u "$USER"
sacct -j <JOB_ID> --format=JobID,JobName,State,ExitCode,Elapsed,AllocTRES
scontrol show job <JOB_ID>
```

Use approved `sbatch` templates and partitions. The compute nodes, node classes, walltime and acceptable job name patterns may vary between sites such as the CPU facility and Axis Atmos GPUs. These are policy settings, **not** a command-line option that an agent may invent. Do not submit expensive work solely to test whether a name is allowed.

## Validated scientific route

Quantum Platform's `ExecutionRecord` refers to an approved submission, Slurm owns scheduler job ID/state and Quantum Workflows owns the scientific run artifact. The simplest `cpu-smoke` checks that the gateway, scheduler, Apptainer runner, filesystem and provenance interact; it does **not** prove quantum science correctness or access to an H200/QPU.

## Common pending/failure reasons

Inspect the scheduler `Reason` (association/QOS, partition, wrong walltime, no nodes, priority, reservations, resources). After completion inspect exit code, stderr, result directory, hashes and actual numerical checks. `COMPLETED` with `0:0` only establishes process success. A missing file may be NFS permissions or runner configuration, not Slurm failure.

## Development responsibilities

Changes to Slurm daemon config, MUNGE keys, package versions, service UID/GID or network ports are privileged infrastructure changes; review the appropriate Ansible role and migration/restart implications. Never write credentials or privileged ssh host keys into a notebook.

Sources: [Slurm deployment](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/05-slurm-hpc-scheduler.md), [M1 CPU fabric](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/m1-slurm-cpu-fabric.md), [M3 end-to-end execution](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/m3c-cpu-smoke-slurm-execution.md), [GPU federation design](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/federated-gpu-inference.md).