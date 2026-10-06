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

The private resolver address is protected environment state. Keep it in the
inventory-owned `group_vars/all/` directory rather than passing it with
`-e` or deriving it indirectly from another hostname:

```text
ansible/inventories/private/
├── hosts.yml
└── group_vars/
    └── all/
        ├── site.yml
        └── research-users.yml
```

For the current environment, `site.yml` contains the private resolver list:

```yaml
kubernetes_coredns_internal_forwarders:
  - <PIHOLE_MANAGEMENT_IP>
```

The public playbook converts that protected value into the managed private
zone:

```yaml
kubernetes_coredns_private_zones:
  - zone: internal
    forwarders: "{{ kubernetes_coredns_internal_forwarders }}"
```

Do not mix `group_vars/all.yml` with a `group_vars/all/` directory in the
private inventory. Use the directory form consistently so site settings and
research-user state are auto-loaded together.

Validate auto-loading before applying:

```bash
cd ~/Projects/infra-hpc-qc-k8s/ansible

ansible-inventory \
  -i inventories/private/hosts.yml \
  --host k8s-cp-01 |
jq '.kubernetes_coredns_internal_forwarders'
```

The result must be the protected resolver list, not `null`. No
`-e @inventories/private/...` override should be required.

Then reconcile:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-dns.yml
```

A second run with no configuration drift should be idempotent: validation,
template rendering and diff succeed, while apply/restart/rollout tasks are
skipped.

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


## M3 bring-up note

During M3c, the private-zone design was first proven with a one-off live
`kubectl edit configmap coredns`. That was a diagnostic experiment, not the
operating procedure. Once the Ansible role and protected inventory were
correct, the live ConfigMap matched the rendered desired state and subsequent
playbook runs became idempotent.

Do not intentionally remove a known-good live DNS block just to demonstrate
that Ansible can recreate it. Treat the repository plus protected inventory as
the desired-state authority and let normal drift/rebuild events exercise the
reconciliation path.
