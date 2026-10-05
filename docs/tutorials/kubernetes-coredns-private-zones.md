# Kubernetes CoreDNS private-zone forwarding

CoreDNS is managed after kubeadm bootstrap by the `kubernetes_coredns` Ansible
role. Do not hand-edit the live `kube-system/coredns` ConfigMap as an operating
procedure.

The current M3c requirement is:

```text
Kubernetes Pod
      ↓
CoreDNS 10.96.0.10
      ↓  *.internal
Pi-hole on edge
      ↓
slurm-login.internal → login1/login2 service endpoint
```

The playbook derives Pi-hole's address from the existing `edge` inventory host:

```yaml
kubernetes_coredns_private_zones:
  - zone: internal
    forwarders:
      - "{{ hostvars['edge'].ansible_host }}"
```

Run from blackmyth:

```bash
cd ~/Projects/infra-hpc-qc-k8s/ansible

ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-dns.yml
```

The role:

1. renders a complete managed CoreDNS ConfigMap on `k8s-cp-01`;
2. runs `kubectl diff` against the live cluster;
3. applies only when drift exists;
4. restarts CoreDNS only after a configuration change;
5. waits for the rollout to complete.

Acceptance from `k8s-cp-01`:

```bash
kubectl -n quantum-platform exec -i \
  deploy/quantum-platform-user-api -- \
  python - <<'PY'
import socket
print(socket.gethostbyname("slurm-login.internal"))
PY
```

Expected:

```text
10.50.0.20
```

Then validate TCP/22 separately. DNS success does not prove that the OpenStack
security-group/routing path to the Slurm login tier is open.
