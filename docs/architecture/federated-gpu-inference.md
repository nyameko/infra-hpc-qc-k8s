# Federated GPU inference fabric

## Purpose

The first ACE GPU site provides one reproducible A100 inference backend for M4a
without joining the remote GPU host to Kubernetes or Slurm.

The architectural contract is:

```text
Clients
   |
   v
Agent Control Plane
   |
   v
LiteLLM in Kubernetes
   |
   v
wg-fabric
   |
   v
ACE A100 / vLLM
   |
   v
Qwen3.5-27B
```

M4a keeps one logical model route, one LiteLLM replica and one vLLM backend.
Routing intelligence, fallbacks and multi-model policy are enabled only after
the persistence acceptance test is complete.

## Scheduling ownership

A physical GPU has one authoritative allocator at a time.

Initial ownership:

- `gpu-a100-01`: dedicated vLLM serving; not a Slurm node and not a
  Kubernetes GPU worker.
- future `ace-gpu-a100-02`: Slurm GPU compute.

Dynamic movement of GPUs between inference and Slurm is tracked separately as a
research problem.

## Network

Human/research VPN and infrastructure federation are separate:

- `wg0`: human/admin/research VPN;
- `wg-fabric`: routed site-to-site infrastructure overlay.

The ACE A100 has no floating IP. The ACE edge is the only public endpoint and
routes remote platform CIDRs over `wg-fabric`.

## Observability and security

Every managed ACE host runs:

- Wazuh agent;
- Node Exporter.

GPU nodes additionally run:

- NVIDIA DCGM Exporter;
- vLLM metrics endpoint.

Prometheus/Grafana remain in the platform observability plane and scrape the
remote exporters over the routed infrastructure fabric.

## Model storage

The A100 root disk is not used as the long-term model cache. Terraform attaches
a dedicated Cinder volume and Ansible mounts it at `/srv/models`.

## Reproducibility

Public repository:

- reusable Terraform module;
- sanitized ACE environment template;
- Ansible roles and playbook;
- logical architecture.

Protected/private state:

- live CIDRs/IPs;
- OpenStack cloud/project credentials;
- WireGuard private/preshared keys;
- vLLM bearer token;
- Wazuh manager address if considered private;
- Terraform state.

## Future

The same model-gateway contract can later point at:

- additional A100/vLLM nodes;
- H200/vLLM nodes behind the Axis AccessProvider;
- Ollama development backends;
- llama.cpp specialist/edge backends;
- other OpenAI-compatible engines.

ACP should continue addressing logical model names, not physical GPU hosts.
