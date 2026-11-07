# M5 H200/A100 resource deployment contract (not activated)

Owner requests: **8 H200 GPUs total** at Axis Atmos, split **4 for
scheduler-backed scientific experiments and 4 for self-hosted model inference**;
one **ACE A100** allocation for the five independent student projects.

**This document is a deployment decision record, not a live GPU reservation.**
Do not reserve by numeric GPU indices alone or assume Atmos grants root,
Slurm-admin, container or partition modification privileges.

## Step 1 — choose the one authoritative allocator

After Atlas/Axis Atmos administration provides the approved boundary:
- **Preferred if we administer the host/scheduler:** inventory all 8 GPU
  **UUIDs**/PCI addresses, use Slurm GRES/TRES and device cgroups for exclusive
  allocation. Pin 4 distinct GPUs for a long-running inference allocation
  and leave the other 4 for research scheduling through the same allocator.
- **If Atmos owns the scheduler:** request separate capacity reservations via
  its existing resource provider. Use remote submit and restricted API/SSH
  pathways; do not install a competing `slurmd` daemon into the same host.
- If provider assigns independent per-GPU containers/VMs, use provider
  devices/network policy as the owner and let Slurm manage only its owned 4.
  Never assume NVIDIA_VISIBLE_DEVICES/CUDA_VISIBLE_DEVICES is isolation.

Do not assume contiguous GPU 0–3 and 4–7 correspond to fixed UUIDs after
reboot; record and verify physical allocation and NUMA topology.

## Step 2 — network and identity

ACP and the browser remain in the Sebowa K8s cluster. ACE A100 and Atmos
H200 are **separate provider environments**. Use the approved egress
TLS/WSS/SSH-reverse route; never depend on inbound WG where Atmos blocks it.
Terraform owns private security groups on ACE/Sebowa but does not magically
own Atmos ACLs. Host tooling is Ansible **only where provider authorization
permits**. No public :8000, root SSH or unauthenticated model route.

Per-user Slurm identities, walltime, account/project quota and result
ownership remain authoritative; agents never submit with root or a
shared all-powerful credential.

## Step 3 — inference launch

Only within an approved four-GPU allocation, launch pinned CUDA/vLLM serving
images and reviewed model weights. Start with one bounded H200 `research-general`
test (the Qwen3.5-27B existing logical candidate), then a coding model
`code-interactive` after tool-use benchmark. Expansion to parallel model
replicas must not consume the four scientific GPUs. Gateway is LiteLLM with
PostgreSQL virtual keys, per-tenant budgets, explicit routing and no
unapproved external fallback.

Monitor GPU UUIDs and memory utilization, restricted API reachability,
cancel/restart and model/driver compatibility; preserve model source commit,
license, tokenizer and context settings.

## Step 4 — science

One authorized user's `sbatch/srun` requests **one** H200 through
the approved scheduler, runs PennyLane Lightning GPU and a reference
scientific problem. Persist Slurm job/account/partition/GPU UUIDs,
manifest hashes, precision and comparison to an independently validated CPU
result. Progress to multi-GPU only after this works.

## Step 5 — ACE A100 student pilot

Provide **one** ACE A100 GPU under a separately approved team/student
reservation or queue. Students have their own Unix/Slurm accounts and
project-scoped storage; no root, no access to ACP databases, inference
secrets, infra states or other teams' private outputs. Five teams share by
time/queue or explicit scheduling policy; do not promise five simultaneous
full-GPU allocations on a single A100. Preserve the existing inference
service and active ACP infrastructure while testing student jobs.

## Human evidence (do not infer from CI)

- Eight device UUIDs recorded, exactly four designated science and four
  inference, with no overlap or unauthorized device access.
- One real H200 scientific run and one independently authenticated vLLM
  inference completion, without public endpoint exposure.
- One real separate ACE A100 student account/Slurm test and denied
  cross-team reads; system and security monitoring remain healthy.
- Reviewed rollback, release image digests, model weights, resource quotas,
  Atlas/Atmos contact and limits.

Implementation work is tracked in
[infra #267](https://github.com/nyameko/infra-hpc-qc-k8s/issues/267).
