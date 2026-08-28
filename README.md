# infra-hpc-qc-k8s

Infrastructure-as-code and GitOps source of truth for the Nyameko hybrid HPC / AI / ML / quantum-computing platform.

## Design principles

- Terraform owns OpenStack resources.
- Ansible owns VM operating-system configuration.
- kubeadm owns Kubernetes bootstrap.
- Argo CD owns in-cluster applications after bootstrap.
- Secrets and personal state live outside Git (Ansible Vault / SOPS+age / external secret store).
- No OpenStack VM except explicitly designated edge/ingress nodes should receive a floating IP.
- The Kubernetes API is reached through an internal OpenStack Octavia load balancer.
- Cinder provides RWO block storage; Manila/NFS provides RWX shared storage.
- Kubernetes is for services and interactive workloads; Slurm is reserved for traditional HPC scheduling.

## Repository model

`main` contains reusable modules, roles, schemas and sanitized examples only.

Recommended protected environment branches/forks:

- `env/personal`
- `env/production`
- `env/purple-1`
- `env/purple-2`

Do not place credentials, private keys, personal addresses, real WireGuard keys, Wazuh passwords, or Terraform state in Git.

## Current bootstrap target

Six Kubernetes VMs plus one edge-admin VM:

- edge-admin: 10.50.0.10
- cp-01: 10.51.0.11
- cp-02: 10.51.0.12
- cp-03: 10.51.0.13
- worker-01: 10.51.0.21
- worker-02: 10.51.0.22
- worker-03: 10.51.0.23

The example values are deliberately non-production and must be overridden in the environment branch.
