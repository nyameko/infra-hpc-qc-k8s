# Installation and Teaching Guide

## 1. What is being built?

The initial environment contains:

```text
OpenStack project
|
+-- Management network: 10.50.0.0/24
|
+-- Kubernetes network: 10.51.0.0/24
|
+-- WireGuard VPN: 10.60.0.0/24
|
+-- edge
|    +-- Wazuh manager
|    +-- WireGuard
|    +-- Pi-hole
|    +-- nftables
|    +-- Suricata IDS
|
+-- api-lb-01
|    +-- HAProxy
|
+-- Slurm
|    +-- controller
|    +-- login1
|    +-- login2
|    +-- compute
|
+-- Kubernetes
     +-- 3 control planes
     +-- 3 workers
```

The architecture deliberately separates infrastructure creation from machine configuration and application deployment.

---

## 2. Design boundaries

```text
Terraform
    |
    +--> OpenStack infrastructure

Ansible
    |
    +--> operating systems and infrastructure services

kubeadm
    |
    +--> Kubernetes cluster

Argo CD
    |
    +--> Kubernetes applications
```

Terraform should not install operating-system packages.

Ansible should not replace the Kubernetes application deployment layer.

Argo CD should become the normal GitOps path for Kubernetes applications.

---

## 3. Terraform

Terraform creates:

- networks
- subnets
- router
- security groups
- ports
- floating IP
- virtual machines
- API load-balancer infrastructure
- persistent OpenStack storage where appropriate

Reference:

- https://developer.hashicorp.com/terraform/docs

---

## 4. Ansible

Ansible configures:

- Rocky Linux
- base packages
- timezone
- chrony
- SSH
- `nyameko`
- nftables
- WireGuard
- Pi-hole
- Wazuh
- Suricata
- HAProxy
- Slurm
- Kubernetes prerequisites

Reference:

- https://docs.ansible.com/

---

## 5. Network model

### Management

```text
10.50.0.0/24
```

Used for infrastructure management and internal services.

### Kubernetes

```text
10.51.0.0/24
```

Used for the Kubernetes nodes and API load balancer.

### VPN

```text
10.60.0.0/24
```

Used by WireGuard clients.

Canonical names:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr: 10.51.0.0/24
vpn_cidr: 10.60.0.0/24
```

Avoid alternate names such as `management_cidr` and `wireguard_cidr`.

---

## 6. Inventory and variables

Ansible variables are read from inventory and variable files during playbook evaluation.

Check what Ansible actually sees:

```bash
ansible-inventory   -i inventories/private/hosts.yml   --host edge
```

Search the repository for naming drift:

```bash
rg -n 'management_cidr|wireguard_cidr|mgmt_cidr|vpn_cidr|k8s_cidr' ansible/
```

The target state is:

```text
management_cidr -> zero active references
wireguard_cidr  -> zero active references
mgmt_cidr       -> intentional
vpn_cidr        -> intentional
k8s_cidr        -> intentional
```

Normal `group_vars/*.yml` changes do not require a cache flush.

If fact or inventory caching is configured, `--flush-cache` can clear it:

```bash
ansible-playbook   -i inventories/private/hosts.yml   playbooks/bootstrap.yml   --flush-cache
```

The authoritative diagnostic remains `ansible-inventory`.

---

## 7. OpenStack credentials

Verify OpenStack access:

```bash
openstack token issue
openstack network list
openstack image list
openstack flavor list
```

Keep OpenStack credentials outside Git.

Reference:

- https://docs.openstack.org/

---

## 8. SSH identities

Two identities are deliberately used.

### Bootstrap/recovery

```text
rocky
```

Uses the OpenStack-injected bootstrap key.

### Normal administration

```text
nyameko
```

Uses a separate administrative SSH key installed by Ansible.

The bootstrap identity should remain available until recovery has been tested.

Normal private-node access is through `edge` with `ProxyJump`.

---

## 9. Time

All hosts use:

```text
Africa/Johannesburg
```

The timezone controls local presentation; chrony synchronizes the actual system clock.

Verify:

```bash
ansible all -m command   -a 'timedatectl show -p Timezone --value'
```

Verify synchronization:

```bash
ansible all -m command   -a 'chronyc tracking'
```

A healthy node should report:

```text
Leap status : Normal
```

Reference:

- https://chrony-project.org/documentation.html

---

## 10. Edge

The edge node is:

```text
10.50.0.10
```

Responsibilities:

```text
edge
├── nftables
├── WireGuard
├── Pi-hole
├── Wazuh manager
└── Suricata IDS
```

It is the controlled entry point into the private infrastructure.

---

## 11. nftables

OpenStack security groups provide the cloud-level network boundary.

nftables provides host-level filtering.

The intended baseline is:

```text
input   -> drop
forward -> drop
output  -> accept
```

with explicit rules for required traffic.

Stateful filtering uses conntrack:

```nft
ct state established,related accept
```

WireGuard client Internet access uses masquerading:

```text
10.60.0.0/24
      |
      v
     wg0
      |
      v
    edge
      |
 masquerade
      |
      v
external network
```

Validate before applying a new ruleset:

```bash
sudo nft -c -f /etc/nftables.conf
```

Reference:

- https://wiki.nftables.org/

---

## 12. WireGuard

The server runs on edge:

```text
10.60.0.1/24
```

The server private key is generated on edge and does not need to leave the host.

The public key is safe to distribute to clients.

A client may use:

```text
10.60.0.2/32
```

The client private key remains on the client.

Reference:

- https://www.wireguard.com/

---

## 13. Pi-hole

Pi-hole runs on edge because DNS is infrastructure.

```text
VM / Pod
   |
   v
CoreDNS
   |
   v
10.50.0.10:53
   |
   v
Pi-hole
   |
   v
upstream DNS
```

It provides DNS resolution, filtering and internal infrastructure records.

Initial persistent state is on edge. Later the storage can be moved to persistent Cinder-backed storage.

Reference:

- https://docs.pi-hole.net/

---

## 14. Wazuh

The initial design is:

```text
other hosts
    |
    v
Wazuh agents
    |
    v
edge / Wazuh manager
```

The indexer and dashboard are later deployed in Kubernetes:

```text
Wazuh manager
      |
      v
Wazuh indexer
      |
      v
Wazuh dashboard
```

The manager can collect and process agent events without the indexer/dashboard being immediately present.

Reference:

- https://documentation.wazuh.com/

---

## 15. HAProxy

The Kubernetes API endpoint is:

```text
10.51.0.100:6443
```

HAProxy forwards to:

```text
10.51.0.11:6443
10.51.0.12:6443
10.51.0.13:6443
```

```text
             10.51.0.100:6443
                    |
                 HAProxy
               /    |                  /     |                 CP1    CP2    CP3
```

The implementation is replaceable:

```text
api_lb_type = haproxy
```

can later become an Octavia implementation without changing the Kubernetes endpoint.

Reference:

- https://www.haproxy.org/

---

## 16. Kubernetes prerequisites

The Kubernetes nodes are:

```text
k8s-cp-01
k8s-cp-02
k8s-cp-03

k8s-worker-01
k8s-worker-02
k8s-worker-03
```

Install:

- containerd
- kubelet
- kubeadm
- kubectl
- required kernel modules
- sysctl configuration

containerd should use the systemd cgroup driver.

Reference:

- https://kubernetes.io/docs/setup/production-environment/container-runtimes/

---

## 17. Kubernetes bootstrap

The API endpoint remains:

```text
10.51.0.100:6443
```

Bootstrap:

```text
CP1
 |
 +-- kubeadm init
 |
 +--> CP2
 +--> CP3
 |
 +--> workers
```

Run:

```bash
ansible-playbook   -i inventories/private/hosts.yml   playbooks/kubernetes.yml
```

Reference:

- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/

---

## 18. Cilium

Cilium provides:

- pod networking
- service networking
- NetworkPolicy
- network observability

Validate:

```bash
kubectl get nodes
cilium status
```

All six nodes should eventually report `Ready`.

Reference:

- https://docs.cilium.io/en/latest/installation/k8s-install-kubeadm/

---

## 19. OpenStack integration and storage

Add OpenStack integration after the cluster is healthy.

Important components include:

```text
OpenStack Cloud Controller Manager
Cinder CSI
```

The persistent-storage model is:

```text
Application
    |
    v
PVC
    |
    v
CSI
    |
    v
Cinder
```

Persistent storage is planned for:

- Wazuh indexer
- Grafana
- PostgreSQL
- Jupyter data
- user data
- application state

References:

- https://docs.openstack.org/cinder/latest/
- https://kubernetes.io/docs/concepts/storage/

---

## 20. Argo CD

Argo CD becomes the Kubernetes application deployment layer:

```text
Git
 |
 v
Argo CD
 |
 v
Kubernetes
```

Applications include:

- Wazuh indexer
- Wazuh dashboard
- Prometheus
- Grafana
- ingress
- cert-manager
- JupyterHub
- Astro
- research services

Reference:

- https://argo-cd.readthedocs.io/

---

## 21. Slurm

Slurm remains the HPC scheduler.

```text
slurm-controller
     |
     +-- login1
     +-- login2
     |
     +-- slurm-cpu-01
     +-- slurm-cpu-02
```

Kubernetes and Slurm are complementary:

```text
Kubernetes
  -> services, notebooks, APIs, long-running workloads

Slurm
  -> HPC batch jobs, MPI and scientific workloads
```

Reference:

- https://slurm.schedmd.com/

---

## 22. Wazuh indexer and dashboard in Kubernetes

The intended architecture is:

```text
Agents
   |
   v
Wazuh manager
   |
   v
Wazuh indexer
   |
   v
Wazuh dashboard
```

The indexer requires persistent storage.

The dashboard provides the web interface.

Wazuh documents the server, indexer and dashboard as separate components.

Reference:

- https://documentation.wazuh.com/current/getting-started/architecture.html

---

## 23. Observability

The platform will provide:

```text
Prometheus
Grafana
Loki
```

for:

- node metrics
- Kubernetes metrics
- Slurm metrics
- application metrics
- workload telemetry
- Hermes telemetry

Reference:

- https://prometheus.io/docs/
- https://grafana.com/docs/

---

## 24. JupyterHub

The user-facing research interface is:

```text
Browser
   |
   v
Ingress
   |
   v
JupyterHub
   |
   v
JupyterLab
```

Research environments can later include:

```text
PennyLane
Qiskit
Qiskit Aer
CUDA Quantum
PyTorch
custom images
```

Resource selection can eventually include:

```text
CPU
RAM
GPU
persistent storage
```

Reference:

- https://jupyterhub.readthedocs.io/

---

## 25. Astro

Initial public application:

```text
quantum.nyameko.com
```

Architecture:

```text
Cloudflare
    |
    v
Ingress
    |
    v
Astro service
    |
    v
Astro container
```

The first goal is a simple hello page to verify DNS, ingress and application deployment end-to-end.

Reference:

- https://docs.astro.build/

---

## 26. PostgreSQL

PostgreSQL is a later persistent application service.

Planned uses include:

- user information
- research portal data
- JupyterHub state
- application metadata

Storage:

```text
PostgreSQL
    |
    v
PVC
    |
    v
Cinder
```

Reference:

- https://www.postgresql.org/docs/

---

## 27. Hermes

The initial infrastructure Hermes agent runs outside Kubernetes:

```text
hermes-orchestrator-01
```

A research Hermes agent later runs inside Kubernetes.

Long-term:

```text
Personal Hermes
      |
      +-- Infrastructure Hermes
      +-- Research Hermes
      +-- future environment agents
```

Hermes should operate with explicit capabilities and least privilege.

---

## 28. Cloudflare

The initial public hostname is:

```text
quantum.nyameko.com
```

Future hostnames may include:

```text
research.nyameko.com
blog.nyameko.com
shop.nyameko.com
```

The public domain remains:

```text
nyameko.com
```

Reference:

- https://developers.cloudflare.com/

---

## 29. Complete deployment order

```text
OpenStack authentication
        |
        v
Terraform
        |
        v
OpenStack infrastructure
        |
        v
Ansible bootstrap
        |
        +-- time
        +-- SSH
        +-- nyameko
        +-- Wazuh agents
        |
        v
Edge
        |
        +-- nftables
        +-- WireGuard
        +-- Pi-hole
        +-- Wazuh manager
        +-- Suricata
        |
        v
HAProxy
        |
        v
Kubernetes
        |
        +-- kubeadm
        +-- Cilium
        +-- OpenStack CCM
        +-- Cinder CSI
        |
        v
Argo CD
        |
        +-- Wazuh indexer/dashboard
        +-- Prometheus/Grafana
        +-- ingress
        +-- JupyterHub
        +-- Astro
        |
        v
Hermes research services
```

Slurm can be configured independently after the base operating-system layer.

---

## 30. Validation philosophy

Every phase has a verification step.

Examples:

```bash
terraform validate
terraform plan
ansible all -m ping
chronyc tracking
timedatectl
wg show
nft list ruleset
systemctl status haproxy
kubectl get nodes
cilium status
kubectl get storageclass
```

A successful provisioning command is not itself proof that the service works.

The goal is a reproducible platform in which every layer has a clear owner, purpose and acceptance test.
