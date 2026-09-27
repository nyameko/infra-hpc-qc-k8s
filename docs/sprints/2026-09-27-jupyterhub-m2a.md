# Sprint — JupyterHub M2a workbench deployment

Date: 2026-09-27
Goal: deploy a low-cost KubeSpawner Jupyter workbench that shares the research
home and can later burst substantial work to Slurm/QPU execution APIs.

## Architecture for this sprint

```text
browser
  |
JupyterHub (Kubernetes)
  |
KubeSpawner
  |
cheap user pod
  |
/home/research/<user>
  |
future execution client
  +--> Slurm CPU/GPU
  +--> quantum-workflows / QPU broker
```

BatchSpawner remains an M2b acceptance path for explicit interactive-HPC
notebooks; it is not the default user experience.

## Sprint gate 0 — preserve the known-good cluster

- [ ] confirm all control-plane and worker nodes Ready
- [ ] record current Allocatable and requested resources
- [ ] confirm Cilium healthy
- [ ] confirm Cinder CSI healthy
- [ ] confirm Argo CD applications healthy
- [ ] confirm existing Quantum Platform, monitoring and Wazuh workloads healthy
- [ ] take/export relevant Git/cluster state before node-pool changes

## Sprint gate 1 — worker-pool structure

The existing general workers become the core/service pool. Do not move them
until labels/taints and workload tolerations have been validated.

Initial desired roles:

```text
k8s-core-01 ... k8s-core-N
k8s-user-01 ... k8s-user-N
k8s-agent-01 ... k8s-agent-N
```

For M2a, provision/identify three initial user workers using the standard
8-vCPU/64-GiB worker flavor.

User-node policy:

```text
label: hub.jupyter.org/node-purpose=user
taint: hub.jupyter.org/dedicated=user:NoSchedule
```

Acceptance:

- [ ] core workloads remain on core workers
- [ ] Jupyter test pod schedules only onto user workers
- [ ] loss/drain of one user worker does not affect core services

## Sprint gate 2 — shared research home from Kubernetes

The same authoritative `/home/research/<user>` must be visible through SSH,
Slurm and Jupyter.

- [ ] permit the Kubernetes user-worker network to mount the research-home NFS export
- [ ] install NFS client support on user workers
- [ ] expose the export to Kubernetes through a controlled RWX PV/PVC or
      equivalent reviewed mount
- [ ] create/verify the disposable `jhub-smoke` home and numeric UID/GID
- [ ] mount it into the single-user pod at the same absolute path
- [ ] prove a file written from SSH appears in Jupyter and vice versa

Do not create a second canonical per-user Cinder home.

## Sprint gate 3 — JupyterHub + KubeSpawner

Build/publish a pinned Hub image with KubeSpawner.

Initial smoke workbench:

```text
CPU request:    100m
CPU limit:      2
memory request: 1 GiB
memory limit:   4 GiB
```

- [ ] service account and minimum RBAC for user pod lifecycle
- [ ] Hub persistent state on Cinder
- [ ] KubeSpawner configured as the default spawner
- [ ] user pods require the dedicated Jupyter node label
- [ ] user pods tolerate only the dedicated Jupyter taint
- [ ] smoke pod runs as the provisioned numeric POSIX UID/GID
- [ ] no privileged container
- [ ] no hostPath
- [ ] no MUNGE key or Slurm administrator credential
- [ ] private/VPN ingress only
- [ ] idle culler configured conservatively after functional validation

## Sprint gate 4 — container/workbench contract

Start with one deliberately boring general research workbench image.

It contains:

- JupyterLab
- lightweight Python scientific baseline
- platform execution-client placeholder/interface
- agent-client placeholder/interface

It does not contain provider secrets or administrator credentials.

Application-specific Qiskit/PennyLane/Pulser workbenches follow only after the
base workbench is accepted.

## Sprint gate 5 — prove lifecycle and persistence

Acceptance tests:

- [ ] login -> spawn completes
- [ ] pod lands on a user worker
- [ ] resource requests/limits are present
- [ ] same persistent home is visible from SSH and Jupyter
- [ ] stop server deletes only the pod, not the home
- [ ] respawn restores files
- [ ] Hub restart preserves Hub state
- [ ] user-worker drain reschedules a new workbench cleanly
- [ ] idle culling removes pod while home/conversation/workflows persist
- [ ] core services are unaffected throughout

## Sprint gate 6 — burst-compute seam

Do not expose physical Slurm partitions as the primary notebook interface.

For this sprint, prove one bounded execution seam from the workbench. The first
implementation may be a thin authenticated service/gateway, but its public
contract should already look like a logical target rather than `sbatch -p ...`.

Target user experience:

```python
job = compute.submit(
    "cpu-smoke",
    script="hello.py",
)
```

Acceptance:

- [ ] notebook does not receive `munge.key`
- [ ] notebook does not receive Slurm admin credentials
- [ ] one logical target maps to an approved Slurm request
- [ ] job survives notebook disconnect
- [ ] state/result can be recovered by job ID
- [ ] scheduler identifiers are retained for provenance
- [ ] cancellation is user-scoped

## Sprint gate 7 — observability and evidence

Create/record:

- active Jupyter servers
- pending/running spawn count
- spawn latency
- user-pod CPU and RSS p50/p95
- worker requested/allocatable CPU and memory
- pod count per user worker
- NFS latency/error signals
- cull count
- execution submissions and failures

Do not resize from intuition after the pilot. Use this evidence before moving
from three to four/five user workers.

## Deliberately not in today's critical path

- production Quantum Platform SSO/provisioning
- hundreds-user scaling
- H200 interactive profile
- production QPU broker
- full quantum-workflows state machine
- production agent chat integration
- Harbor
- parallel filesystem migration
- Kubernetes autoscaler

The sprint is successful when the cheap workbench is reliable, persistent and
isolated, and one bounded burst-compute path is proven end-to-end.
