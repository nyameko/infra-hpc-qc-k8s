# M5 P1–P6 readiness after P0: site-by-site evidence gates

**Status: independent engineering analysis; NOT acceptance or deployment.**
P0 requires researcher-native Slurm login, portal removal of shared
privileged gateway, and observed cross-user denial. Subsequent steps
do NOT presume either GPU site is fully configured or federated.

> **Scientific preparation is cheap; expensive execution is scheduled.**

## Confirmed source-tree baseline (not a live cluster observation)

The current `dev` Ansible configuration declares `slurm_cluster_name: quantum-cpu`,
two CPU partitions (`cpu-small` and `cpu-large`) and four CPU-only
`slurm_nodes` in `ansible/group_vars/slurm_cluster.yml`. The public
`slurm.conf.j2` has no GPU GRES declarations or A100/H200 GPU partitions.
`cgroup.conf.j2` already sets `ConstrainDevices=yes`, but that **does not**
demonstrate GPU scheduling/device isolation without correctly declared GPU
devices, GRES and an observed allocation.

ACE's `ansible/playbooks/ace-inference.yml` configures a
`gpu_inference` host with NVIDIA/DCGM and `vllm_server`, not a Slurm
GPU compute node. The `axis-h200.yml` and `axis-h200-runtime.yml`
playbooks explicitly state they do **not** install Slurm. Therefore,
**neither ACE A100 nor Axis H200 scheduler integration can be inferred from
the current public source**. Private inventory / deployed configuration
could differ and must be inspected without disrupting existing inference.

This makes P1 an **evidence-and-admission gate**, not a trivial addition of
`#SBATCH --gres=gpu:1`.

## P1 — Discover what actually exists before configuring GPUs

**ACE A100** and **Axis Atmos H200** are independent operational domains.
For each site independently obtain operator-approved, non-secret evidence:

| Question | ACE A100 | Axis H200 |
| --- | --- | --- |
| Who operates `slurmctld`, `slurmd` and accounting? | Verify on actual host | Ask Axis / verify tenant entitlement |
| Does a scheduler actually manage this GPU? | `sinfo -N -l`, `scontrol show nodes` | Provider-sanctioned CLI/API; don't assume `slurmd` |
| GPU inventory/UUID/MIG/topology | `nvidia-smi -L`, `nvidia-smi topo -m` | Operator-authorized inventory |
| GRES & cgroups | `scontrol show config`, `scontrol show node`, cgroup.conf | Site-owned partition/GRES/cgroup configuration |
| MUNGE/UID consistency | id, user associations, submission node | Independent identity trust and mapping |
| Resource partitions and QoS | `sinfo -o '%P|%l|%G|%T'`, `sacctmgr show assoc` | Provider approved reservation/partition |
| Accounting for GPU-hours/TRES | `sacct -X -nP -j JOB -o AllocTRES,Elapsed` | Provider job/accounting telemetry |
| Inference GPU ownership | Confirm existing running A100 endpoints unaffected | **4 inference + 4 science** is target, not validated allocation |

**Fail closed:** if the H200 belongs to the provider's own scheduler, integrate
through its sanctioned submit channel; do **not** install a competing slurmd
or declare eight GPUs schedulable when four are reserved for inference.
Do not infer that the CPU `quantum-cpu` partition can allocate A100/H200.
The five independent student teams must share policy-controlled allocations;
one A100 is not five simultaneously dedicated GPUs.

## Deferred CPU cluster-fabric and performance acceptance (not a P0 gate)

The initial CPU `quantum-cpu` Slurm smoke and Ansible configuration do **not**
prove that all compute nodes expose a coherent research filesystem or
Lmod software stack. Track this independently; schedule a real site-wide
HPL acceptance run when operator time is available.

Evidence still required:
- Correct /home/research NFS export, per-node mount versions/options,
  UID/GID and POSIX ACL/0700 isolation, usable read/write on *each*
  login/compute node, no stale handles or ghost mounts; quantify throughput
  and metadata latency under realistic load.
- Lmod available to each authorized researcher on all CPU compute nodes,
  module paths/defaults and environment parity across nodes, with a real
  Slurm batch `module load` test (not merely login-node `module avail`).
- `srun` fanout, PMI/PMIx/MPI selection and fabric connectivity on
  multiple CPU nodes. Record `sacct` allocation, I/O and failure behavior.
- A **full CPU cluster** High Performance Linpack (HPL) benchmark with a
  real multi-node Slurm allocation, validated residual and measured
  sustained performance. HPL memory problem size and process grid must
  be adapted to the actual CPU nodes and network; not every provisioned
  core may be suitable for the first run. Compare achieved performance
  with a defensible measured peak and record versions.
- Observed cleanup, scheduler contention, exporter/telemetry and
  rolling-restart behavior, before declaring the CPU HPC fabric production-ready.

Do not call this complete from a one-node Slurm hello job. It is also
**not** a reason to delay the P0 researcher-authentication test. Actual
cross-node NFS and MPI correctness *does* matter before claiming
whole-cluster scientific reproducibility and HPL acceptance.

## P2 — CPU workbench → actual ACE A100 Aer GPU batch

Preconditions: P0 native per-user site access and P1 A100 isolation/offerings,
immutable compatible `qiskit-aer-gpu` OCI digest and site SIF path.
Run the source reference from
[Quantum Workflows PR #62](https://github.com/nyameko/quantum-workflows/pull/62).
One approved GPU, no interactive Jupyter reservation. User closes notebook,
reopens it, retrieves JSON, scientific validation and `sacct` device/TRES
evidence. Slurm job survives workbench restart. Do not claim P2 passed from
CPU unit tests or source syntax checks.

## P3 — Remote H200 repeat and data movement

Confirm Axis network/SSH/TLS egress, independent user identity and scratch
contract. Stage input by approved rsync/SFTP when reachable or resumable
HTTPS/object-store transfer initiated from the permitted side. Run with a
site-approved H200 GPU allocation and versioned image/SIF; stage results
back with SHA256 and ACL verification. No SSHFS for high-throughput live
GPU data, no cross-site NFS assumed. Keep local scratch/checkpoints at
the GPU site and return reduced products. Compare numerical agreement with
the A100 reference, image, driver, CUDA and accounting evidence.

## P4 — Researcher catalog / runs reconciliation, no redesign

Preserve the current Quantum Platform visual design. Extend backend
authorization only after native identity is actually proven. Bind one
offering to programme access, site, cluster, resource profile, approved
container digest and quota. Correlate `site+cluster+job-id`, user, entitlement,
timestamps, TRES, results and checksums. Verify cross-user denial of
status/reading/cancel, disabled membership and expired allocation. Avoid
an agent-selected UID or any service account that can impersonate users.
If portal submission requires per-user credential delegation, that is a
separately reviewed trust boundary; do not silently substitute a root
broker / Slurm-wide JWT signer. Preserve API compatibility before gateway
retirement; explicitly coordinate migration or degrade gracefully.

## P5 — Backend environment catalogue

Source scientific recipes and tests in Quantum Workflows, build OCI through
reviewed CI, promote verified immutable digest, convert to SIF under Infra
or provider control, and record SIF hash.

- Qiskit/Aer CPU+GPU: correct CUDA wheel and method.
- PennyLane Lightning CPU+GPU: gradients/physics crosscheck, cuQuantum CUDA.
- Cirq/qsim CUDA: test supported qsim backend vs simple CPU baseline.
- NVIDIA cuQuantum: direct cuStateVec/cuTensorNet, precision/memory validation.
- IQM native/fake: local emulator vs approved provider credentials.
- Pulser/Pasqal: Qutip/emu-sv/emu-mps semantics and test fixtures.
- PhotonicsLab: independent optical reference and measurement errors.

Build/reuse compatible groups, not one enormous vendor image, but do not
multiply images unnecessarily when dependencies are actually compatible.
Never assume Python 3.14 availability of every vendor SDK. A CPU demo is
not proof of GPU compatibility, and a simulator is not a QPU.

## P6 — Optional research guide, never scheduler authority

Only after authorized status and result records exist, Guide can suggest a
reviewed notebook, explain errors, interpret scheduler accounting and
compare completed experiments. Guide has no authority to change quota,
impersonate users, submit arbitrary commands, or spend QPU credits.

## Gates and ownership

| Gate | Primary owner | Evidence required | Deployment chat |
| --- | --- | --- | --- |
| P0 | Infra + Platform | researcher-native own job and denied cross-user action; remove shared credential | separate |
| P1 | Infra + Axis | actual per-site scheduler, GRES/cgroups and accounting, inference isolation | separate |
| P2 | Quantum Workflows | real A100 Aer GPU durable batch, validated results | separate |
| P3 | Infra + Workflows | real H200, checksum stage-out, validated resource usage | separate |
| P4 | Quantum Platform | unchanged UI, site-specific per-programme access, accurate Jobs | separate |
| P5 | Quantum Workflows | per-backend immutable image and scientific tests | separate |
| P6 | ACP | owner-bound assistant explanations and telemetry | separate |

**Do not** batch unrelated P1–P6 deployments into this P0 PR.
