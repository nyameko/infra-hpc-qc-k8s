# Secrets policy

Preferred progression:

1. Ansible Vault for bootstrap secrets.
2. SOPS + age for GitOps-managed encrypted Kubernetes secrets.
3. A dedicated secrets manager when the platform is mature.

Never put the following in Git:

- OpenStack passwords/application credentials
- Terraform state
- SSH private keys
- WireGuard private keys
- Wazuh credentials
- TLS private keys
- Kubernetes admin kubeconfig
- kubeadm join tokens/certificate keys
- Hermes memory/soul state
