# Parallel GPU Slurm readiness — ACE A100 + Axis H200 (P1)

**Status: code candidates, NOT a production scheduler or GPU allocation.**
P0 (native authenticated user submission and owner-scoped cancellation) is
still a hard gate. No privileged helper, sudo/runuser impersonation,
shared job-cancellation key or second Slurm controller is permitted.

## What is observed, and what remains a hypothesis

The current Sebowa `quantum-cpu` control plane is
`slurm-controller-01` / `10.50.0.12`. Existing source
`ansible/group_vars/slurm_cluster.yml` lists **CPU-only** nodes and
Slurm **25.11.8 EL9** RPMs. Earlier live controller reports showed
`GresTypes=(null)`, `AccountingStorageEnforce=none`.
The existing shared `cgroup.conf.j2` specifies `ConstrainDevices=yes`,
but this alone does **not** show correct GPU device isolation.

AXIS XD670 is an eight-H200 Rocky 10 host with working GPU CDI smoke,
private outbound WireGuard `10.61.0.3`, and two operator-created XFS
mounts (`/srv/h200/inference/models` and
`/srv/h200/science/scratch`). **No Slurm/H200 job has passed.**
Inference GPU 0–3 vs science GPU 4–7 is a *proposed physical division*,
not a substitute for recording all eight UUID→PCI→device-minor mappings.
H200-to-controller TCP/6817 and controller-to-H200 TCP/6818 remain
subject to verified return routing, edge nftables and Neutron port security.
See [existing routing notes](Axis-H200-Slurm-Routing.md).

ACE A100 already hosts separate inference resources; do not take over
its devices, introduce a second allocator, run `nvidia_gpu_host` on H200,
or assume all ACE GPUs are on one scheduler-enabled Slurm node.
The initial A100 pilot requests **one separately approved science GPU**.

## P1 inventory on both sites (no host mutation)

1. Copy `ansible/inventories/gpu-slurm.example.yml` into ignored
   `ansible/inventories/private/gpu-slurm.yml`; merge existing approved
   SSH/ProxyJump parameters with those used by the Axis H200 preflight.
   Enter the real ACE node hostname and expected A100 GPU UUIDs. Enter
   all eight *already independently recorded* H200 UUIDs. Never commit
   host keys, private endpoints, credentials or MUNGE material.
2. Run `ANSIBLE_HOST_KEY_CHECKING=True ansible-playbook -i
   inventories/private/gpu-slurm.yml playbooks/gpu-slurm-readiness.yml
   --check` from `ansible/`. The role has no `become`, package,
   file-write, service or network mutation tasks. Commands run on
   the approved hosts using the operator's existing access.
3. Save the output in the protected operator evidence store. Review
   expected vs observed UUIDs, device minors, active compute processes,
   topology/NUMA, scratch mounts, `slurmd -C`, and reachable scheduler
   settings. Absence of `slurmd` on Axis is expected at this stage.
   Query each site separately if access is approved at different times.

The source deliberately fails if the site or full physical UUID inventory
is not filled in. **Successful inventory is not device isolation.**
Verify with the site operator which entity owns each GPU and which
provider permits Slurm daemon admission. An Axis-owned scheduler should
be used remotely, not competed with by another `slurmd`.

## P1 review-only GPU config generation

Copy the relevant `ansible/vars/{ace-a100,axis-h200}-gpu.example.yml`
to ignored `inventories/private/<site>-gpu-plan.yml`. After collecting
site evidence, populate GPU UUIDs, *actual* `/dev/nvidiaN` **minors**
(not NVIDIA displayed indices), the Slurm node name/IP, real CPU and
memory budgets, and approved project account list. The H200 plan must
list 4 science UUIDs and 4 non-overlapping inference UUIDs. ACE begins
with 1 approved A100 UUID, while all inference ownership is preserved.

To render into a **private local /tmp directory only**, explicitly set
both the review record and the opt-in:

```bash
cd ansible
ANSIBLE_HOST_KEY_CHECKING=True ansible-playbook \
  playbooks/gpu-slurm-candidate-render.yml \
  -e @inventories/private/axis-h200-gpu-plan.yml \
  -e gpu_science_render_enabled=true
# Equivalent: ace-a100-gpu-plan.yml
```

This produces `/tmp/gpu-slurm-candidate/<site>/gres.conf.candidate`
and `slurm-gpu.fragment.candidate`. No remote hosts are modified.
The candidate uses explicit `Name=gpu File=/dev/nvidiaN` with
`AutoDetect=off`, advertises only the approved science devices, and
sets the new partition `State=INACTIVE` for a later human-reviewed
admission. Never run an all-GPU autodetect profile on a partially
reserved science/inference host.

**The fragments are not standalone complete Slurm configuration files.**
Final `slurm.conf` must retain the current CPU partitions, add
`GresTypes=gpu` only once, share coherent node/partition definitions
across controller and clients, and install compatible, verified
`gres.conf` only on owned compute nodes. Do not add the Rocky 10
H200 to the existing EL9 Slurm RPM staging playbook; build/pin a
compatible Slurm 25.11.x package separately, using identical effective
controller protocol/version where required by the facility.

## Before changing the live scheduler

- **P0 security:** complete `nlisa` native own-job submit, `squeue`,
  `sacct`, `scancel`, and a denied cross-user cancellation. Retire
  the shared helper only after the portal execution path no longer uses it.
- **Scheduler:** audit `scontrol show config`, `sacctmgr` users,
  associations, limits, QOS, `AccountingStorageEnforce`, GPU TRES
  accounting and site partition allowlists. Enabling
  `AccountingStorageEnforce=limits,qos` on the *existing* controller
  impacts CPU jobs too; backfill and test CPU association permissions
  before a reviewed cutover. For each GPU site, approve GRES-only
  science UUIDs and negative inaccessible GPU tests in Slurm job
  cgroups. Also prove that unscheduled researcher processes cannot
  directly open reserved devices.
- **Hardware:** verify `/proc/driver/nvidia/gpus/*/information`
  UUID/PCI/device-minor mapping against `nvidia-smi`, NUMA, active
  inference devices/processes, H200 CPU/memory affinity and the
  A100 inference isolation boundary. The cgroup plugin must work on
  Rocky 10/cgroup v2; do not assume CDI provides Slurm job isolation.
- **Networking:** separately verify MUNGE interoperability,
  DNS/NodeAddr resolution, H200→controller TCP/6817, controller→H200
  TCP/6818, controller return routing and Neutron allowed-address pair,
  then any approved login/job-step paths. Do not restart Sebowa edge
  nftables through a full `flush ruleset` role.
- **Storage:** preserve existing NFS research identities on Sebowa;
  H200 scratch is *not* the NFS home. Stage scripts/input to approved
  H200 scratch and stage checksummed results back to durable storage.
  Confirm quota, per-user ownership and cleanup without exposing student
  credentials or mounting whole home directories via SSHFS.

Only after P1 evidence and P0 approval, progress to Quantum Workflows
Aer-GPU runner in PR #62, one authorized A100 `sbatch`, verified
`sacct AllocTRES/TRESUsageIn*`, numerical references and durable output.
Replicate on H200 with stage-in/out and independent checksums.
Do not mark P2/P3 complete based on `nvidia-smi`, CDI or a CI build.

Official references:
[Slurm GRES](https://slurm.schedmd.com/gres.html),
[gres.conf](https://slurm.schedmd.com/gres.conf.html),
[Slurm accounting enforcement](https://slurm.schedmd.com/accounting.html).
