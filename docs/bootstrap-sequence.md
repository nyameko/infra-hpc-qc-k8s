# Bootstrap sequence

1. Create/select the OpenStack project and quotas outside this repository if Keystone administration is required.
2. Select an exact Kubernetes patch release in environment configuration; keep only the minor repository URL in Ansible.
3. Populate environment-specific Terraform variables out of Git or in a private environment branch.
4. Run Terraform to create networks, router, security groups, ports, edge-admin, six Kubernetes VMs and the internal Octavia API load balancer.
5. Verify that the Kubernetes API VIP is `10.51.0.100` in this example and is outside the DHCP/allocation pool.
6. Run `ansible-playbook -i inventories/personal/hosts.yml playbooks/bootstrap.yml`.
7. Establish WireGuard and verify VPN-only access.
8. Remove the temporary public SSH ingress rule from the edge-admin security group.
9. Run `ansible-playbook -i inventories/personal/hosts.yml playbooks/kubernetes.yml`.
10. The join playbook creates a 30-minute kubeadm token and certificate key on CP1 and keeps the values in Ansible memory only; they are never committed.
11. Verify `kubectl get nodes -o wide` and etcd/control-plane health.
12. Install Cilium.
13. Install OpenStack CCM, Cinder CSI, and Manila/NFS CSI when available.
14. Install Argo CD and make it the in-cluster source of truth.
15. Add ingress/cert-manager, observability and security stacks.
16. Add JupyterHub, resource profiles, shared storage and research images.
17. Add Ollama/llama.cpp.
18. Deploy Hermes last with narrowly scoped credentials.
