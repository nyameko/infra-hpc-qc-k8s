# Quick Guide

> **Zero-to-hero:** OpenStack project → VMs → hardened hosts → Kubernetes → Cilium → platform applications.
>
> Minimal prose. Read [INSTALLATION.md](INSTALLATION.md) for explanations, warnings, comparisons and troubleshooting.

---

## 0. Workstation

```bash
git clone https://github.com/nyameko/infra-hpc-qc-k8s.git
cd infra-hpc-qc-k8s

sudo pacman -Syu ansible terraform python-openstackclient git
```

Verify:

```bash
terraform version
ansible --version
openstack --version
```

---

## 1. OpenStack credentials

Configure your OpenStack credentials **outside Git**.

```bash
openstack token issue
openstack network list
openstack image list
openstack flavor list
```

---

## 2. Private environment

Populate the private environment files required by this deployment.

Typical structure:

```text
ansible/inventories/private/
├── hosts.yml
└── group_vars/
    └── all.yml
```

Confirm inventory resolution:

```bash
cd ansible
ansible-inventory -i inventories/private/hosts.yml --graph
ansible-inventory -i inventories/private/hosts.yml --host edge
```

---

## 3. OpenStack infrastructure

```bash
cd ../terraform/environments/private
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Verify:

```bash
openstack server list
openstack network list
openstack security group list
```

---

## 4. Bootstrap and base hosts

```bash
cd ../../../ansible
ansible all -i inventories/private/hosts.yml -m ping

ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/bootstrap.yml
```

Verify:

```bash
ansible all -i inventories/private/hosts.yml -m command \
  -a 'hostnamectl --static'

ansible all -i inventories/private/hosts.yml -m command \
  -a 'timedatectl show -p Timezone --value'

ansible all -i inventories/private/hosts.yml -b -m command \
  -a 'chronyc tracking'
```

---

## 5. Edge

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/edge.yml
```

Verify:

```bash
ansible edge_nodes -i inventories/private/hosts.yml -b -m shell -a \
  'systemctl is-active nftables; systemctl is-active wg-quick@wg0; systemctl is-active pihole-FTL; systemctl is-active suricata'

ssh edge
sudo nft list ruleset
sudo wg show
```

---

## 6. Kubernetes API load balancer

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/api_lb.yml
```

Verify:

```bash
ssh api-lb-01
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl is-active haproxy
sudo ss -lntp | grep 6443
```

Before Kubernetes exists, HAProxy backends may be `DOWN`. That is expected.

---

## 7. Kubernetes prerequisites

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-prereqs.yml
```

Verify **as root** where required:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml -b -m shell -a \
  'systemctl is-active containerd; systemctl is-active kubelet; crictl info >/dev/null && echo CRI_OK'
```

Expected:

```text
active
active
CRI_OK
```

---

## 8. Kubernetes cluster

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes.yml
```

Configure `kubectl` from the bootstrap control plane as required by the role/workstation setup, then verify:

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

Before CNI, `CoreDNS` may be pending and nodes may not be `Ready`. After CNI is installed, all six nodes must become `Ready`.

---

## 9. Cilium

Install the pinned Cilium release used by the environment:

```bash
cilium install <version>
cilium status --wait
```

Verify:

```bash
kubectl get nodes
cilium status
cilium connectivity test --debug
```

Acceptance:

```text
6/6 Cilium agents healthy
6/6 nodes Ready
connectivity test successful
```

---

## 10. OpenStack integration

Next layers:

```text
OpenStack Cloud Controller Manager
Cinder CSI
```

Verify after deployment:

```bash
kubectl get pods -A
kubectl get storageclass
kubectl get csidrivers
```

---

## 11. Argo CD

Install Argo CD through the repository's Kubernetes/GitOps path.

Verify:

```bash
kubectl get pods -n argocd
kubectl get applications -A
```

---

## 12. Platform applications

Deploy in dependency order:

```text
Ingress
  ↓
cert-manager
  ↓
Prometheus / Grafana / Loki
  ↓
Wazuh indexer / dashboard
  ↓
PostgreSQL
  ↓
JupyterHub
  ↓
Astro
  ↓
Research Hermes
```

---

## 13. Slurm

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/slurm.yml
```

Verify:

```bash
sinfo
squeue
scontrol show nodes
```

---

## 14. End-to-end acceptance

```bash
terraform validate
ansible all -i ansible/inventories/private/hosts.yml -m ping

kubectl get nodes -o wide
kubectl get pods -A
cilium status
kubectl get storageclass

sinfo
```

Final application path:

```text
OpenStack
  → Rocky Linux
  → Ansible
  → kubeadm
  → Cilium
  → Cinder CSI
  → Argo CD
  → Ingress
  → Application
```

---

## Safety gates

**DO NOT** remove public SSH/22 until the final public-application milestone has been completed and the WireGuard/recovery path has been tested.

**DO NOT** commit:

```text
OpenStack credentials
private SSH keys
WireGuard private keys
Ansible secrets
kubeadm bootstrap credentials
TLS private keys
```

**DO NOT** skip validation between layers.

---

## Failure triage

```bash
# OpenStack
openstack server list
openstack port list
openstack security group rule list <group>

# Ansible
ansible-inventory -i inventories/private/hosts.yml --graph
ansible all -i inventories/private/hosts.yml -m ping

# Host
systemctl --failed
journalctl -u <service> -b

# Networking
ip addr
ip route
sudo nft list ruleset
sudo wg show

# Kubernetes
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp

# Runtime
sudo systemctl status containerd kubelet
sudo crictl info

# Cilium
cilium status
cilium-dbg status --verbose
cilium connectivity test --debug
```
