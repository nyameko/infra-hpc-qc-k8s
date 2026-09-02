# Tutorial 3 — Deployment with Terraform and Ansible

## 1. Purpose

This tutorial converts the design into a repeatable deployment.

The core operating model is:

```text
Terraform → provision OpenStack
Ansible   → configure Linux and services
kubeadm   → bootstrap Kubernetes
Argo CD   → deliver applications
```

The project deliberately uses two Kubernetes playbooks rather than a large collection of tiny wrappers:

```text
ansible/playbooks/
├── kubernetes-prereqs.yml
└── kubernetes.yml
```

---

## 2. Workstation preparation

The working machine is Arch Linux.

Verify:

```bash
terraform version
ansible --version
openstack --version
kubectl version --client
helm version
```

The deployment should be performed from a known Git revision and should keep private inventory and credentials out of the public repository.

---

## 3. OpenStack authentication

Use `clouds.yaml` or environment variables.

Never commit cloud credentials or private environment values.

Validate authentication before provisioning:

```bash
openstack token issue
openstack network list
openstack image list
openstack flavor list
```

The project repeatedly benefited from this basic check during troubleshooting.

---

## 4. Terraform workflow

The intended workflow is:

```bash
cd terraform/environments/personal
terraform init
terraform validate
terraform plan
terraform apply
```

The Makefile wraps these operations where appropriate.

The current infrastructure model includes the Kubernetes API load-balancer VM as well as the 13 other service/compute VMs. The older teaching documents were inconsistent about this; the current topology should always show `api-lb-01` explicitly.

---

## 5. OpenStack flavor failure

An early Terraform error reported a flavor as unavailable even though the flavor was visible in:

```bash
openstack flavor list
```

The cause was a mismatch between a human-readable flavor name and the field where the provider expected the flavor ID.

The lesson is:

```text
OpenStack flavor name ≠ flavor ID
```

A failed lookup should therefore not automatically be interpreted as a quota problem.

The repository history preserves the explicit flavor-ID fix. citeturn154630view0

---

## 6. Ansible inventory is authoritative

The actual inventory groups are:

```text
edge_nodes
hermes_orchestrator
slurm_controller
slurm_login
slurm_compute
api_lb
control_plane
workers
```

Always inspect the inventory rather than guessing:

```bash
ansible-inventory \
  -i inventories/private/hosts.yml \
  --graph
```

For a particular host:

```bash
ansible-inventory \
  -i inventories/private/hosts.yml \
  --host edge
```

This prevented mistaken group names during Kubernetes automation.

---

## 7. Private variables and variable scope

Environment-specific values live in:

```text
ansible/inventories/private/group_vars/
```

The public repository contains reusable defaults/templates rather than the authority for a particular deployment.

This decision emerged from real variable-scope failures: values such as the timezone and network CIDRs were not always being resolved where expected until the private inventory was made authoritative.

Use:

```bash
ansible-inventory -i inventories/private/hosts.yml --host edge
```

to confirm what Ansible actually sees.

A YAML file on disk is not the same thing as a value that Ansible has resolved for the host.

---

## 8. Timezone and time synchronisation

Timezone and clock synchronisation are separate concerns.

The environment uses:

```text
Africa/Johannesburg
```

Chrony synchronises the actual clock underneath it.

Validate both:

```bash
ansible all -m command -a 'timedatectl show -p Timezone --value'
ansible all -m command -a 'chronyc tracking'
```

An early timezone failure was caused by variable placement rather than a broken timezone role. The final fix was to place the value in private group variables instead of hardcoding service configuration into the role.

---

## 9. Base operating-system deployment

The common/base layer establishes:

- packages
- time synchronisation
- timezone
- SSH hardening
- `nyameko` administrator
- Wazuh targeting/agent configuration

The bootstrap identity remains available for recovery until the private access path is proven.

---

## 10. Edge deployment iterations

### WireGuard

The server private key was generated locally on `edge` and left there.

Only public-key material is exchanged.

A handler naming mismatch was corrected so the `wg-quick@wg0` service is restarted correctly.

### Pi-hole

The Podman Quadlet image was changed from the ambiguous short name to:

```text
docker.io/pihole/pihole:latest
```

### Wazuh

A stale/broken repository was removed and the 4.x repository was corrected.

### Suricata

EPEL/CRB/OISF packaging was added and the first deployment stays IDS-only.

The repository history contains these separate corrective iterations and is useful evidence of why the final roles look the way they do. citeturn154630view0

---

## 11. HAProxy deployment

The API load balancer is:

```text
api-lb-01
10.51.0.100
```

Backends:

```text
10.51.0.11:6443
10.51.0.12:6443
10.51.0.13:6443
```

The first service deployment exposed a useful distinction:

```text
haproxy -c → valid
systemctl start → failed
```

The cause was SELinux denying the bind.

The final role sets:

```text
haproxy_connect_any = on
```

persistently through Ansible.

---

## 12. Kubernetes prerequisites: containerd failure and correction

The first prerequisite implementation tried to install:

```yaml
- containerd
```

from Rocky's regular repositories.

The result was:

```text
No package containerd available.
```

The correction was to isolate runtime ownership in the dedicated `containerd` role and install:

```text
containerd.io
```

from Docker's EL9 repository.

The containerd role now owns:

```text
repository
package
config.toml
SystemdCgroup
service
```

The Kubernetes prerequisite role owns Kubernetes-specific host state.

This separation was captured in the repository's refinement commit. citeturn154630view0

---

## 13. Kubernetes prerequisite result

The final prerequisite pipeline configures all six Kubernetes nodes with:

```text
overlay
br_netfilter
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

and installs:

```text
kubelet
kubeadm
kubectl
cri-tools
```

with:

```text
containerd://2.3.4
Kubernetes v1.36.4
```

The containerd release and Kubernetes version were verified across all nodes.

---

## 14. CRI configuration

`crictl` is pointed at:

```yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
```

The `kube_prereqs` role validates CRI as root.

A separate ad-hoc test initially failed with `permission denied` because it ran as the normal `nyameko` user. Re-running with `sudo` returned `CRI_OK` on all six nodes.

This is a useful distinction:

```text
CRI transport works
    ↓
Unix socket permissions matter
```

The repository history captures the addition of `crictl` as an explicit prerequisite. citeturn409697view6turn154630view5

---

## 15. Kubernetes repository and package version

The Kubernetes packages come from the modern per-minor repository:

```text
https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
```

The deployed version is:

```text
v1.36.4
```

Do not carry unused duplicate version variables. Only keep variables that actually control repository/bootstrap behavior.

---

## 16. kubeadm automation architecture

The actual cluster bootstrap uses Ansible to orchestrate kubeadm.

The playbooks are intentionally:

```text
kubernetes-prereqs.yml
kubernetes.yml
```

and the roles divide responsibilities:

```text
containerd
kube_prereqs
kube_control_plane
kube_control_plane_join
kube_worker_join
```

A redundant `join-cluster.yml` playbook was removed during the naming refactor.

That commit is a good example of the repository being simplified as its architecture became clearer. citeturn154630view6

---

## 17. kubeadm configuration

The cluster bootstrap values are:

```text
Kubernetes version: 1.36.4
Control-plane endpoint: 10.51.0.100:6443
CP1 advertise address: 10.51.0.11
Pod CIDR: 10.244.0.0/16
Service CIDR: 10.96.0.0/12
CRI socket: unix:///run/containerd/containerd.sock
```

The important point is that control-plane clients use:

```text
10.51.0.100
```

rather than hardcoding CP1.

---

## 18. The first kubeadm run was manual — then codified

The first CP1 initialization was deliberately performed manually while debugging the infrastructure boundary.

It succeeded.

The API server reported healthy.

However, `kubectl` through the VIP timed out.

That exposed the API load-balancer security-group problem described in Tutorial 2.

Once the VIP was working, the remaining control-plane and worker joins were moved into Ansible.

This is an important engineering lesson:

> A manual command used to isolate a failing layer is acceptable during diagnosis; leaving a production bootstrap manual is not.

---

## 19. Temporary kubeadm bootstrap credentials

The control-plane role generates temporary:

```text
token
CA discovery hash
control-plane certificate key
```

They are not persisted into Git, Vault, Terraform state or private inventory.

The CA hash is derived from the cluster CA certificate.

The bootstrap token can be generated again.

The control-plane certificate secret uploaded by `--upload-certs` is temporary and can be re-created when necessary.

Worker join:

```text
kubeadm join 10.51.0.100:6443 \
  --token ... \
  --discovery-token-ca-cert-hash sha256:...
```

Control-plane join:

```text
kubeadm join 10.51.0.100:6443 \
  --token ... \
  --discovery-token-ca-cert-hash sha256:... \
  --control-plane \
  --certificate-key ...
```

The join-role variable reference bugs discovered during implementation were fixed before the successful automated run. citeturn154630view3

---

## 20. Idempotence

CP1 checks for:

```text
/etc/kubernetes/admin.conf
```

before running `kubeadm init`.

Already joined nodes are guarded by Kubernetes node state such as:

```text
/etc/kubernetes/kubelet.conf
```

This means the orchestration can be rerun without reinitialising an existing control plane or rejoining an existing node.

A perfect host-state convergence run should eventually report `changed=0` for already-established prerequisites.

Temporary bootstrap credential generation is runtime state rather than persistent infrastructure drift.

---

## 21. Full Kubernetes automation result

The automated cluster deployment successfully produced:

```text
k8s-cp-01       control-plane
k8s-cp-02       control-plane
k8s-cp-03       control-plane
k8s-worker-01   worker
k8s-worker-02   worker
k8s-worker-03   worker
```

All report:

```text
v1.36.4
containerd://2.3.4
```

Three etcd members, three API servers, three controller managers and three schedulers run as expected.

---

## 22. Validation ladder

At every layer, validate behavior rather than trusting a successful command.

### Terraform

```bash
terraform validate
terraform plan
```

### OpenStack

```bash
openstack server list
openstack port list
openstack security group list
```

### Ansible inventory

```bash
ansible-inventory -i inventories/private/hosts.yml --graph
```

### Host services

```bash
systemctl is-active containerd
systemctl is-active kubelet
```

### CRI

```bash
sudo crictl info
```

### API load balancer

```bash
sudo systemctl is-active haproxy
sudo ss -ltnp | grep ':6443'
```

### Kubernetes API

```bash
kubectl cluster-info
kubectl get --raw='/readyz?verbose'
```

### Nodes and system pods

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

---

## 23. What comes after the host/bootstrap layer

Once Kubernetes is assembled:

```text
Cilium
   ↓
Cinder CSI / OpenStack cloud integration
   ↓
Argo CD
   ↓
Prometheus / Grafana
   ↓
Slurm integration
   ↓
Hermes
   ↓
JupyterHub
   ↓
Astro
```

Applications are not rebuilt through Terraform or kubeadm.

They are higher-level platform state and will ultimately be managed by GitOps.

---

## References

- Terraform OpenStack provider: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs
- Terraform style guide: https://developer.hashicorp.com/terraform/language/style
- Ansible roles: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html
- OpenStackClient: https://docs.openstack.org/python-openstackclient/latest/
- Kubernetes kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- Kubernetes CRI runtimes: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- Kubernetes HA: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
