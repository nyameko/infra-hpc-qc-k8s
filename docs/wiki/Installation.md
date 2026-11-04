# Installation and bootstrap

This is an **operator procedure**, not an end-user self-service setup. The repository is a reference deployment; substitute your own provider inventory, CIDRs, DNS, security policies, certificates and credentials. Do not apply the example values against an existing production tenant.

## Prerequisites

Provide a supported OpenStack project (or implement a provider adapter), administrative access to Rocky Linux machines, a Git checkout, Terraform, Ansible and approved `kubectl` access from the Kubernetes administration host. Prepare encrypted/offline credential recovery and an out-of-band console before altering network/firewall policy.

## Acceptance-gated sequence

1. **Cloud:** inspect `terraform/environments/template` and the protected environment layout. Run `terraform fmt -check`, `terraform init`, `terraform validate`, and `terraform plan`. Review every potential creation/deletion and quota impact before an authorized apply.
2. **Host baseline:** from `ansible/`, validate inventory with `ansible-inventory -i inventories/private/hosts.yml --graph`. Check connectivity and run targeted bootstrap playbooks with reviewed privilege escalation.
3. **Edge:** configure WireGuard, DNS resolver, nftables/Neutron rules, certificates and API load-balancer. Validate `nft -c` before reload and preserve a recovery path.
4. **Kubernetes:** install runtime and kubeadm/control-plane roles. Check `kubectl get nodes -o wide`, readiness, Cilium connectivity and private DNS resolution.
5. **Storage:** validate Cinder CSI StorageClasses and persistent-volume claims; separately verify NFS exports, UID/GID mapping, mounts and recovery on Slurm nodes.
6. **GitOps:** bootstrap Argo CD root application, then progressively reconcile Cilium/storage, ingress, monitoring, databases and product applications. Pin versions and image digests. Record desired revision and observed deployment revision.
7. **HPC:** establish MUNGE/service identities, Slurm controller/accounting, login/compute nodes and controlled `sbatch` smoke. Verify `sacct` and shared result artifacts.
8. **Research:** perform identity approval/reconciliation, signed Jupyter launch and restricted Slurm submission with a fresh test identity. Separate destructive continuity tests require explicit approval.

**Stop on the first failed gate.** Do not compensate for a broken storage or identity layer by skipping ahead to portal application deployments.

Detailed playbooks: [installation guide](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/INSTALLATION.md), [quick command reference](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/QUICK_GUIDE.md), [Terraform README](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/terraform/README.md), [Ansible README](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/ansible/README.md), [GitOps README](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/argocd/README.md).