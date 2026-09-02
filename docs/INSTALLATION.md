# Installation Guide

> A complete, hand-held deployment of the `infra-hpc-qc-k8s` platform.
>
> The guide deliberately explains **what**, **why**, **trade-offs**, **failure modes** and **acceptance tests**. Commands are written for an Arch Linux workstation deploying Rocky Linux guests in OpenStack.

---

## 0. Read this first

### What you are building

The target platform is a layered infrastructure stack:

```text
                     OpenStack
                         │
                    Terraform
                         │
             networks / ports / SGs / VMs
                         │
                      Ansible
                         │
        ┌────────────────┼────────────────┐
        │                │                │
      Edge             Slurm          Kubernetes
        │                                 │
   DNS / VPN /                        kubeadm
   security                          + Cilium
                                          │
                                   CCM + Cinder CSI
                                          │
                                      Argo CD
                                          │
                                     Applications
```

The project is intentionally neither “just Kubernetes” nor “just OpenStack”. It is an infrastructure laboratory in which each layer has a distinct responsibility.

### The first principle: build in layers

Never begin by installing everything at once.

The intended order is:

```text
Cloud
 ↓
Operating systems
 ↓
Network / security
 ↓
API endpoint
 ↓
Container runtime
 ↓
Kubernetes
 ↓
CNI
 ↓
Cloud integration / storage
 ↓
GitOps
 ↓
Applications
```

Every arrow is an acceptance gate.

> **WARNING:** A command succeeding is not proof that the system is healthy. The deployment process therefore contains explicit tests after every significant phase.

---

# Part I — Architecture before installation

## 1. Target topology

### 1.1 Networks

| Network | CIDR | Purpose |
|---|---|---|
| Management | `10.50.0.0/24` | VM management and infrastructure services |
| Kubernetes | `10.51.0.0/24` | Kubernetes nodes and API endpoint |
| WireGuard | `10.60.0.0/24` | Private administrative VPN |

The canonical Ansible variables are:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr: 10.51.0.0/24
vpn_cidr: 10.60.0.0/24
```

> **NOTE:** Variable-name consistency matters. During the project's build, `management_cidr` / `wireguard_cidr` drift created avoidable ambiguity. The canonical names above should be used everywhere.

### 1.2 Hosts

```text
Management network: 10.50.0.0/24

edge                         10.50.0.10
hermes-orchestrator-01       10.50.0.11
slurm-controller-01          10.50.0.12
login1                       10.50.0.20
login2                       10.50.0.21
slurm-cpu-01                 10.50.0.30
slurm-cpu-02                 10.50.0.31

Kubernetes network: 10.51.0.0/24

api-lb-01 / VIP              10.51.0.100
k8s-cp-01                    10.51.0.11
k8s-cp-02                    10.51.0.12
k8s-cp-03                    10.51.0.13
k8s-worker-01                10.51.0.21
k8s-worker-02                10.51.0.22
k8s-worker-03                10.51.0.23
```

The apparent address reuse between management and Kubernetes networks is intentional because they are different subnets on different network segments.

### 1.3 Kubernetes API

The cluster's API endpoint is:

```text
10.51.0.100:6443
```

HAProxy fronts three control planes:

```text
                 10.51.0.100:6443
                        │
                     HAProxy
                  ┌────┼────┐
                  ▼    ▼    ▼
                 CP1  CP2  CP3
```

> **DESIGN CHOICE:** Keep the API endpoint stable even when the implementation of the load balancer changes. Today that implementation is HAProxy; OpenStack Octavia can become a future implementation where available.

---

# Part II — Workstation preparation

## 2. Assumptions

The reference workstation is Arch Linux. The target guests are Rocky Linux.

You need:

- Git
- Terraform
- Ansible
- OpenStack CLI
- SSH
- access to the OpenStack project
- the repository's private environment files

Install the local tools:

```bash
sudo pacman -Syu git ansible terraform python-openstackclient
```

Verify:

```bash
git --version
terraform version
ansible --version
openstack --version
ssh -V
```

> **NOTE:** The workstation distribution is not a hard architectural dependency. Arch is simply the current reference environment. The managed guests remain Rocky Linux.

---

## 3. Clone the repository

```bash
git clone https://github.com/nyameko/infra-hpc-qc-k8s.git
cd infra-hpc-qc-k8s
```

Inspect the repository:

```bash
find terraform ansible docs -maxdepth 2 -type f | sort
```

Before making changes, inspect the recent project history:

```bash
git log --oneline --decorate -20
```

The repository history is intentionally part of the learning material. The recent deployment work contains the evolution of the Cilium, CRI and security-group configuration.

---

# Part III — Credentials and private configuration

## 4. OpenStack credentials

Configure OpenStack using your normal external mechanism (`clouds.yaml`, environment variables, application credentials, etc.). Do not put secrets in the repository.

Validate access:

```bash
openstack token issue
openstack network list
openstack image list
openstack flavor list
```

You should be able to identify:

- the project/network context
- the target Rocky image
- the expected VM flavors
- the networks available to the project

> **DANGER:** Never “temporarily” paste an OpenStack password, application credential, private key or token into a tracked YAML file. Temporary secrets have a habit of becoming permanent Git history.

### Why Terraform receives cloud credentials, but Ansible does not

Terraform is the cloud lifecycle tool. It needs OpenStack credentials because it creates cloud resources.

Ansible talks to already-created hosts over SSH. It normally does not need the OpenStack administrative credential.

This reduces the blast radius of the Ansible execution environment.

---

## 5. Private Ansible inventory

The environment-specific inventory should live outside the public defaults:

```text
ansible/inventories/private/
├── hosts.yml
└── group_vars/
    └── all.yml
```

Inspect the resolved inventory:

```bash
cd ansible
ansible-inventory -i inventories/private/hosts.yml --graph
```

Inspect host variables:

```bash
ansible-inventory \
  -i inventories/private/hosts.yml \
  --host edge
```

> **IMPORTANT:** `ansible-inventory` is the authoritative diagnostic when a variable appears to have disappeared. Do not guess what Ansible will load.

Validate connectivity before doing any configuration:

```bash
ansible all -i inventories/private/hosts.yml -m ping
```

---

# Part IV — Terraform: create the cloud

## 6. Terraform ownership

Terraform should own:

```text
OpenStack networks
OpenStack subnets
routers
security groups
ports
floating IPs
VMs
API load-balancer VM/networking
storage resources where appropriate
```

It should **not** install packages inside Rocky guests.

This separation means that destroying/recreating a VM does not require Terraform to learn how the guest operating system is configured.

---

## 7. Initialize and validate Terraform

```bash
cd ../terraform/environments/private
terraform init
terraform fmt -check
terraform validate
```

Then inspect the plan:

```bash
terraform plan
```

Read the plan rather than blindly applying it.

Check particularly:

- networks
- CIDRs
- security groups
- port fixed IPs
- server flavor IDs
- image IDs
- floating IP associations
- API load-balancer resources

### Flavor-name versus flavor-ID trap

OpenStack APIs often distinguish between the human-friendly flavor name and the resource ID.

A deployment failure previously arose because a resource expected a flavor ID while the configuration supplied a flavor name.

> **WARNING:** Never assume that a field named `flavor` or `flavor_id` accepts the friendly flavor name. Confirm the provider schema and inspect the actual OpenStack resource IDs.

Useful inspection:

```bash
openstack flavor list
```

---

## 8. Apply Terraform

```bash
terraform apply
```

Then verify:

```bash
openstack server list
openstack network list
openstack subnet list
openstack port list
openstack security group list
```

The important acceptance criterion is not “Terraform returned zero”; it is that the expected topology exists.

### Acceptance gate

You should be able to identify:

```text
edge
Hermes VM
Slurm controller
Slurm logins
Slurm compute
API LB
3 Kubernetes control planes
3 Kubernetes workers
```

---

# Part V — Rocky Linux bootstrap

## 9. Why `rocky` exists

The image/bootstrap account is deliberately distinct from the normal admin account.

```text
rocky
  │
  └── bootstrap / recovery

nyameko
  │
  └── normal administration
```

Ansible installs/configures the `nyameko` account and its authorized SSH key.

> **DESIGN CHOICE:** The bootstrap account is not a sign that the system is unfinished. It is a deliberate recovery plane until recovery has been tested.

---

## 10. Base bootstrap

Run:

```bash
cd ../../ansible
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/bootstrap.yml
```

Validate:

```bash
ansible all -i inventories/private/hosts.yml -m ping
```

Check hostname/time:

```bash
ansible all -i inventories/private/hosts.yml -m command \
  -a 'hostnamectl --static'

ansible all -i inventories/private/hosts.yml -m command \
  -a 'timedatectl show -p Timezone --value'
```

The expected local timezone is:

```text
Africa/Johannesburg
```

### Timezone versus clock synchronization

These are different concepts:

```text
timedatectl timezone
      = presentation / local civil time

chrony
      = actual clock synchronization
```

Check chrony:

```bash
ansible all -i inventories/private/hosts.yml -b -m command \
  -a 'chronyc tracking'
```

Look for a healthy synchronization state such as:

```text
Leap status : Normal
```

> **WARNING:** Distributed systems do not tolerate casual time drift. Kubernetes certificates, TLS, logs, databases and authentication all become harder to reason about when clocks disagree.

---

# Part VI — Edge security and network access

## 11. Edge responsibilities

The edge node is:

```text
10.50.0.10
```

It provides:

```text
nftables
WireGuard
Pi-hole
Suricata IDS
Wazuh manager / edge security
SSH bastion role
```

Run:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/edge.yml
```

Validate:

```bash
ansible edge_nodes -i inventories/private/hosts.yml -b -m shell -a \
  'systemctl is-active nftables; systemctl is-active wg-quick@wg0; systemctl is-active pihole-FTL; systemctl is-active suricata'
```

---

## 12. Defense in depth

OpenStack security groups and host firewalls answer different questions.

```text
OpenStack SG
  = what traffic may reach the VM?

nftables
  = what traffic may the operating system accept/forward?
```

The target nftables model is approximately:

```text
input   → drop
forward → drop
output  → accept
```

with explicit exceptions and established/related traffic handling.

Validate a new ruleset before applying it:

```bash
sudo nft -c -f /etc/nftables.conf
```

Inspect the active policy:

```bash
sudo nft list ruleset
```

> **DANGER:** Firewall changes can lock you out. Always keep the recovery/console path available while changing host firewall policy.

---

## 13. WireGuard

The server is on edge:

```text
edge / wg0
10.60.0.1/24
```

A typical client is:

```text
10.60.0.2/32
```

The client split tunnel should permit the private infrastructure networks rather than forcing all traffic through the VPN:

```text
10.50.0.0/24
10.51.0.0/24
10.60.0.0/24
```

Validate on edge:

```bash
sudo wg show
ip addr show wg0
ip route
```

> **DANGER:** The WireGuard private key stays on the host/client where it was generated. Store or distribute only the public key where needed.

---

## 14. Pi-hole

Pi-hole runs at the edge because DNS is foundational infrastructure.

The conceptual path is:

```text
host / pod
    │
    ▼
DNS request
    │
    ▼
edge :53
    │
    ▼
Pi-hole
    │
    ▼
upstream DNS
```

Validate:

```bash
sudo ss -lunpt | grep ':53'
```

Where applicable, confirm the container/service is running and that the host can resolve names through it.

> **NOTE:** A DNS service can be “running” while clients still fail because of firewall, listen-address, routing or upstream-resolution problems. Test from a client network, not just the service host.

---

# Part VII — Kubernetes API endpoint

## 15. Why HAProxy comes before kubeadm

The control-plane nodes need a stable endpoint from the moment the cluster is bootstrapped.

The target is:

```text
10.51.0.100:6443
```

Run:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/api_lb.yml
```

Validate configuration:

```bash
ssh api-lb-01
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl is-active haproxy
sudo ss -lntp | grep 6443
```

### Why the HAProxy service can fail even when the config syntax is correct

A previous deployment showed:

```text
cannot bind socket (Permission denied)
```

The configuration itself parsed successfully. The failure was caused by SELinux policy: HAProxy was not yet permitted to perform the required connection behavior.

The fix was to enable the appropriate SELinux boolean through Ansible rather than weakening SELinux globally.

This is an important lesson:

```text
Configuration valid ≠ service permitted to perform the action
```

Useful checks:

```bash
getenforce
getsebool haproxy_connect_any
sudo journalctl -u haproxy -b
```

> **DESIGN CHOICE:** Fix the specific SELinux control instead of disabling SELinux. Security policy should be adjusted narrowly to the required behavior.

### Before Kubernetes exists

HAProxy backends can legitimately be `DOWN` at this stage because the API servers do not exist yet.

Do not “fix” that by inventing placeholder services.

---

# Part VIII — Kubernetes runtime prerequisites

## 16. containerd

Kubernetes needs a CRI-compatible container runtime.

This project uses containerd.

The Rocky packaging detail matters: the required package is provided as `containerd.io` from the configured Docker repository, not an arbitrary `containerd` package name from the base Rocky repositories.

This distinction fixed a real deployment failure.

Run:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-prereqs.yml
```

Check:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml -b -m shell -a \
  'systemctl is-active containerd; systemctl is-active kubelet'
```

The runtime should use the systemd cgroup driver.

> **WARNING:** Mismatched cgroup configuration between kubelet and containerd is a classic source of instability. Treat it as a prerequisite, not a cleanup task for later.

---

## 17. CRI validation — run it correctly

The deployment includes `crictl` and `/etc/crictl.yaml` pointing to:

```text
unix:///run/containerd/containerd.sock
```

Validate:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml -b -m shell -a \
  'crictl info >/dev/null && echo CRI_OK'
```

Expected:

```text
CRI_OK
```

### A real failure mode: “permission denied”

The CRI test initially produced a socket permission error.

The important diagnosis was not “containerd is broken”. The command had been run as the unprivileged `nyameko` user without sufficient permission to inspect the containerd socket.

This is why the acceptance test above explicitly uses Ansible become (`-b`).

> **TEACHING NOTE:** Always classify an error by layer before changing infrastructure. A Unix socket permission error is different from an OpenStack security-group error, a service failure or a broken runtime.

---

# Part IX — kubeadm cluster

## 18. Bootstrap model

The cluster is formed as:

```text
                  CP1
                   │
             kubeadm init
             /           \
           CP2           CP3
            │             │
            └──────┬──────┘
                   │
             workers 1–3
```

Control-plane and worker join credentials are short-lived bootstrap material. They do not belong in Git.

The cluster endpoint remains:

```text
10.51.0.100:6443
```

Run the complete playbook:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes.yml
```

The automation is intentionally idempotent in spirit: an already-initialized control plane should not be reinitialized, and already-joined nodes should not be joined again.

---

## 19. Why kubeadm is separate from Terraform and Ansible

There are three different responsibilities:

```text
Terraform
  → create machines

Ansible
  → prepare machines

kubeadm
  → form Kubernetes control plane / workers
```

Could Ansible execute every kubeadm command directly? Yes.

Should Terraform do it? No.

Terraform's reconciliation model is a poor fit for mutating distributed cluster bootstrap state. Kubernetes itself has already solved that problem with kubeadm/bootstrap tooling.

### Bootstrap credentials

The cluster requires:

```text
bootstrap token
CA discovery hash
control-plane certificate key
```

These should be generated/used during bootstrap, not copied into source control.

---

## 20. Validate the control plane

Before Cilium, expect the cluster to be incomplete.

Useful checks:

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw='/readyz?verbose'
```

You should see the control-plane components and etcd running.

`CoreDNS` being pending before a CNI exists is not automatically a disaster.

> **WARNING:** Do not interpret pre-CNI `NotReady` nodes as a generic kubeadm failure. First distinguish “cluster has no pod network yet” from “control-plane bootstrap failed”.

---

# Part X — Cilium

## 21. Why Cilium is installed after kubeadm

Cilium is the Kubernetes network layer. kubeadm establishes the cluster control plane first.

The conceptual sequence is:

```text
kubeadm
   │
   ▼
Kubernetes control plane exists
   │
   ▼
Cilium installed
   │
   ▼
Pod networking becomes functional
   │
   ▼
Nodes become Ready
```

Install the Cilium version pinned for this environment:

```bash
cilium install <version>
cilium status --wait
```

Then:

```bash
kubectl get nodes -o wide
cilium status
```

---

## 22. Cilium baseline versus advanced features

The initial deployment intentionally keeps advanced Cilium functionality out of the critical bootstrap path.

Current baseline concepts include:

```text
CNI
service networking
NetworkPolicy foundation
eBPF-based networking / observability capabilities
```

Deferred work can later include:

```text
Hubble / Relay
kube-proxy replacement
advanced load balancing
ClusterMesh
advanced policy
```

> **DESIGN CHOICE:** Do not turn on five interacting datapath features while you are still learning whether the basic network works. A known-good baseline is an engineering tool.

---

## 23. OpenStack security groups and Cilium

This was one of the most instructive parts of the build.

A CNI can be completely healthy while the surrounding cloud firewall still prevents specific traffic classes.

The relevant Kubernetes node traffic includes:

```text
TCP 6443      Kubernetes API
TCP 2379-2380 etcd
TCP 10250     kubelet
UDP 8472      VXLAN
TCP 4240      Cilium node health
ICMP          node reachability / health checks
TCP 30000-32767 NodePort
UDP 30000-32767 NodePort
```

The exact allowed source should remain constrained to the Kubernetes node network where appropriate:

```text
source: 10.51.0.0/24
```

### Control plane rules

```text
22/tcp          ← management CIDR
6443/tcp        ← k8s CIDR
2379-2380/tcp   ← k8s CIDR
10250/tcp       ← k8s CIDR
8472/udp        ← k8s CIDR
4240/tcp        ← k8s CIDR
ICMP            ← k8s CIDR
30000-32767/tcp ← k8s CIDR
30000-32767/udp ← k8s CIDR
```

### Worker rules

```text
22/tcp          ← management CIDR
10250/tcp       ← k8s CIDR
8472/udp        ← k8s CIDR
4240/tcp        ← k8s CIDR
ICMP            ← k8s CIDR
30000-32767/tcp ← k8s CIDR
30000-32767/udp ← k8s CIDR
```

### Why VXLAN working does not prove NodePort works

This is a particularly important diagnostic lesson.

The Cilium default tunnel path uses VXLAN traffic such as UDP `8472`.

NodePort traffic uses the Kubernetes NodePort range, by default:

```text
30000-32767
```

Therefore:

```text
UDP 8472 works
        ≠
NodePort works
```

A cluster can have perfectly healthy overlay networking and still fail a NodePort test because the cloud security group blocks the NodePort range.

---

## 24. Cilium health versus NodePort

During troubleshooting, Cilium showed that some health-path traffic was not reaching the expected nodes even though HTTP agent checks worked.

This is exactly why the following should be tested separately:

```text
control-plane API reachability
containerd/CRI
VXLAN
Cilium health
NodePort
ICMP
pod-to-pod
service-to-pod
```

Do not call all of these “networking”. They are different paths.

---

## 25. Run the connectivity test

```bash
cilium connectivity test --debug
```

A successful run in the current environment reached:

```text
82 tests
780 actions
all successful
55 tests skipped
1 scenario skipped
```

This is a major milestone: the cloud firewall, node routing and Cilium datapath are now cooperating sufficiently for the full test suite to pass.

> **NOTE:** Skipped tests are not automatically failures. Read the test output and understand which optional scenarios were intentionally unavailable in the baseline configuration.

---

# Part XI — OpenStack cloud integration and storage

## 26. Why cloud integration comes after a healthy cluster

OpenStack CCM and Cinder CSI add additional moving parts:

```text
Kubernetes API
+ cloud credentials
+ controller integration
+ storage control plane
```

Do not debug all of these simultaneously with kubeadm and CNI.

Install CCM and Cinder CSI after:

```text
6 nodes Ready
Cilium healthy
connectivity test healthy
```

---

## 27. Cinder CSI model

Persistent storage follows:

```text
Application
   │
   ▼
PVC
   │
   ▼
PersistentVolume
   │
   ▼
Cinder CSI
   │
   ▼
OpenStack Cinder
```

Likely consumers include:

```text
Wazuh indexer
Grafana
PostgreSQL
JupyterHub
user data
application state
```

Validate:

```bash
kubectl get storageclass
kubectl get csidrivers
kubectl get pods -A
```

---

# Part XII — Argo CD and GitOps

## 28. Why Argo CD is a separate layer

Ansible is excellent for operating-system and infrastructure configuration.

Kubernetes-native application reconciliation is a different problem.

```text
Ansible
  → host / infrastructure lifecycle

Argo CD
  → Kubernetes application lifecycle
```

Use Argo CD as the normal path for application deployment rather than turning Ansible into a giant application installer.

The target model is:

```text
Git
 │
 ▼
Argo CD
 │
 ▼
Kubernetes
```

---

## 29. Application dependency order

The platform should grow in roughly this order:

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

The exact deployment mechanism can evolve; the dependency model should remain understandable.

---

# Part XIII — Slurm

## 30. Why Slurm remains separate

The initial Slurm topology is:

```text
slurm-controller-01
        │
  ┌─────┴─────┐
  ▼           ▼
login1      login2
  │           │
  └─────┬─────┘
        ▼
slurm-cpu-01 / 02
```

Slurm is authoritative for HPC scheduling.

Kubernetes is authoritative for services, long-running platform components and notebook/application orchestration.

Do not force HPC batch scheduling into Kubernetes merely because the Kubernetes cluster exists.

---

## 31. Configure Slurm

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/slurm.yml
```

Validate:

```bash
sinfo
squeue
scontrol show nodes
```

Then submit a small test job before attempting realistic workloads.

---

# Part XIV — Security services

## 32. Wazuh

The initial arrangement is:

```text
Linux hosts
    │
    ▼
Wazuh agents
    │
    ▼
edge / Wazuh manager
```

Later:

```text
Wazuh manager
     │
     ▼
Wazuh indexer
     │
     ▼
Wazuh dashboard
```

The indexer requires persistent storage, which is why this component belongs after Cinder CSI is available.

---

## 33. Suricata

The initial role is IDS rather than an inline IPS dataplane.

That is deliberate.

A monitoring sensor can be introduced without putting the entire network behind a new packet-forwarding control point on day one.

> **DESIGN CHOICE:** Establish visibility first; add inline enforcement only when the traffic architecture and failure/recovery procedure are understood.

---

# Part XV — Observability

## 34. Prometheus and Grafana

The intended observability stack is:

```text
Prometheus → metrics
Grafana    → dashboards
Loki       → logs
```

Targets include:

```text
Linux nodes
Kubernetes
Cilium
Slurm
applications
Hermes
workloads
```

### Important learning exercise

After Prometheus and Grafana are operational:

```text
rerun Cilium connectivity tests
             │
             ▼
watch the dashboards
             │
             ▼
correlate network events with metrics
```

This turns the connectivity test from a pass/fail command into an observability exercise.

---

# Part XVI — JupyterHub, Astro and research services

## 35. JupyterHub

The target user path is:

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

Research environments may expose:

```text
CPU
RAM
GPU
persistent storage
```

and libraries such as:

```text
PyTorch
PennyLane
Qiskit
Qiskit Aer
CUDA Quantum
custom research images
```

---

## 36. Astro end-to-end milestone

The first public application should be intentionally simple.

The target path is:

```text
Cloudflare
    │
    ▼
DNS
    │
    ▼
Ingress
    │
    ▼
Astro Service
    │
    ▼
Astro container
```

A simple public “hello” page is valuable because it proves all of the following at once:

```text
DNS
TLS / ingress
Kubernetes service
container scheduling
container networking
public routing
GitOps
```

Do this before adding sophisticated application behavior.

---

# Part XVII — Hermes

## 37. Hermes federation

The personal/federation Hermes stays outside Kubernetes:

```text
personal Hermes
      │
      ▼
hermes-orchestrator-01
      │
      ├── read/report infrastructure state
      └── coordinate future agents
```

The future research Hermes runs inside Kubernetes.

```text
Personal Hermes
      │
      ├── Infrastructure Hermes
      └── Research Hermes
```

> **SECURITY NOTE:** Do not give an orchestration agent unrestricted cluster-admin, root, Git-push and cloud credentials simultaneously. Build explicit capabilities with small, auditable permissions.

---

# Part XVIII — Final acceptance tests

## 38. Infrastructure

```bash
openstack server list
openstack network list
openstack port list
openstack security group list
```

## 39. Ansible

```bash
ansible-inventory -i inventories/private/hosts.yml --graph
ansible all -i inventories/private/hosts.yml -m ping
```

## 40. Edge

```bash
sudo nft list ruleset
sudo wg show
systemctl is-active haproxy
```

## 41. Runtime

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml -b -m shell -a \
  'systemctl is-active containerd; systemctl is-active kubelet; crictl info >/dev/null && echo CRI_OK'
```

## 42. Kubernetes

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw='/readyz?verbose'
```

## 43. Cilium

```bash
cilium status --wait
cilium connectivity test --debug
```

The current environment's acceptance milestone is:

```text
82 tests
780 actions
all successful
55 tests skipped
1 scenario skipped
```

## 44. Storage

```bash
kubectl get storageclass
kubectl get csidrivers
```

## 45. Slurm

```bash
sinfo
squeue
scontrol show nodes
```

---

# Part XIX — Troubleshooting method

## 46. Diagnose by layer

When something fails, classify it before changing anything.

```text
Cloud
  ↓
OpenStack networking / SG / port / route
  ↓
VM / OS
  ↓
service / systemd / SELinux
  ↓
TCP / UDP / Unix socket
  ↓
container runtime / CRI
  ↓
Kubernetes control plane
  ↓
CNI / datapath
  ↓
Service / application
```

### Useful first commands

```bash
# OpenStack
openstack server show <server>
openstack port show <port>
openstack security group rule list <group>

# Linux
systemctl --failed
journalctl -u <service> -b
getenforce

# Network
ip addr
ip route
ss -lntup
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

---

# Part XX — Known lessons from the build

## 47. Failures that became teaching material

### OpenStack flavor mismatch

A flavor name was supplied where a resource expected an ID.

**Lesson:** provider schemas matter more than intuition.

### Broken/stale Wazuh repository

An unrelated DNF failure was initially observed during system setup.

**Lesson:** repository configuration can poison unrelated package operations. Check enabled repositories before diagnosing a package as inherently broken.

### Suricata package availability

Suricata was not available in the desired form from the default repositories.

**Lesson:** understand repository provenance and dependency scope; add the minimum required repository sources rather than copying random package commands from the Internet.

### HAProxy SELinux denial

The HAProxy syntax was valid but the process was denied the required network operation.

**Lesson:** syntax validation and policy authorization are separate tests.

### `containerd` package naming

The expected runtime package was not available under the guessed name in the base Rocky repositories.

**Lesson:** the OS package ecosystem and upstream project naming are not always identical.

### CRI socket permission

`crictl` failed when run without sufficient privileges.

**Lesson:** a Unix socket permission error is not automatically a network error.

### Kubernetes API access

The API server was healthy directly, but access through the VIP initially failed because the load-balancer security group source scope was wrong.

**Lesson:** test each hop of the path:

```text
client
 → VIP
 → HAProxy
 → backend
 → kube-apiserver
```

### Cilium connectivity / NodePort

VXLAN health did not imply NodePort health.

**Lesson:** different protocols and ports represent different datapaths. Check the exact traffic the failing test requires.

---

# Part XXI — Production hardening still to do

This environment is an infrastructure lab and a controlled first platform. Before treating it as a production multi-user research service, review at least:

- HA for currently single-instance services
- backup and restore procedures
- OpenStack credential rotation
- stronger secret management
- Kubernetes certificate/key rotation policy
- network-policy defaults
- ingress/TLS hardening
- database HA and backups
- Cinder backup strategy
- Wazuh architecture sizing
- Prometheus/Grafana persistence and retention
- Slurm controller/database HA
- centralized logging retention
- public DNS and Cloudflare policy
- disaster-recovery tests
- account lifecycle and RBAC
- least-privilege Hermes capabilities

> **WARNING:** “The cluster is healthy” and “the platform is production-ready” are not the same statement.

---

# Part XXII — Final security gate

The project intentionally does **not** remove public SSH access immediately after the VPN works.

Do not remove the public TCP/22 path until all of these are true:

```text
WireGuard access works
        │
        ▼
private nodes reachable
        │
        ▼
nyameko admin SSH works
        │
        ▼
rocky recovery path tested
        │
        ▼
final Astro/public application milestone complete
        │
        ▼
public TCP/22 can be removed safely
```

This is a real operational dependency, not merely a documentation preference.

---

# References

## Core infrastructure

- [OpenStack Documentation](https://docs.openstack.org/)
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Rocky Linux](https://docs.rockylinux.org/)

## Kubernetes

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [CRI](https://kubernetes.io/docs/concepts/architecture/cri/)

## Networking and security

- [Cilium](https://docs.cilium.io/)
- [Cilium kubeadm installation](https://docs.cilium.io/en/latest/installation/k8s-install-kubeadm/)
- [Cilium network policy](https://docs.cilium.io/en/stable/security/policy/)
- [Hubble](https://docs.cilium.io/en/stable/observability/hubble/intro/)
- [WireGuard](https://www.wireguard.com/)
- [nftables Wiki](https://wiki.nftables.org/)
- [Suricata](https://suricata.io/documentation/)
- [Wazuh](https://documentation.wazuh.com/)
- [Pi-hole](https://docs.pi-hole.net/)

## Platform services

- [Cinder](https://docs.openstack.org/cinder/latest/)
- [Argo CD](https://argo-cd.readthedocs.io/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [JupyterHub](https://jupyterhub.readthedocs.io/)
- [Slurm](https://slurm.schedmd.com/)
- [Astro](https://docs.astro.build/)

---

# Documentation maintenance rule

The documentation should follow the code, not the other way around.

When infrastructure changes:

```text
1. change code
2. validate deployment
3. update installation procedure
4. update quick guide if commands changed
5. update README if architecture changed
6. add/extend a tutorial when there is a useful teaching lesson
```

Do not preserve obsolete architecture in documentation merely because an earlier design looked cleaner.
