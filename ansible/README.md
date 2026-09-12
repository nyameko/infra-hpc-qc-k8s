# Ansible

Ansible owns **operating-system configuration, host services, security baselines, platform prerequisites, and infrastructure bootstrap** in `infra-hpc-qc-k8s`.

It takes the machines created by Terraform and turns them into usable infrastructure.

Ansible is deliberately not the long-lived Kubernetes application controller.

---

## Ansible's question

Ansible answers:

> **How should the machines be configured so the platform can operate?**

Terraform answers what machines/resources exist.

Argo CD answers what Kubernetes applications should remain running.

---

## Ownership boundary

```text
Terraform
    ↓
OpenStack VMs / networking

Ansible
    ↓
Rocky Linux
users / SSH / packages
firewall / services
containerd / bootstrap
HAProxy / edge / Slurm

kubeadm + Cilium
    ↓
Kubernetes substrate

Argo CD
    ↓
long-lived Kubernetes applications
```

This separation is one of the core design lessons of the repository.

---

## What Ansible owns

The Ansible layer currently covers several classes of infrastructure:

### Base hosts

```text
Rocky Linux configuration
users and groups
SSH configuration
packages
chrony / time-related prerequisites
host security
SELinux-aware service setup
```

### Edge / private access

```text
WireGuard
Pi-hole
nftables
Suricata
Wazuh components
```

### Kubernetes host preparation

```text
containerd
kernel/runtime prerequisites
Kubernetes packages
kubeadm bootstrap
control-plane joining
worker joining
Argo CD bootstrap
Sealed Secrets bootstrap
```

### External load balancing

```text
api-lb-01
HAProxy
Kubernetes API endpoint
Kubernetes application ingress
```

### HPC

```text
Slurm controller
Slurm login hosts
Slurm compute hosts
```

### Hermes hosts

Hermes infrastructure that intentionally runs outside Kubernetes may remain Ansible-managed.

---

## Repository structure

```text
ansible/
├── ansible.cfg
├── inventories/
│   ├── public / shared definitions
│   └── private/                 # environment-specific inventory
├── playbooks/
│   ├── bootstrap.yml
│   ├── edge.yml
│   ├── api_lb.yml
│   ├── kubernetes-prereqs.yml
│   ├── kubernetes.yml
│   ├── argocd.yml
│   ├── slurm.yml
│   └── hermes.yml
└── roles/
    ├── common/
    ├── admin_user/
    ├── ssh/
    ├── api_lb_haproxy/
    ├── edge/
    ├── wireguard/
    ├── pihole/
    ├── suricata/
    ├── wazuh_*/
    ├── containerd/
    ├── kubernetes_prereqs/
    ├── kube_control_plane/
    ├── kube_join_control_plane/
    ├── kube_worker/
    ├── slurm_*/
    └── hermes_orchestrator/
```

The exact inventory layout may vary by deployment, but the ownership model should remain stable.

---

## Inventory is the topology source

Inventory should describe **what hosts exist and what role they play**.

For example:

```text
k8s_control_plane
k8s_workers
api_lb
edge
slurm_controller
slurm_login
slurm_compute
hermes_orchestrator
```

That allows roles such as HAProxy to derive their backend topology from the same worker/control-plane data used to build the cluster.

This is especially important for scaling.

### Worker scaling principle

Do not hard-code:

```text
worker01
worker02
worker03
```

into operational templates when the inventory already knows how many workers exist.

Instead:

```text
Inventory
   ↓
worker topology
   ↓
Ansible variables
   ↓
HAProxy Jinja template
```

The current `api_lb_haproxy` role already follows the pattern of deriving API backends from inventory-backed data. The same pattern should be used for future Traefik HTTP/HTTPS worker backends.

---

## Canonical network variables

Keep network vocabulary consistent across roles:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr: 10.51.0.0/24
vpn_cidr: 10.60.0.0/24
```

Avoid introducing aliases such as `management_cidr` or `wireguard_cidr` when the repository already has canonical names.

---

## Bootstrap sequence

The intended bootstrap path is:

```text
OpenStack VM
    ↓
rocky bootstrap identity
    ↓
common / admin / security baseline
    ↓
containerd
    ↓
Kubernetes prerequisites
    ↓
kubeadm
    ↓
Cilium
    ↓
Argo CD
```

This is bootstrap automation, not the long-term controller for applications.

---

## `rocky` and `nyameko`

The bootstrap/recovery identity and the normal administrative identity have different purposes.

The reference environment retains `rocky` for image/bootstrap/recovery purposes while `nyameko` is the normal administrative identity.

Do not remove the recovery path until the private WireGuard path and alternative recovery path have been explicitly validated.

---

## Kubernetes administration boundary

Ansible may need an administrator kubeconfig during bootstrap, typically from the first control plane.

That does not mean Argo CD should receive the administrator kubeconfig.

The intended division is:

```text
Ansible
    ↓
bootstrap Kubernetes
    ↓
install Argo CD
    ↓
stop using Ansible as the application controller

Argo CD
    ↓
Kubernetes ServiceAccount + RBAC
    ↓
Kubernetes API
```

This keeps the powerful host/bootstrap credential separate from the day-2 GitOps controller identity.

---

## Argo CD bootstrap

The Argo role should remain intentionally small:

```text
verify kubeconfig / API access
        ↓
create argocd namespace
        ↓
install Argo CD
        ↓
wait for core components
```

After this point, application installation should normally migrate to Argo CD manifests and Helm values under `argocd/`.

---

## HAProxy

HAProxy is a good example of the Ansible boundary.

Terraform creates:

```text
api-lb-01
10.51.0.100
```

Ansible configures:

```text
HAProxy service
Kubernetes API backend pool
application ingress backend pools
```

Kubernetes creates:

```text
worker NodePorts
Traefik
Ingress routes
```

The layers therefore cooperate without co-owning each other.

For scalable ingress, derive HAProxy worker backends from the Kubernetes worker topology rather than manually duplicating IP lists.

---

## Pi-hole and private DNS

Pi-hole is intentionally host-level infrastructure on the edge node.

The useful distinction is:

```text
Public DNS
    ↓
Internet / Cloudflare

Private DNS
    ↓
Pi-hole on edge
    ↓
10.51.0.100 / internal services
```

The workstation's WireGuard interface may use split DNS so that only `~quantum.nyameko.com` is resolved by Pi-hole while ordinary Internet DNS remains unchanged.

---

## Secrets

Ansible must not become a plaintext secret distribution mechanism.

Kubernetes application secrets follow the Sealed Secrets workflow:

```text
operator workstation
       ↓
plaintext secret
       ↓
kubeseal
       ↓
SealedSecret in Git
       ↓
Argo CD
       ↓
Kubernetes Secret
```

Host-level secrets that cannot be represented this way belong in protected Ansible inventory/variable stores or an appropriate external secret system.

---

## What Ansible should not grow into

Avoid installing or permanently controlling large Kubernetes applications here merely because Ansible can run `helm` or `kubectl`.

Do not turn Ansible into the application owner for:

```text
Cinder CSI
Prometheus
Grafana
Traefik applications
cert-manager applications
JupyterHub
Astro
research applications
```

Once Argo CD owns those resources, use GitOps.

---

## Validation philosophy

Ansible should establish capabilities and validate them immediately.

Preferred pattern:

```text
configure
   ↓
verify
   ↓
record/diagnose
   ↓
continue
```

Examples include:

- validate that HAProxy configuration parses before reload
- validate service state after configuration
- validate Kubernetes API reachability after bootstrap
- validate containerd/CRI before kubeadm
- validate DNS and WireGuard reachability after edge configuration
- validate Cilium after bootstrap

The project should prefer failures near the layer that introduced them rather than allowing a later application deployment to expose a week-old host configuration error.

---

## Portability

Keep the Ansible roles as provider-neutral as practical.

Provider-specific assumptions should live at the inventory/environment boundary rather than appearing throughout every role.

That allows the same host/bootstrap logic to survive a change from OpenStack VMs to bare metal or another cloud.

---

## Related documentation

- [Project README](../README.md)
- [Terraform](../terraform/README.md)
- [Argo CD](../argocd/README.md)
- [Documentation](../docs/README.md)
