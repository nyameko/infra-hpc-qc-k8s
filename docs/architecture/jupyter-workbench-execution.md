# Jupyter workbench, burst compute and Kubernetes capacity

Status: **architecture decision**

The platform distinguishes a **workspace** from an **execution allocation**.

- JupyterHub + KubeSpawner: cheap, persistent research workbench.
- Slurm: substantial CPU/GPU resource authority.
- QPU broker / QRMI / QDMI: quantum resource authority.
- BatchSpawner: optional interactive-HPC notebook mode.
- quantum-workflows: durable multi-stage execution state.

This preserves scarce resources during the long periods where a researcher is
reading, editing, plotting, planning or talking to an agent.

## Kubernetes placement

Kubernetes hosts the workbench because it is a service-like, lightweight,
long-lived process. This does **not** move HPC scheduling into Kubernetes.

Use separate worker purposes:

```text
core/service workers
  ingress, GitOps, observability, platform APIs, PostgreSQL, ACP control services

Jupyter user workers
  KubeSpawner notebook pods only

agent-runtime workers
  Hermes/Codex/Claude/OpenClaw/Paperclip workers and bounded agent jobs
```

The Agent Control Plane API, policy/audit service and its durable database remain
core services. Agent/harness execution is isolated because it is burstier, has
different egress/tool permissions and may eventually launch sandboxed jobs.

### Reference pool shape

The current reference OpenStack flavors are:

- control plane: 8 vCPU / 16 GiB per node;
- general worker: 8 vCPU / 64 GiB per node.

The existing three general workers should become the **core/service pool**.
Their present requests are small relative to capacity, so there is no capacity
reason to replace or enlarge them before JupyterHub.

Recommended initial pools:

| Pool | Initial shape | Purpose |
| --- | --- | --- |
| control plane | 3 × 8 vCPU / 16 GiB | kube-apiserver, scheduler, controller-manager, etcd |
| core/service | 3 × 8 vCPU / 64 GiB | Traefik, Argo CD, Prometheus/Grafana, Wazuh services, Quantum Platform, PostgreSQL, ACP API/control services |
| Jupyter user | 3 × 8 vCPU / 64 GiB for pilot; 4 nodes before ~100 concurrent workbenches | KubeSpawner user pods |
| agent runtime | 2 × 8 vCPU / 64 GiB initially; move to 3 for stronger HA/concurrency | agent/harness workers and bounded tool jobs |

Do not put large-model GPU inference on the agent-runtime CPU pool. GPU inference
is a separately scheduled capability (dedicated inference service or Slurm/GPU
backend).

For ~200 concurrently running 1-GiB-request workbenches with one-node failure
headroom, plan roughly five 8-vCPU/64-GiB user workers before measurement-based
refinement.

User and agent workers should be labeled/tainted and capacity-managed independently.
Core services should use topology spread/anti-affinity where they have replicas so
one worker failure does not remove every replica of a critical service.

## Sizing principle

The public repo currently exposes the number of Kubernetes nodes but not the
actual site-specific control-plane/worker flavor values. Capacity decisions must
therefore be tied to live `Allocatable` and observed workload percentiles.

Do not increase control-plane count for Jupyter users. Three HA control planes
are sufficient in topology; scale them vertically only from API/etcd evidence.

For user workers, forecast from per-pod requests:

```text
capacity ~= allocatable / requested-resource-per-workbench
```

with 20–30% operational/failure headroom. The initial planning point is
100m CPU + 1 GiB requested per workbench, 2 CPU + 4 GiB limit, subject to
measurement.

## Scaling stages

1. **Now:** preserve the three generic workers for core platform services while
   measuring their real allocatable resources.
2. **Before broad Jupyter rollout:** introduce dedicated Jupyter user workers.
3. **At tens of users:** validate bin-packing, image pulls, NFS behavior and idle
   culling.
4. **Before hundreds:** size the user pool from measured p50/p95 RSS and CPU,
   reserve failure headroom, and automate node provisioning/scaling if the
   OpenStack environment supports it reliably.
5. **Do not hide scarcity by overcommitting memory.** CPU can be bursty;
   memory exhaustion kills kernels and destabilizes nodes.

See [M2a](../tutorials/m2a-jupyterhub-kubespawner-workbench.md) for the concrete
capacity model and acceptance tests.
