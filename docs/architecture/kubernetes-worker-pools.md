# Kubernetes worker-pool architecture

Status: M2a design baseline.

## Current pool

The existing worker flavor is 8 vCPU / 64 GiB RAM. Three workers provide a
24-vCPU / 192-GiB core-services pool. Current requests are small relative to
that capacity, so there is no justification for resizing the existing workers
before Jupyter rollout.

Use the existing three workers as the **core/service pool**:

- Argo CD
- Traefik
- cert-manager / Sealed Secrets
- Cilium / CSI components
- Prometheus / Alertmanager / Grafana
- Quantum Platform
- PostgreSQL
- Agent Control Plane API/control workers
- Wazuh indexer/dashboard at current scale

Label these nodes `node-pool=core`.

## Jupyter pool

Provision three additional 8-vCPU / 64-GiB workers initially and label them
`node-pool=jupyter`. KubeSpawner selects this pool.

M2a workbench requests:

- 250m CPU requested; 2 CPU limit
- 1 GiB memory requested; 4 GiB limit

Three workers provide 24 CPU / 192 GiB. At 80% planning occupancy, CPU requests
support roughly 76 concurrent workbenches; RAM supports roughly 153. CPU request
is therefore the initial planning constraint. A fourth same-size worker raises
the conservative CPU-request capacity to about 102 concurrent workbenches.

Do not size for hundreds from registered-user count. Measure p50/p95 CPU,
resident memory, spawn latency, NFS latency and image-pull time first.

## Future pools

Do not create these before evidence requires them.

### Agent runtime pool

Agent Control Plane API, policy, queue and durable state remain core services.
Dedicated `node-pool=agents` workers become useful when many Hermes/Codex/
Claude/OpenClaw/Paperclip runtime pods are long-lived or run subprocess-heavy
tools. Model inference and arbitrary research code should not be hidden inside
these workers; route those to dedicated inference services, sandboxes or Slurm.

A first dedicated agent pool would normally be 2-3 workers of the existing
8-vCPU / 64-GiB class, sized from measured concurrency.

### Observability/security-data pool

Prometheus and Wazuh are modest today, but retention and a multi-node Wazuh
indexer can become memory/IO heavy. When that happens, create a dedicated
`node-pool=observability` or `node-pool=data`, normally three failure-domain
nodes, before merely enlarging every general worker.

### GPU/inference pool

Do not mix physical GPUs into the generic core/Jupyter pool. Dedicated GPU
nodes use explicit labels/taints and are owned by one scheduler at a time.
Interactive inference services may live on Kubernetes GPU nodes; batch research
training/simulation remains Slurm-owned.

## Taints

M2a starts with labels only. Add `NoSchedule` taints after verifying that Cilium,
Cinder CSI, node-exporter and every required DaemonSet tolerates the taint. This
avoids turning a clean node-pool migration into a networking/storage outage.
