# Researcher guide

## Access prerequisites

A public Quantum Platform login is not sufficient to consume HPC resources. Complete the approved research identity/programme path, register SSH and WireGuard **public** keys through the authorized portal process, and wait for the corresponding resource entitlement and POSIX identity reconciliation. Never transmit a private key through the portal, agent conversation or issue.

## Normal working model

1. Sign in to [Quantum Platform](https://quantum.nyameko.com/).
2. Open the research workbench from the authenticated portal once your access is active. The JupyterHub KubeSpawner workbench is for editing, small experiments and launching work, **not** a reservation for a GPU.
3. Keep notebooks, code and data in the provisioned `/home/research/<user>` rather than a disposable Pod filesystem. Check `pwd`, `id`, `echo "$HOME"` and `df -h "$HOME"` before long-running work.
4. Select a documented execution offering in the portal. The normal durable route is the platform execution API, restricted SSH gateway, Slurm allocation and versioned Quantum Workflows runner.
5. Observe the scheduler job ID, state, exit status, result location, `manifest.json` and `summary.json`. A submitted job is not yet a successful experiment.
6. Use the project/Guide assistant for help, but do not grant it administrator or shell access to diagnose a simple notebook issue.

## Slurm essentials

On an approved Slurm login host, `sinfo` lists partitions and `squeue -u "$USER"` lists queued/running jobs. `sacct -j <JOB_ID> --format=JobID,State,ExitCode,Elapsed` inspects a completed job when accounting access permits. Submit only facility-approved sbatch templates; partition availability and walltime constraints are site-specific. Avoid running compute-heavy work on login hosts. Interactive sessions must use the documented allocation policy.

For a reproducible simulation, keep the executor, scientific environment, image digest, input data hashes, random seeds, scheduler resources and result directory together. Request GPU/QPU allocations explicitly; CPU notebook success does not imply GPU/QPU access.

## Boundaries and help

JupyterHub may restart without changing the canonical research home. Persistent agent messages live in ACP, **not** merely in a Jupyter browser tab. A missing notebook is a storage/mount question; a missing prior conversation is an ACP identity/state question. Consult [Troubleshooting](Troubleshooting.md) and include redacted error messages, time, request/run ID, environment and reproducible steps in an issue.

See [M3 end-to-end guide](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/m3-account-workbench-slurm-sprint.md) and [research workbench operations](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/m2a-jupyterhub-kubespawner-workbench.md).