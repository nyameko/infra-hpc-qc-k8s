# H200 remote scratch and batch-first data staging (planning contract)

**Status:** source-only M5 planning. The Axis provider must approve filesystem roots, quotas, network transports and site-specific identities before any automation or mount.

## Filesystem boundaries

- **ACE Jupyter research home**: the existing protected /home/research/<user> workspace for notebooks, code, small input datasets, manifests and returned result summaries.
- **Axis H200 scratch**: per-researcher/project directory **approved by the Axis site operator**, on H200-accessible storage. This is **not automatically the same NFS** and not a Kubernetes PVC.
- **Compute-node local scratch** (`$SLURM_TMPDIR` or operator-approved path when provided): high-throughput temporary simulation inputs/checkpoints during a scheduled allocation. Stage back before allocation disappears.
- **Durable results**: validated output store with experiment IDs, checksum, per-user ACLs and retention. Store large outputs in an approved object store or facility dataset store instead of forcing full copies into workbench NFS.

## SSHFS / symlinks

Yes, a personal **SSHFS** mount may expose *small* remote files through a user's authorized workbench or a dedicated accessible jump node if FUSE, network rules, credentials and storage policies allow it. A symlink to that mount merely refers to the mount point; it does not create a persistent/scheduler-visible filesystem. Disconnected sessions, cache inconsistency, latency, metadata storms, token refresh and mount lifecycle make this a **poor default for large or concurrent GPU I/O**. Never assume Slurm compute nodes can see a FUSE mount made inside Kubernetes; no shared privileged multi-user SSHFS gateway or key forwarding. SSHFS is optional convenience, not the job data plane.

## Recommended batch data flow

1. **Prepare**: notebook writes a manifest of selected inputs, checksums, requested GPU/CPU/walltime, image digest and approved site quota. Do not upload hidden/private files by default.
2. **Stage-in**: per-user, approved site transfer: `rsync` over SSH/SFTP for small-to-medium incremental data, or approved S3-compatible **multipart/resumable object transfer** for large datasets. When Axis permits only **outbound TCP/443**, use an Axis-initiated broker/relay or direct short-lived signed object-store URLs, *subject to provider/security approval*. Do not presume inbound SSH.
3. **Verify**: hash file list, lengths and ownership/permissions; deny cross-programme paths. The staging service cannot choose an arbitrary submit user. Mark input ready only after an explicit checksum pass.
4. **Submit**: native `sbatch` as the authenticated researcher's account on the site-authorized submit node; Slurm/GRES/cgroups isolate the H200, and job references the staged local path. No remote GPU Jupyter session.
5. **Compute**: `srun apptainer exec --nv` on the allocated host, on local/site scratch. Avoid continuous checkpoint writes over WAN/SSHFS. Use scientific, application-aware checkpoints and set retention/size quotas.
6. **Stage-out**: transfer **explicitly selected** result files and provenance after completion; write manifest atomically; verify SHA256 and artifact sizes before advertising `available`; retries must be idempotent and not trigger job resubmission. Preserve failure/cancellation state and accessible logs.
7. **Reconcile/clean**: `sacct` GPU/elapsed/TRES and site/cluster-qualified scheduler ID into ExecutionRecord, access-checked for current researcher/programme. Apply approved expiration and cleanup; never delete results before verified return.

## Large-data decision rules

- MiB: small input/JSON/plots — rsync/SFTP generally sufficient.
- GiB: incremental rsync when files are stable and permissions permit; parallel transfer only if site policy permits. Chunked/object-store transfer often better for immutable large files.
- Hundreds of GiB/TiB: object store or facility-supported high-bandwidth transfer/staging, site egress cost/bandwidth estimate, resumability, checksums, retention and data locality; **do not** pull all data repeatedly into ACE NFS through SSHFS.
- If datasets are already resident at Axis, compute there and return *reduced products* instead of copying all raw data to ACE.

Slurm burst-buffer mechanisms are optional future optimisation if **the actual site** supports them; do not implement a fake burst-buffer provider.

## Release dependencies and evidence

P0 authenticated researcher Slurm access, P1 isolated science GPU allocation, P2 actual A100 batch run, **P3 verified H200 stage-in / batch / stage-out**; followed by P4 portal usage, P5 backend images, P6 agent guidance. Observe bandwidth, retry, throughput, checksum and access-denial tests and capture the effective site quota before adopting a transfer service.

The source reference is [Quantum Workflows M5](https://github.com/nyameko/quantum-workflows/blob/dev/docs/M5-BATCH-FIRST-SIMULATOR-PATH.md). This does not grant approval to change Atmos configuration or run GPU workloads.
