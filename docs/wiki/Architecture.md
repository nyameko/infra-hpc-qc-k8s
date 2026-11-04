# Architecture and component ownership

## Layered dependency model

```text
Terraform/OpenStack -> Rocky Linux/Ansible -> edge/VPN/DNS/HAProxy
-> kubeadm -> Cilium + Cinder CSI -> Argo CD -> workloads
                          +-> Prometheus/Grafana / Wazuh/Suricata
Independent HPC path: NFS/XFS -> MUNGE + Slurm -> CPU/GPU scheduler
Research access: Quantum Platform -> JupyterHub (KubeSpawner)
                                  -> restricted submission -> Slurm -> workflows
Agent path: Quantum Platform identity -> ACP -> approved runtime/harness
```

Terraform provisions provider resources; Ansible configures hosts; kubeadm bootstraps control plane; GitOps reconciles applications. Keep manual `kubectl apply` changes out of the normal release lifecycle. The default Jupyter single-user server uses KubeSpawner, with multiple logical JupyterLab workspaces inside one server; the legacy BatchSpawner templates are **not** the production default.

## Trust boundaries

Management, Kubernetes and WireGuard networks are separate security domains. Public documentation intentionally uses `<MGMT_CIDR>`, `<K8S_CIDR>`, `<VPN_CIDR>` and named roles, not a live sensitive topology. WireGuard is the intended administrative entry; edge nftables, cloud security groups and Cilium policies provide different boundaries, not interchangeable controls. Cluster services use internal DNS through CoreDNS/private resolvers.

Shared research homes use stable POSIX identities; database identity is managed by Quantum Platform, and provisioned into NFS/Jupyter/Slurm through approved reconciliation. Identity allocation is not a side effect of anonymous signup.

## Data ownership

| State | Owner / authority |
|---|---|
| Terraform state and cloud assets | Site operator and provider |
| Host inventory and key custody | Protected inventory/vault |
| Kubernetes desired application state | Argo CD manifests |
| Research identity and entitlements | Quantum Platform |
| Shared user files | Research home/NFS |
| Slurm job state/accounting | Slurm/slurmdbd |
| Scientific data and provenance | Quantum Workflows / relevant science package |
| Persistent agent conversations/memory | ACP PostgreSQL |

See [federated platform design](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/federated-quantum-centric-platform.md), [hybrid research execution](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/hybrid-research-execution.md) and [Jupyter execution](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/jupyter-workbench-execution.md).