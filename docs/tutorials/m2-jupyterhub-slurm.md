# M2b — BatchSpawner interactive-HPC Jupyter sessions

> **Architecture status:** supported secondary mode, not the default researcher experience.
>
> The normal JupyterHub path is documented in
> [M2a — KubeSpawner research workbench and burst compute](m2a-jupyterhub-kubespawner-workbench.md).
> This tutorial remains valuable because some workloads genuinely need an interactive
> notebook server *inside* a Slurm CPU/GPU allocation.

## When BatchSpawner is appropriate

Use this path when the notebook kernel must remain resident with the scarce resource:

- interactive accelerator debugging or profiling;
- large in-memory state that cannot sensibly be handed off as a batch stage;
- tightly coupled MPI/interactive work;
- short, explicitly entitled GPU/HPC sessions;
- validation of the Kubernetes ↔ Slurm interactive path itself.

Do **not** use it as the ordinary all-day notebook environment. Reading papers,
editing code, talking to agents and preparing workloads should normally occur in
a cheap KubeSpawner workbench.

## Execution path

```text
browser
  |
JupyterHub (Kubernetes control plane)
  |
BatchSpawner
  |
restricted submit/query/cancel gateway
  |
Slurm allocation
  |
Apptainer environment
  |
jupyterhub-singleuser
  |
/home/research/<user>
```

The Hub does not receive `munge.key`. The notebook server runs under the
researcher's POSIX identity and sees the same persistent home as SSH.

## M2b smoke profiles

The current branch keeps two CPU profiles only to prove the mechanism:

| profile | partition | CPU | memory | walltime |
| --- | --- | ---: | ---: | ---: |
| Development | cpu-small | 2 | 4 GiB | 2 h |
| Large interactive | cpu-large | 64 | 232 GiB | 4 h |

These are **acceptance-test profiles**, not the long-term product catalog. Future
interactive H200/A100 profiles must have strict entitlement, concurrency and
walltime policy.

## Bootstrap identity

M2 uses only the disposable `jhub-smoke` account. Do not manually create a
production researcher identity. M3 provisions real identity from Quantum
Platform approval.

## Trust boundary

The Kubernetes Hub gets a dedicated SSH capability, not the MUNGE key. The key
is a forced command with forwarding and PTY disabled. The gateway accepts only:

- `submit <user>`
- `query <jobid>`
- `cancel <jobid>`

Submission is executed as the provisioned POSIX user. The helper validates
JupyterHub entitlement, allowed job naming, partitions and walltimes.

## Required network paths

```text
Hub -> Slurm gateway -> scheduler
proxy -> allocated compute node:singleuser-port
compute node -> private Hub callback URL
```

Do not broaden the management plane to make this work.

## Acceptance gate

M2b is complete only when:

- the notebook server is visibly a Slurm job;
- `squeue` and `sacct` report the correct user/resources;
- Stop Server cancels the allocation;
- spawn timeout leaves no orphan allocation;
- Slurm walltime terminates the notebook;
- cgroup CPU/memory limits apply;
- the same `/home/research/<user>` persists through SSH and re-spawn;
- Hub restart safely reconciles or cleans up;
- arbitrary gateway commands are rejected;
- Kubernetes never receives `munge.key`.

This acceptance proves the **interactive-HPC escape hatch**. It must not be used
to justify reserving scarce resources during ordinary notebook idle time.
