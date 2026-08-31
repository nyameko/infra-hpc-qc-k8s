# Installation & Testing Guide — `nyameko/infra-hpc-qc-k8s`

This is a phased runbook for deploying the repo end-to-end: 13 OpenStack VMs, base OS hardening, edge/security services, a Slurm cluster, and a kubeadm Kubernetes cluster.

**Before you start:** a prior audit of this repo (same-day, 2-commit snapshot as of 2026-08-28) found several bugs that block a clean run if you follow the README/Makefile literally. This guide includes the fix for each one, inline, at the phase where it first matters. They're also summarized here so you can patch everything up front if you prefer:

| # | Bug | Blocks | Fixed in |
|---|---|---|---|
| 1 | `providers.tf` duplicates `variable`/`provider` blocks already in `variables.tf`/`versions.tf` | `terraform init` | Phase 2 |
| 2 | `terraform.tfvars.example` uses stale variable names, missing 8 of 13 required vars | `terraform apply` | Phase 1 |
| 3 | `ansible.cfg` has no `roles_path`; roles live outside Ansible's default search path | every playbook | Phase 5 |
| 4 | `community.general` collection used but never declared as a dependency | bootstrap & k8s-prereqs playbooks | Phase 6 |
| 5 | Over-escaped regex in the swap-disable task destroys the original `/etc/fstab` line instead of commenting it out | data integrity on every host | Phase 6 |

Everything else in the repo (YAML, remaining HCL, shell scripts, inventory, join-token logic) checked out clean in static testing.

---

## Phase 0 — Local tooling & OpenStack credential verification

**Goal:** confirm your workstation and OpenStack account can actually do what the rest of this guide assumes, before touching Terraform.

### 0.1 Install local tooling

```bash
terraform version      # >= 1.9.0 (required_version in versions.tf)
ansible --version       # ansible-core, plus community.general (see Phase 6)
openstack --version
kubectl version --client
helm version
```

### 0.2 Configure OpenStack auth

Use a `clouds.yaml` (preferred) or `OS_*` environment variables. **Never** put credentials in a committed `terraform.tfvars` — the repo's `.gitignore` already excludes `*.tfvars`.

```bash
export OS_CLOUD=mycloud   # if using clouds.yaml
# or source an OpenRC file:
# source openrc.sh
```

### 0.3 Verify credentials actually work

```bash
# Depending on the OpenStack cloud.yaml files you downloaded from Sebowa 
openstack token issue

# Export the variables into your shell environment
# export OS_TOKEN=<id>
# export OS_AUTH_URL=<auth_url>
# export OS_PROJECT_ID=<project_id>

openstack quota show --compute

```

**Expected:** a valid token response and quota table. If this fails, nothing downstream will work — stop here and fix auth first.

#### Or better yet, add the temporary token=<id> to clouds.yaml

Comment out or remove username, project_name and user_domain_name, and make sure to add project_domain_name and auth_type.

```yaml
clouds:
  openstack:
    auth:
      auth_url: <url>
      token: <id>
      #username: "nlisa"
      project_id: <id>
      # project_name: "QC Simulator"
      # user_domain_name: "Default"
      project_domain_name: "Default"
    region_name: "RegionOne"
    interface: "public"
    identity_api_version: 3
    auth_type: v3token

```

### 0.4 Verify every resource the Terraform code references by name actually exists

The Terraform in this repo **does not create** an image, a keypair, or the external network — it only references them by name/ID. If any of these are missing, `terraform apply` will fail partway through (after some resources are already created).

```bash
# You may need to explicity 
export OS_CLIENT_CONFIG_FILE="$HOME/.config/openstack/clouds.yaml"
openstack --os-cloud infra-hpc-qc-debug server list

# External/public network (var.external_network_name)
openstack network list --external

# Installation & Architecture Guide — `infra-hpc-qc-k8s`

`infra-hpc-qc-k8s` is a reproducible infrastructure framework for building a small hybrid HPC, cloud, AI/ML and quantum-computing research platform on OpenStack.

The repository uses:

* Terraform for OpenStack infrastructure
* Ansible for operating-system configuration and services
* kubeadm for Kubernetes bootstrap
* Cilium for Kubernetes networking
* Cinder-backed persistent storage
* Argo CD for GitOps application deployment
* Slurm for HPC batch workloads
* HAProxy as the initial Kubernetes API load balancer
* Wazuh, Suricata, nftables and WireGuard for security
* Pi-hole for infrastructure DNS and filtering
* Prometheus/Grafana for observability
* JupyterHub/JupyterLab for interactive research environments
* Hermes for autonomous infrastructure orchestration
* Astro for web frontends and research portals

The platform is intentionally built in layers. Each layer should be verified before the next one is introduced.

---

# 1. Architecture

## 1.1 The initial OpenStack environment

The first environment contains:

```text
OpenStack Project
│
├── Management network
│   └── 10.50.0.0/24
│
├── Kubernetes network
│   └── 10.51.0.0/24
│
├── Router
│
├── edge
│   └── 10.50.0.10
│
├── hermes-orchestrator-01
│   └── 10.50.0.11
│
├── slurm-controller-01
│   └── 10.50.0.12
│
├── login1
│   └── 10.50.0.20
│
├── login2
│   └── 10.50.0.21
│
├── slurm-cpu-01
│   └── 10.50.0.30
│
├── slurm-cpu-02
│   └── 10.50.0.31
│
├── api-lb-01
│   └── 10.51.0.100
│
├── k8s-cp-01
│   └── 10.51.0.11
│
├── k8s-cp-02
│   └── 10.51.0.12
│
├── k8s-cp-03
│   └── 10.51.0.13
│
├── k8s-worker-01
│   └── 10.51.0.21
│
├── k8s-worker-02
│   └── 10.51.0.22
│
└── k8s-worker-03
    └── 10.51.0.23
```

The current Terraform configuration creates the normal infrastructure nodes through the generic `compute` module and creates the Kubernetes API load-balancer separately through the `api_lb` implementation module. The Kubernetes API endpoint is:

```text
10.51.0.100:6443
```

The current implementation is HAProxy; Octavia remains a replaceable future implementation.

---

# 2. Design principles

## 2.1 Terraform owns infrastructure

Terraform creates:

* OpenStack networks
* subnets
* router
* security groups
* ports
* floating IPs
* VM instances
* API load-balancer infrastructure
* persistent OpenStack storage where appropriate

Terraform should not configure operating-system services.

---

## 2.2 Ansible owns operating systems and services

Ansible configures:

* Rocky Linux
* system packages
* timezone
* chrony
* SSH
* administrative users
* nftables
* WireGuard
* Pi-hole
* Wazuh
* Suricata
* HAProxy
* Slurm
* Kubernetes prerequisites

---

## 2.3 Kubernetes owns applications

Once Kubernetes is running, applications should increasingly be deployed through GitOps:

```text
Git
 ↓
Argo CD
 ↓
Kubernetes
```

Applications include:

* Wazuh indexer
* Wazuh dashboard
* Prometheus
* Grafana
* Loki
* ingress
* cert-manager
* JupyterHub
* model-serving infrastructure
* Astro sites
* research services

---

# 3. Repository and environment model

The repository is intentionally environment-agnostic.

The same codebase is used for:

```text
personal
production
purple-1
purple-2
```

through branches, forks and private environment configuration.

The public repository must not contain:

* OpenStack credentials
* OpenStack tokens
* private SSH keys
* WireGuard private keys
* database passwords
* API tokens
* TLS private keys
* Wazuh credentials
* personal infrastructure state

Environment-specific values belong outside the public repository or in an appropriate secret-management system.

---

# 4. Network model

## 4.1 Management network

```text
10.50.0.0/24
```

Used for:

* infrastructure administration
* Slurm
* management traffic
* internal service communication
* SSH from the bastion

---

## 4.2 Kubernetes network

```text
10.51.0.0/24
```

Used for:

* Kubernetes control plane
* Kubernetes workers
* Kubernetes API load balancer

The Kubernetes API endpoint is:

```text
10.51.0.100:6443
```

---

## 4.3 WireGuard network

```text
10.60.0.0/24
```

Canonical variable name:

```yaml
vpn_cidr: 10.60.0.0/24
```

WireGuard provides administrator/user access into the private infrastructure.

The first administrator client uses an address such as:

```text
10.60.0.2/32
```

---

# 5. Security model

The platform uses multiple security layers.

```text
Internet
   │
   ▼
OpenStack security groups
   │
   ▼
edge / nftables
   │
   ├── WireGuard
   ├── DNS
   ├── Wazuh
   └── routed private networks
        │
        ▼
Kubernetes / Slurm / services
```

OpenStack security groups provide the cloud-level network boundary.

nftables provides host-level filtering.

Kubernetes NetworkPolicy/Cilium provides workload-level segmentation.

Application authentication and authorization provide the final logical layer.

---

# 6. OpenStack credentials

Verify OpenStack authentication before running Terraform.

```bash
openstack token issue
openstack quota show --compute
openstack network list
openstack image list
openstack flavor list
```

The OpenStack cloud configuration should normally be stored in:

```text
~/.config/openstack/clouds.yaml
```

Do not commit credentials.

The Terraform provider source must be:

```hcl
terraform-provider-openstack/openstack
```

not:

```text
hashicorp/openstack
```

---

# 7. Required local software

Install:

```bash
terraform
ansible
ansible-core
kubectl
helm
openstackclient
```

Install required Ansible collections:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

The repository uses collections including:

```yaml
collections:
  - name: community.general
  - name: ansible.posix
```

---

# 8. Terraform environment

Create a private environment from the template.

```bash
cp -r terraform/environments/template terraform/environments/private
```

Keep the private environment outside Git.

A private environment contains:

```text
terraform/environments/private/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── terraform.tfvars
```

The public template contains placeholders.

---

# 9. Terraform variables

Typical private values include:

```hcl
openstack_cloud       = "..."
openstack_region      = "RegionOne"
external_network_name = "..."

image_id     = "..."
ssh_key_name = "..."

edge_flavor              = "..."
hermes_flavor            = "..."
slurm_controller_flavor  = "..."
login_flavor             = "..."
compute_12c_flavor       = "..."
k8s_control_plane_flavor = "..."
k8s_worker_flavor        = "..."

api_lb_type   = "haproxy"
api_lb_flavor = "C4.small"

api_lb_address = "10.51.0.100"

kubernetes_api_port = 6443

kubernetes_control_plane_addresses = [
  "10.51.0.11",
  "10.51.0.12",
  "10.51.0.13",
]
```

`api_lb_type` selects the implementation:

```text
haproxy
octavia
```

---

# 10. Terraform initialization

From the environment:

```bash
cd terraform/environments/private
terraform init
terraform validate
```

Before applying:

```bash
terraform plan
```

The plan should show the expected networks, security groups, ports and VMs.

Never apply a plan containing unexpected destruction.

---

# 11. Terraform apply

```bash
terraform apply
```

Afterward:

```bash
terraform output
```

Expected outputs include:

```text
edge_floating_ip
kubernetes_api_address
kubernetes_api_endpoint
kubernetes_api_port
node_ips
```

---

# 12. HAProxy API load balancer

The Kubernetes API endpoint must remain independent of the load-balancer implementation.

Current implementation:

```text
HAProxy VM
10.51.0.100
```

Backend control planes:

```text
10.51.0.11:6443
10.51.0.12:6443
10.51.0.13:6443
```

Conceptually:

```text
                10.51.0.100:6443
                       │
                    HAProxy
                 /      |      \
                /       |       \
          CP-01       CP-02      CP-03
```

The same logical endpoint is intended to survive a future migration from HAProxy to Octavia.

The load-balancer VM is deliberately outside the generic Kubernetes node list.

---

# 13. SSH access

The infrastructure uses two identities.

## Bootstrap/recovery

```text
rocky
```

with the OpenStack bootstrap key.

## Operational administration

```text
nyameko
```

with a separate SSH key.

The operational key is installed by Ansible and is the normal administrative identity.

The bootstrap account remains available until recovery procedures have been tested.

---

# 14. SSH through edge

Only `edge` has the public floating IP.

Normal access is:

```text
workstation
   │
   ▼
edge
   │
   ▼
private VM
```

Configure `ProxyJump` in `~/.ssh/config`.

Normal operations use:

```text
nyameko
```

Recovery can use an explicit `rocky` host alias.

---

# 15. Base operating-system bootstrap

The initial bootstrap establishes:

* base packages
* chrony
* timezone
* SSH
* administrative user
* sudo
* Wazuh agent

Run:

```bash
cd ansible
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/bootstrap.yml
```

---

# 16. Time synchronization

All systems must use:

```text
Africa/Johannesburg
```

while chrony synchronizes the actual clock.

Verify:

```bash
ansible all \
  -i inventories/private/hosts.yml \
  -m command \
  -a "timedatectl show -p Timezone --value"
```

Expected:

```text
Africa/Johannesburg
```

Check synchronization:

```bash
ansible all \
  -i inventories/private/hosts.yml \
  -m command \
  -a "chronyc tracking"
```

Healthy systems should show:

```text
Leap status : Normal
```

and a small system/NTP offset.

Time synchronization is a prerequisite for distributed systems such as Kubernetes, Slurm, TLS, authentication and telemetry.

---

# 17. Administrative user

Ansible creates:

```text
nyameko
```

with:

* home directory
* SSH public key
* `wheel`
* passwordless sudo

The public key is environment-specific.

Do not store the private key in the repository.

After verifying the new identity:

```bash
ssh edge
ssh k8s-cp-01
ssh slurm-controller
ssh api-lb-01
```

switch Ansible to:

```yaml
ansible_user: nyameko
```

---

# 18. Edge architecture

`edge` is the infrastructure gateway.

```text
edge
├── nftables
├── WireGuard
├── Pi-hole
├── Wazuh manager
└── Suricata
```

`edge` should not become a general-purpose application server.

Its primary responsibilities are:

* controlled external access
* routing
* DNS
* security monitoring
* administrative entry

---

# 19. nftables

The OpenStack security group is the first network boundary.

nftables is the host firewall.

The policy uses:

```text
input  → drop by default
forward → drop by default
output → allow by default
```

and explicitly permits required traffic.

Stateful rules use:

```nft
ct state established,related accept
```

The firewall also provides NAT for WireGuard clients:

```text
10.60.0.0/24
       │
       ▼
      wg0
       │
       ▼
      edge
       │
    masquerade
       │
       ▼
   external network
```

Before applying a firewall:

```bash
sudo nft -c -f /etc/nftables.conf
```

Then inspect:

```bash
sudo nft list ruleset
```

Never deploy an untested firewall remotely.

---

# 20. WireGuard

WireGuard is the primary remote administrative path.

The server runs on:

```text
edge
10.60.0.1/24
```

The server's private key is generated on `edge` and never stored in the repository.

The server public key is safe to distribute to clients.

The peer configuration contains:

```text
PublicKey
PresharedKey
AllowedIPs
```

The first administrative peer may use:

```text
10.60.0.2/32
```

The server private key does not need to leave the server.

A complete rebuild therefore creates a new WireGuard identity.

---

# 21. WireGuard client configuration

The client private key remains on the client.

The client configuration conceptually contains:

```text
[Interface]
Address = 10.60.0.2/32
PrivateKey = <client-private-key>

[Peer]
PublicKey = <edge-public-key>
PresharedKey = <shared-psk>
Endpoint = <edge-public-address>:51820
AllowedIPs = 10.50.0.0/24, 10.51.0.0/24
PersistentKeepalive = 25
```

On Linux:

```bash
sudo wg-quick up wg0
```

and:

```bash
sudo wg show
```

---

# 22. Pi-hole

Pi-hole runs on `edge` as an infrastructure service.

The intended architecture is:

```text
VM
 │
 ▼
10.50.0.10:53
 │
 ▼
Pi-hole
 │
 ▼
upstream DNS
```

It provides:

* DNS resolution
* filtering
* ad/malware blocking
* local infrastructure records

The initial deployment uses a Podman-managed container.

Persistent data lives under:

```text
/opt/pihole/etc-pihole
```

Later this directory should be backed by persistent storage.

---

# 23. DNS architecture

The desired long-term DNS hierarchy is:

```text
Kubernetes pod
      │
      ▼
CoreDNS
      │
      ▼
Pi-hole
      │
      ▼
upstream DNS
```

This allows a single infrastructure DNS policy.

Internal names can later include:

```text
grafana...
jupyter...
argo...
wazuh...
hermes...
```

Public names can use DNS managed through Cloudflare.

---

# 24. Wazuh

The Wazuh architecture separates:

```text
agents
   │
   ▼
Wazuh server/manager
   │
   ▼
Wazuh indexer
   │
   ▼
Wazuh dashboard
```

The initial deployment puts the manager on:

```text
edge
10.50.0.10
```

All other VMs run Wazuh agents.

The manager can operate without the indexer/dashboard for basic event collection and local log analysis.

The indexer and dashboard are deployed later inside Kubernetes. Wazuh documents the server/manager, indexer and dashboard as separate architectural components. [Wazuh server installation](https://documentation.wazuh.com/current/installation-guide/wazuh-server/step-by-step.html)

---

# 25. Wazuh manager

Configure:

```yaml
wazuh_manager_address: 10.50.0.10
```

on the private environment.

The manager should be deployed only to `edge`.

The initial verification is:

```bash
sudo systemctl status wazuh-manager
```

and:

```bash
sudo ss -lntup
```

The Wazuh agent role should point to the same manager address.

---

# 26. Wazuh agents

Every infrastructure VM receives the Wazuh agent.

That includes:

```text
edge
hermes-orchestrator
slurm-controller
login1
login2
slurm-compute
api-lb
k8s-control-plane
k8s-workers
```

The agent communicates with:

```text
10.50.0.10
```

The manager's indexer/dashboard do not need to exist for the agents to begin reporting to the manager.

---

# 27. Suricata

Suricata is initially deployed as an IDS.

The first objective is:

```text
observe
 ↓
detect
 ↓
alert
```

not:

```text
observe
 ↓
inline IPS
 ↓
drop
```

Suricata should not be inserted into Kubernetes east-west traffic simply because it runs on `edge`.

Traffic must actually traverse the monitoring point.

IPS is introduced later after the forwarding path is explicitly designed and tested.

---

# 28. Edge verification

After configuring the edge:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/edge.yml
```

Verify:

```bash
ssh edge
```

Then:

```bash
sudo systemctl status nftables
sudo systemctl status wg-quick@wg0
sudo systemctl status wazuh-manager
sudo systemctl status pihole
sudo wg show
sudo nft list ruleset
```

---

# 29. API load balancer verification

Configure:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/api-lb.yml
```

Verify:

```bash
ssh api-lb-01
sudo systemctl status haproxy
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

The HAProxy backends should point to:

```text
10.51.0.11:6443
10.51.0.12:6443
10.51.0.13:6443
```

---

# 30. Kubernetes prerequisites

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

* containerd
* kubelet
* kubeadm
* kubectl
* required kernel modules
* sysctl configuration

containerd should use the systemd cgroup driver. Kubernetes documents this as the recommended configuration when using cgroup v2. [Kubernetes container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

Verify:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -m shell \
  -a 'systemctl is-active containerd'
```

and:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -m command \
  -a 'kubeadm version'
```

---

# 31. Kubernetes API endpoint

kubeadm must use:

```text
10.51.0.100:6443
```

not an individual control-plane address.

This provides a stable endpoint:

```text
kubeadm / kubectl
       │
       ▼
10.51.0.100:6443
       │
    HAProxy
       │
 ┌─────┼─────┐
 ▼     ▼     ▼
CP1   CP2   CP3
```

---

# 32. Kubernetes bootstrap

The initial bootstrap sequence is:

```text
k8s-cp-01
    │
    └── kubeadm init
             │
             ├── upload certificates
             └── generate join information
                       │
              ┌────────┴────────┐
              ▼                 ▼
          k8s-cp-02         k8s-cp-03
                               
              workers
                 │
        ┌────────┼────────┐
        ▼        ▼        ▼
       W1       W2       W3
```

Run:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes.yml
```

The control-plane endpoint remains:

```text
10.51.0.100:6443
```

---

# 33. Initial Kubernetes validation

On `k8s-cp-01`:

```bash
kubectl get nodes
```

At this stage nodes may remain:

```text
NotReady
```

until the CNI is installed.

Verify kubelet:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -m command \
  -a 'systemctl is-active kubelet'
```

Verify the API load-balancer:

```bash
curl -sk https://10.51.0.100:6443/healthz
```

---

# 34. Cilium

Cilium becomes the Kubernetes networking layer.

Responsibilities include:

* pod networking
* node networking
* NetworkPolicy
* service networking
* observability
* future security segmentation

The first installation should remain conservative.

Verify:

```bash
cilium status
kubectl get nodes
```

All six nodes should eventually become:

```text
Ready
```

Cilium provides official kubeadm installation documentation. [Cilium kubeadm installation](https://docs.cilium.io/en/latest/installation/k8s-install-kubeadm/)

---

# 35. OpenStack integration

Once Kubernetes and Cilium are working, add OpenStack integration.

The important components are:

```text
OpenStack Cloud Controller Manager
Cinder CSI
```

This allows Kubernetes to request cloud resources such as:

```text
LoadBalancer
PersistentVolume
```

and connect them to OpenStack infrastructure.

---

# 36. Persistent storage

Important application state should not depend on VM root disks or pod-local storage.

The intended hierarchy is:

```text
Application
   │
   ▼
PVC
   │
   ▼
CSI
   │
   ▼
Cinder
```

Persistent storage will be used for:

* PostgreSQL
* Wazuh indexer
* Grafana
* Jupyter data
* user data
* application state
* research datasets

Cinder volumes should survive VM/Kubernetes rebuilds where appropriate.

---

# 37. Argo CD

Once Kubernetes networking and persistent storage work, install Argo CD.

Argo becomes the deployment mechanism for Kubernetes applications:

```text
Git
 │
 ▼
Argo CD
 │
 ▼
Kubernetes
```

The desired operating model is:

```text
Terraform
    ↓
OpenStack infrastructure

Ansible
    ↓
host configuration

Argo CD
    ↓
Kubernetes applications
```

Manual `kubectl apply` should increasingly be reserved for debugging and emergency recovery.

---

# 38. Wazuh indexer and dashboard in Kubernetes

Deploy:

```text
wazuh-indexer
wazuh-dashboard
```

inside Kubernetes.

The intended architecture becomes:

```text
                         ┌───────────────┐
Agents ─────────────────►│ Wazuh manager │
                         │    on edge    │
                         └───────┬───────┘
                                 │
                                 ▼
                         ┌───────────────┐
                         │ Wazuh indexer │
                         │  Kubernetes   │
                         └───────┬───────┘
                                 │
                                 ▼
                         ┌───────────────┐
                         │Wazuh dashboard│
                         │  Kubernetes   │
                         └───────────────┘
```

Indexer data requires persistent storage.

---

# 39. Observability

The platform will eventually provide:

```text
Prometheus
Grafana
Loki
```

for:

* node metrics
* Kubernetes metrics
* workload metrics
* Slurm metrics
* application telemetry
* Hermes telemetry
* research workload telemetry

Grafana access should eventually be controlled by user identity and RBAC.

---

# 40. User telemetry model

The platform is intended to support:

```text
Student
   ↓
own workloads

Team
   ↓
team workloads

Principal Investigator
   ↓
student/team workloads

Administrator
   ↓
platform-wide telemetry
```

This separation should be enforced at the application and data layer rather than relying solely on URL obscurity.

---

# 41. Slurm

Slurm remains the scheduler for pure HPC workloads.

Initial nodes:

```text
slurm-controller-01
login1
login2
slurm-cpu-01
slurm-cpu-02
```

The two compute VMs are currently using the test flavor:

```text
compute_12c_flavor
```

The final architecture can replace the flavor later with an exact 64-vCPU flavor.

Slurm is independent of Kubernetes:

```text
                     Platform
                        │
          ┌─────────────┴─────────────┐
          ▼                           ▼
      Kubernetes                    Slurm
          │                           │
      services                    HPC jobs
```

This distinction is intentional.

---

# 42. Interactive research environments

JupyterHub will provide the user-facing research interface.

Initial flow:

```text
Browser
   │
   ▼
Ingress
   │
   ▼
JupyterHub
   │
   ▼
JupyterLab
```

The longer-term research environment will allow users to select:

```text
Python
PyTorch
Qiskit
Qiskit Aer
PennyLane
PennyLane Lightning
CUDA Quantum
custom research images
```

and request resources such as:

```text
CPU = X
RAM = Y
Storage = Z
GPU = N
```

---

# 43. Shared research environments

The research platform is intended to evolve toward:

```text
JupyterHub
    │
    ▼
environment selector
    │
    ├── PennyLane
    ├── Qiskit
    ├── CUDA Quantum
    ├── PyTorch
    └── custom environments
```

Each environment should be represented by a versioned container image.

For example:

```text
pennylane-01
pennylane-02
qiskit-aer-01
qiskit-aer-02
cuda-quantum-01
```

This provides reproducible research environments.

---

# 44. Slurm and Kubernetes application scheduling

Two distinct execution models are supported:

### Kubernetes

Best suited to:

* web services
* APIs
* notebooks
* model serving
* telemetry
* databases
* long-running microservices

### Slurm

Best suited to:

* batch jobs
* MPI
* HPC simulations
* CPU-intensive workloads
* GPU batch jobs
* scientific workflows

Future integrations may allow JupyterHub to submit resource-backed workloads to Slurm.

---

# 45. Hermes

Hermes is the orchestration layer.

The initial design contains:

```text
hermes-orchestrator-01
```

outside Kubernetes.

A second research Hermes agent will eventually run inside Kubernetes.

Conceptually:

```text
Personal Hermes
      │
      ▼
Platform Hermes
      │
      ├── OpenStack
      ├── Kubernetes
      ├── Slurm
      ├── Git
      ├── telemetry
      └── security
```

The infrastructure Hermes agent should follow a least-privilege model.

It should not have unrestricted write access to:

* the Git repository
* cluster-admin
* arbitrary secrets
* all user workloads

unless explicitly authorised.

---

# 46. Hermes federation

The architecture is designed for multiple Hermes agents.

Example:

```text
Personal Hermes
      │
      ├── Research Hermes
      │      ├── Kubernetes
      │      ├── JupyterHub
      │      └── AI/QC workloads
      │
      ├── Infrastructure Hermes
      │      ├── OpenStack
      │      ├── Slurm
      │      └── networking
      │
      ├── Purple Team Hermes
      │
      └── future federated agents
```

The federation should use explicitly defined capabilities and trust boundaries.

---

# 47. Astro research portal

The first public Kubernetes web workload can be a minimal Astro site.

Initial target:

```text
quantum.nyameko.com
```

Architecture:

```text
Cloudflare
    │
    ▼
Ingress
    │
    ▼
Astro service
    │
    ▼
Astro container
```

The initial goal is simply to prove:

```text
DNS
→ Cloudflare
→ ingress
→ Kubernetes
→ container
```

---

# 48. PostgreSQL

PostgreSQL is a later platform service.

It will provide persistent structured data for applications such as:

* user information
* research portal data
* JupyterHub metadata
* future authentication/application services
* Hermes metadata where appropriate

The intended storage model is:

```text
PostgreSQL
    │
    ▼
PVC
    │
    ▼
Cinder
```

PostgreSQL should not be introduced until Kubernetes persistent storage is working reliably.

---

# 49. Cloudflare

Cloudflare will eventually front public services.

Initial public hostname:

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

Kubernetes ingress provides the service endpoint behind Cloudflare.

---

# 50. Complete deployment sequence

The intended installation order is:

```text
1. OpenStack credentials
       ↓
2. Terraform
       ↓
3. networks
       ↓
4. security groups
       ↓
5. VMs
       ↓
6. SSH/bootstrap
       ↓
7. common OS configuration
       ↓
8. nyameko admin
       ↓
9. time synchronization
       ↓
10. edge
       ├── nftables
       ├── WireGuard
       ├── Pi-hole
       ├── Wazuh manager
       └── Suricata
       ↓
11. HAProxy
       ↓
12. Kubernetes prerequisites
       ↓
13. kubeadm
       ↓
14. Cilium
       ↓
15. OpenStack CCM
       ↓
16. Cinder CSI
       ↓
17. Argo CD
       ↓
18. Wazuh indexer/dashboard
       ↓
19. Prometheus/Grafana/Loki
       ↓
20. ingress/cert-manager
       ↓
21. JupyterHub
       ↓
22. Astro
       ↓
23. PostgreSQL
       ↓
24. Hermes research agent
```

Slurm may be configured independently after the base OS layer.

---

# 51. Validation philosophy

Every phase should have a validation test.

Do not proceed because an Ansible playbook merely finishes with:

```text
failed=0
```

Verify the actual service.

Examples:

```bash
systemctl is-active chronyd
systemctl is-active nftables
systemctl is-active wazuh-manager
systemctl is-active haproxy
systemctl is-active containerd
systemctl is-active kubelet
```

and:

```bash
wg show
nft list ruleset
chronyc tracking
kubectl get nodes
cilium status
```

---

# 52. Rebuild philosophy

The infrastructure is intended to be rebuildable.

```text
Git
 │
 ├── Terraform
 │      ↓
 │   OpenStack
 │
 ├── Ansible
 │      ↓
 │   operating systems
 │
 └── Argo CD
        ↓
     Kubernetes
```

Persistent data must be separated from disposable infrastructure.

```text
VM
 └── disposable

Cinder
 └── persistent
```

This distinction is fundamental to the backup and disaster-recovery strategy.

---

# 53. Security checklist

Before considering an environment operational:

```text
[ ] OpenStack credentials not committed
[ ] Terraform state protected
[ ] private inventory ignored
[ ] SSH private keys outside Git
[ ] WireGuard private keys outside Git
[ ] passwords outside Git
[ ] nyameko SSH access verified
[ ] rocky recovery access retained
[ ] password SSH authentication disabled
[ ] nftables active
[ ] OpenStack security groups restricted
[ ] WireGuard working
[ ] Wazuh agents reporting
[ ] Wazuh manager running
[ ] Suricata running in IDS mode
[ ] Kubernetes API reachable only through intended paths
[ ] persistent storage tested
```

---

# 54. Educational use

This repository is also intended as a teaching framework.

Students should understand the boundary between:

```text
Infrastructure
    ↓
Operating system
    ↓
Network/security
    ↓
Scheduler/orchestrator
    ↓
Container platform
    ↓
Application
    ↓
Research workload
```

A useful learning path is therefore:

```text
OpenStack
   ↓
Terraform
   ↓
Linux
   ↓
Ansible
   ↓
Networking
   ↓
Security
   ↓
Kubernetes
   ↓
Cilium
   ↓
Storage
   ↓
GitOps
   ↓
Observability
   ↓
Slurm
   ↓
AI/ML
   ↓
Quantum computing
   ↓
Hermes
```

Every major component should be teachable independently before it is combined into the platform.

---

# 55. Further reading

OpenStack:

* https://docs.openstack.org/
* https://docs.openstack.org/nova/latest/
* https://docs.openstack.org/neutron/latest/
* https://docs.openstack.org/cinder/latest/

Terraform:

* https://developer.hashicorp.com/terraform/docs

Ansible:

* https://docs.ansible.com/

Kubernetes:

* https://kubernetes.io/docs/

Cilium:

* https://docs.cilium.io/

Slurm:

* https://slurm.schedmd.com/

WireGuard:

* https://www.wireguard.com/

nftables:

* https://wiki.nftables.org/

Wazuh:

* https://documentation.wazuh.com/

Pi-hole:

* https://docs.pi-hole.net/

Prometheus:

* https://prometheus.io/docs/

Grafana:

* https://grafana.com/docs/

Argo CD:

* https://argo-cd.readthedocs.io/

JupyterHub:

* https://jupyterhub.readthedocs.io/

Astro:

* https://docs.astro.build/

Cloudflare:

* https://developers.cloudflare.com/

---

# 56. Final smoke test

After the platform has been deployed:

```bash
ansible all -m ping
```

Verify all expected hosts.

Verify Kubernetes:

```bash
kubectl get nodes -o wide
```

Verify Cilium:

```bash
cilium status
```

Verify the API endpoint:

```bash
curl -sk https://10.51.0.100:6443/healthz
```

Verify Slurm:

```bash
sinfo
```

Verify WireGuard:

```bash
sudo wg show
```

Verify Wazuh:

```bash
sudo systemctl status wazuh-manager
```

Verify nftables:

```bash
sudo nft list ruleset
```

Verify persistent volumes:

```bash
kubectl get storageclass
kubectl get pv
kubectl get pvc --all-namespaces
```

The infrastructure should be considered operational only when the individual layers have been validated rather than merely created.
