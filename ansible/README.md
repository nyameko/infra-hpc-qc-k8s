# Ansible

Ansible owns **host configuration, operating-system configuration, security baselines, base services, and Kubernetes bootstrap prerequisites** in `infra-hpc-qc-k8s`.

It is not the long-term Kubernetes application controller. After Kubernetes and Argo CD are established, Kubernetes applications should normally be delivered through Argo CD.

## Responsibility boundary

```text
Terraform
    ↓
creates cloud resources / VMs

Ansible
    ↓
configures the machines
    ├── Rocky Linux
    ├── users / SSH
    ├── firewall / host security
    ├── edge services
    ├── containerd
    ├── Kubernetes prerequisites
    ├── kubeadm bootstrap / joining
    └── Argo CD bootstrap

Argo CD
    ↓
manages long-lived Kubernetes applications
```

Slurm is an intentional Ansible-managed exception because it runs directly on dedicated VMs outside Kubernetes.

## Directory structure

```text
ansible/
├── ansible.cfg
├── inventories/
│   └── private/             # environment-specific inventory; do not publish secrets
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
    ├── admin_user/
    ├── api_lb_haproxy/
    ├── common/
    ├── containerd/
    ├── edge/
    ├── hermes_orchestrator/
    ├── kube_control_plane/
    ├── kube_join_control_plane/
    ├── kube_worker/
    ├── kubernetes_prereqs/
    ├── pihole/
    ├── slurm_compute/
    ├── slurm_controller/
    ├── slurm_login/
    ├── ssh/
    ├── suricata/
    ├── wazuh_agent/
    ├── wazuh_manager/
    └── wireguard/
```

The repository currently exposes separate playbooks for API load balancing, edge services, Kubernetes prerequisites/bootstrap, Slurm and Hermes. citeturn697765view1turn697765view0

## Inventory and variables

Public code should remain generic. Environment-specific values belong in the private inventory.

Important canonical variables include:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr: 10.51.0.0/24
vpn_cidr: 10.60.0.0/24
```

The reference environment uses `private/group_vars/all.yml` for values that must not be committed publicly.

## Bootstrap model

The normal sequence is:

```text
OpenStack VM
    ↓
rocky bootstrap identity
    ↓
Ansible common/admin/security configuration
    ↓
containerd
    ↓
Kubernetes prerequisites
    ↓
kubeadm
    ↓
Cilium
    ↓
Argo CD bootstrap
```

`rocky` remains useful for bootstrap/recovery; `nyameko` is the normal administrator identity. Public SSH should only be removed after the private recovery path has been fully proven.

## Kubernetes administration host

`k8s-cp-01` is used as the temporary execution point for cluster bootstrap operations that need the cluster administrator kubeconfig.

The important distinction is that this is **not** a permanent Ansible-to-Kubernetes application-control pattern. Ansible uses the control plane to bootstrap Argo CD; Argo CD then uses its own in-cluster ServiceAccount/RBAC to manage Kubernetes resources.

## Argo CD bootstrap

The Argo CD role is deliberately small:

```text
verify existing kubeconfig
verify kubectl/API access
create argocd namespace
install Argo CD
wait for core components
```

The standard Argo installation is intentionally used for an in-cluster deployment. Argo's application controller is a StatefulSet in the current installation model. citeturn523162search1turn883343search0

The role does not need to copy the administrator kubeconfig into Argo. The kubeconfig is only an Ansible/bootstrap credential.

## Slurm

Slurm remains Ansible-managed because it is outside Kubernetes:

```text
slurm-controller-01
login1 / login2
slurm-cpu-01 / slurm-cpu-02
```

The Slurm playbook can be run independently once the VMs exist. It should be operational before Hermes/JupyterHub begin depending on HPC execution.

## What Ansible should not grow into

Avoid adding large application installers here for:

```text
Cinder CSI
Prometheus
Grafana
JupyterHub
Astro
research services
```

Those belong under `argocd/` once the GitOps boundary is established.

The goal is to keep playbooks understandable:

```text
Terraform → cloud
Ansible   → hosts
Argo CD   → Kubernetes applications
Slurm     → HPC scheduling
```

## Validation philosophy

Ansible tasks should validate the capability they establish. Examples from the project include service health checks, CRI checks, API endpoint readiness, HAProxy verification, and Cilium validation.

The preferred pattern is:

```text
configure → verify → move on
```

rather than allowing later application failures to expose an earlier host-level problem.

## Portability

The Ansible layer should remain as provider-neutral as possible. Host configuration and Kubernetes bootstrap concepts should survive changes in cloud provider or hardware.

Provider-specific assumptions belong at the infrastructure/inventory boundary, not throughout every role.
