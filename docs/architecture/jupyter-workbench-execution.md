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
core workers
  platform APIs, databases, agents, monitoring, ingress

user workers
  KubeSpawner notebook pods only
```

User workers should be labeled/tainted and capacity-managed independently.

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
250m CPU + 1 GiB requested per workbench, 2 CPU + 4 GiB limit, subject to
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
