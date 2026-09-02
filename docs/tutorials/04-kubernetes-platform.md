# 4. Kubernetes Platform

This tutorial documents the Kubernetes platform in `infra-hpc-qc-k8s`, including the implementation decisions, validation steps, failures, and fixes encountered during the deployment of the six-node cluster.

The goal is not only to reproduce a working cluster, but to show how to diagnose the kinds of problems that commonly appear when Kubernetes is deployed on Rocky Linux inside OpenStack.

## 4.1 Platform topology

The current Kubernetes platform consists of:

```text
                         WireGuard
                            │
                            ▼
                    10.51.0.100:6443
                         HAProxy
                            │
               ┌────────────┼────────────┐
               │            │            │
               ▼            ▼            ▼
          CP1 10.51.0.11 CP2 .12      CP3 .13
               │            │            │
               └────────────┼────────────┘
                            │
                    Kubernetes API
                            │
                    stacked etcd
                            │
             ┌──────────────┼──────────────┐
             ▼              ▼              ▼
       worker-01 .21  worker-02 .22  worker-03 .23
```

Networks:

| Network | CIDR | Purpose |
|---|---|---|
| Management | `10.50.0.0/24` | OpenStack management/service traffic |
| Kubernetes | `10.51.0.0/24` | Kubernetes API and node-to-node traffic |
| VPN | `10.60.0.0/24` | WireGuard administrative access |

The Kubernetes API endpoint is deliberately stable:

```text
10.51.0.100:6443
```

Clients should use this address for the life of the cluster regardless of whether HAProxy is eventually replaced by Octavia.

## 4.2 Infrastructure ownership

The platform uses explicit ownership boundaries:

```text
Terraform
   │
   └── OpenStack infrastructure
       ├── networks
       ├── ports
       ├── security groups
       └── virtual machines

Ansible
   │
   ├── Rocky Linux configuration
   ├── containerd
   ├── Kubernetes prerequisites
   ├── HAProxy
   └── Kubernetes bootstrap

kubeadm
   │
   ├── control-plane initialization
   ├── control-plane joins
   └── worker joins

Cilium
   │
   └── Kubernetes networking / eBPF datapath

Argo CD
   │
   └── application delivery and GitOps
```

This distinction is important for students: Kubernetes does not provision the OpenStack VMs, and kubeadm does not replace Ansible. kubeadm performs Kubernetes bootstrap; Ansible orchestrates that bootstrap.

## 4.3 Kubernetes prerequisites

All six Kubernetes nodes must first receive:

- containerd
- kubelet
- kubeadm
- kubectl
- cri-tools
- kernel modules required by Kubernetes
- Kubernetes sysctl settings
- the Kubernetes package repository

The authoritative playbook is:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-prereqs.yml
```

The playbook applies:

```text
containerd
   │
   ├── containerd.io
   ├── /etc/containerd/config.toml
   └── SystemdCgroup = true

Kubernetes prerequisites
   │
   ├── overlay
   ├── br_netfilter
   ├── net.bridge.bridge-nf-call-iptables = 1
   ├── net.bridge.bridge-nf-call-ip6tables = 1
   └── net.ipv4.ip_forward = 1

Kubernetes packages
   │
   ├── kubelet
   ├── kubeadm
   ├── kubectl
   └── cri-tools

CRI
   │
   └── /etc/crictl.yaml
```

Containerd uses the systemd cgroup driver because it matches kubelet and is the recommended Kubernetes configuration for modern systemd-based Linux hosts.

## 4.4 First deployment failure: `containerd` package not found

The first attempt used:

```yaml
- name: Install containerd
  ansible.builtin.dnf:
    name: containerd
```

This failed on Rocky Linux 9:

```text
No package containerd available.
```

The problem was not Kubernetes. Rocky's configured repositories did not provide a package with that name.

The role was corrected to use Docker's EL9 repository and the `containerd.io` package.

The successful deployment now reports:

```text
containerd containerd v2.3.4
```

on all six nodes.

The lesson is important: package names and package repositories are distribution-specific. Do not assume that the upstream project name is also the OS package name.

## 4.5 containerd configuration

The containerd role generates the default configuration and enables the systemd cgroup driver.

Validation:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -m shell \
  -a 'containerd --version && systemctl is-active containerd'
```

Expected:

```text
containerd containerd v2.3.4 ...
active
```

The role also configures:

```text
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
```

in `/etc/crictl.yaml`.

## 4.6 CRI validation and a misleading permission error

A later test was run with:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -m shell \
  -a 'systemctl is-active containerd; systemctl is-active kubelet; crictl info >/dev/null && echo CRI_OK'
```

This failed with:

```text
connect: permission denied
```

The initial suspicion was an OpenStack security-group problem.

It was not.

`/run/containerd/containerd.sock` is a privileged Unix-domain socket. The ad-hoc Ansible command was executed as the normal `nyameko` user, without `become`.

The correct diagnostic is:

```bash
sudo crictl info
```

or:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -b \
  -m shell \
  -a 'crictl info >/dev/null && echo CRI_OK'
```

The `kube_prereqs` role already performs the CRI verification with privilege escalation, so the successful prerequisite play showed that the runtime itself was healthy.

General lesson:

> A local Unix-socket permission failure is not the same thing as a network ACL/security-group failure.

Always identify whether the endpoint is TCP/UDP or a local Unix socket before debugging network policy.

## 4.7 Kubernetes version

The deployed Kubernetes version is:

```text
v1.36.4
```

The cluster nodes now report:

```text
Kubernetes v1.36.4
containerd://2.3.4
```

The repository should avoid maintaining unused duplicate version variables. The installed versions should be represented by the variables that actually drive the package repository/bootstrap configuration.

## 4.8 API load balancer

The Kubernetes API is exposed through:

```text
10.51.0.100:6443
```

HAProxy runs on `api-lb-01`.

The HAProxy backend is:

```text
CP1 → 10.51.0.11:6443
CP2 → 10.51.0.12:6443
CP3 → 10.51.0.13:6443
```

The HAProxy listener can exist before Kubernetes is initialized. At that point its backend health checks are expected to fail.

Example early state:

```text
HAProxy: UP
CP1: DOWN
CP2: DOWN
CP3: DOWN
```

This is not a failure of HAProxy.

Once the control planes come online:

```text
HAProxy: UP
CP1: UP
CP2: UP
CP3: UP
```

## 4.9 HAProxy SELinux failure

The initial HAProxy deployment failed even though:

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg
```

reported:

```text
Configuration file is valid
```

The real runtime error was:

```text
cannot bind socket (Permission denied) for [10.51.0.100:6443]
```

Inspection showed:

```text
SELinux: Enforcing
haproxy_connect_any --> off
```

The fix was:

```bash
sudo setsebool -P haproxy_connect_any on
```

The fix was then codified in the `api_lb_haproxy` Ansible role using `ansible.posix.seboolean`.

After the fix:

```text
haproxy.service: active (running)
10.51.0.100:6443: LISTEN
```

The lesson is important on Rocky/RHEL-family systems:

> A syntactically valid service configuration can still be blocked by SELinux at runtime.

## 4.10 API security-group model

The intended security model is:

```text
api-lb
  TCP 6443 ← vpn_cidr
  TCP 6443 ← k8s_cidr

k8s-control-plane
  TCP 6443 ← k8s_cidr
```

The direct VPN-to-control-plane API rule is intentionally not required.

This means:

```text
VPN client
   │
   ▼
10.51.0.100:6443
   │
   ▼
HAProxy
   │
   ├── CP1
   ├── CP2
   └── CP3
```

rather than exposing the individual control-plane API listeners to VPN clients.

This concentrates the API entry point around one stable endpoint and makes the HAProxy layer a genuine security and availability boundary.

## 4.11 kubeadm initialization

The first control plane is:

```text
k8s-cp-01 = 10.51.0.11
```

The cluster uses:

```text
Control-plane endpoint: 10.51.0.100:6443
Pod CIDR:               10.244.0.0/16
Service CIDR:           10.96.0.0/12
```

The conceptual kubeadm configuration is:

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 10.51.0.11
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock

---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.36.4
controlPlaneEndpoint: "10.51.0.100:6443"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
```

The CP1 initialization succeeded.

The API server was healthy directly on:

```text
10.51.0.11:6443
```

and subsequently through HAProxy:

```bash
curl -k https://10.51.0.100:6443/healthz
```

returned:

```text
ok
```

## 4.12 Bootstrap token, CA hash and certificate key

Additional control planes and workers require temporary bootstrap information.

The deployment generates:

```text
kubeadm token
CA discovery hash
control-plane certificate key
```

These are deliberately not stored in Git, Vault, Terraform state, or persistent inventory.

The worker join form is:

```text
kubeadm join 10.51.0.100:6443 \
  --token ... \
  --discovery-token-ca-cert-hash sha256:...
```

The control-plane join additionally includes:

```text
--control-plane
--certificate-key ...
```

The CA discovery hash is not permanent state. It can be derived again from the Kubernetes CA certificate.

The bootstrap token is temporary and can be generated again.

The uploaded control-plane certificates are temporary and can be re-uploaded when necessary.

This is installation-time state, not long-lived infrastructure configuration.

## 4.13 Ansible cluster bootstrap

The Kubernetes lifecycle is intentionally represented by two playbooks:

```text
playbooks/
├── kubernetes-prereqs.yml
└── kubernetes.yml
```

The cluster playbook orchestrates:

```text
CP1
 │
 ├── initialize if not already initialized
 │
 ├── configure kubectl
 │
 └── generate temporary join information
        │
        ├── CP2
        ├── CP3
        │
        ├── worker-01
        ├── worker-02
        └── worker-03
```

Additional control-plane and worker joins are performed one at a time.

The join roles use:

```text
/etc/kubernetes/kubelet.conf
```

as an idempotence guard.

This allows the playbook to be safely rerun without attempting to join an already joined node.

## 4.14 First full automated cluster deployment

The cluster was successfully assembled with:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes.yml
```

The result:

```text
k8s-cp-01       v1.36.4
k8s-cp-02       v1.36.4
k8s-cp-03       v1.36.4
k8s-worker-01   v1.36.4
k8s-worker-02   v1.36.4
k8s-worker-03   v1.36.4
```

The control planes each have:

```text
etcd
kube-apiserver
kube-controller-manager
kube-scheduler
```

running as static pods.

## 4.15 Cluster validation

At this stage, the cluster API is healthy but all nodes are expected to be `NotReady` because no CNI has been installed yet.

Validation:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl cluster-info
kubectl get --raw='/readyz?verbose'
```

The current successful state before Cilium is:

```text
All six nodes registered
All three etcd members running
All three API servers running
All three controller managers running
All three schedulers running
All six kube-proxy pods running
CoreDNS pending
Nodes NotReady
```

`kubectl cluster-info` reports the API endpoint:

```text
https://10.51.0.100:6443
```

The API `/readyz` endpoint reports all checks healthy.

This demonstrates an important Kubernetes distinction:

```text
Kubernetes API healthy
        ≠
Kubernetes cluster networking ready
```

The latter requires a CNI.

## 4.16 HAProxy validation after Kubernetes bootstrap

The load balancer logs showed all three control planes transitioning from:

```text
DOWN
```

to:

```text
UP
```

For example:

```text
Server kubernetes-control-plane/cp1 is UP
Server kubernetes-control-plane/cp2 is UP
Server kubernetes-control-plane/cp3 is UP
```

Requests are now distributed across all three control planes.

This validates both:

1. the OpenStack security path
2. the HAProxy backend configuration

and proves that the API endpoint is genuinely highly available rather than merely being a VIP pointed at a single node.

## 4.17 Kubernetes state before Cilium

The expected state is:

```text
etcd                         Running
kube-apiserver               Running
kube-controller-manager      Running
kube-scheduler               Running
kube-proxy                   Running
CoreDNS                      Pending
Nodes                        NotReady
```

Do not interpret the `NotReady` state as a failed kubeadm deployment.

The next component is the CNI.

## 4.18 Cilium

Cilium is the selected Kubernetes CNI.

It provides:

- pod networking
- service networking
- NetworkPolicy enforcement
- eBPF-based datapath
- network observability
- Hubble integration

The current stable Cilium release is `1.20.1`, and Cilium documents Kubernetes 1.36 as tested and supported.

Cilium system requirements include Linux kernel >= 5.10, and the Rocky Linux 9 kernel used by this cluster satisfies that baseline.

### OpenStack networking requirements

The current OpenStack security-group model must additionally allow the Cilium overlay traffic between Kubernetes nodes.

With Cilium's default VXLAN overlay:

```text
UDP 8472 ← k8s_cidr
```

must be allowed among Kubernetes nodes.

For Cilium health monitoring:

```text
TCP 4240 ← k8s_cidr
```

should also be allowed.

These rules belong in the Kubernetes node security groups, not in the edge nftables policy.

### Initial Cilium mode

The initial deployment intentionally retains kube-proxy:

```text
Kubernetes
   │
   ├── kube-proxy
   └── Cilium
```

Kube-proxy replacement, native routing, Hubble tuning, encryption and other advanced datapath features should be introduced deliberately rather than all at once.

### Install and validate

Cilium's official Helm installation is:

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.20.1 \
  --namespace kube-system
```

After deployment:

```bash
kubectl -n kube-system get pods -o wide
kubectl get nodes
cilium status --wait
```

The official Cilium validation also provides a connectivity test:

```bash
cilium connectivity test
```

A successful connectivity test validates pod-to-pod, service and policy paths rather than only proving that the Cilium pods themselves are running.

## 4.19 Cilium troubleshooting

If Cilium pods are running but cross-node networking fails, check the OpenStack security group first:

```text
UDP 8472 between Kubernetes nodes
TCP 4240 between Kubernetes nodes
```

Then inspect:

```bash
cilium status
cilium connectivity test
kubectl -n kube-system get pods -o wide
kubectl -n kube-system logs ds/cilium
```

Do not immediately switch to kube-proxy replacement, native routing or other advanced settings. First establish the default overlay datapath.

## 4.20 After Cilium

The target state becomes:

```text
6/6 nodes Ready
CoreDNS Running
Cilium agents Running on all nodes
Cilium operator Running
kube-proxy Running
API HA healthy
```

Only after this point should application infrastructure be introduced.

The planned sequence is:

```text
Cilium
   ↓
Cinder CSI / OpenStack Cloud Controller Manager
   ↓
Argo CD
   ↓
Prometheus
   ↓
Grafana
   ↓
Slurm integration
   ↓
Hermes Orchestrator
   ↓
Hermes Researcher
   ↓
JupyterHub
   ↓
Astro
```

Storage-dependent services such as PostgreSQL, Wazuh indexer, Jupyter user data and application state should wait until Cinder CSI is operational.

## 4.21 Lessons from the deployment

### Package assumptions

`containerd` and `containerd.io` are not interchangeable package names.

### SELinux

A valid configuration file does not prove a service can bind its socket.

### OpenStack security groups

A timeout to a private TCP endpoint can be a cloud firewall problem even when the service is healthy.

### Unix sockets

A `permission denied` error on `/run/containerd/containerd.sock` is a local Unix permission problem, not an OpenStack security-group problem.

### Bootstrap credentials

Kubeadm tokens, CA discovery hashes and temporary certificate keys are operational bootstrap material, not permanent configuration.

### Idempotence

The Kubernetes playbook detects already-initialized or already-joined nodes rather than rebuilding them.

### Layered validation

A successful deployment was verified at several layers:

```text
OpenStack
   ↓
VM/network reachability
   ↓
HAProxy listener
   ↓
HAProxy backends
   ↓
kubeadm control plane
   ↓
etcd
   ↓
Kubernetes API
   ↓
node registration
   ↓
CNI
```

This layered model is the recommended troubleshooting approach for future students and collaborators.

## 4.22 Current state

At the completion of this stage:

```text
✓ OpenStack networks and VMs
✓ Rocky Linux base configuration
✓ Edge / WireGuard / Pi-hole
✓ Wazuh manager
✓ Suricata IDS
✓ Kubernetes API load balancer
✓ HAProxy SELinux configuration
✓ containerd 2.3.4
✓ Kubernetes 1.36.4 prerequisites
✓ CP1 kubeadm initialization
✓ CP2 control-plane join
✓ CP3 control-plane join
✓ Worker joins
✓ Kubernetes API HA
→ Cilium
→ Cinder CSI
→ Argo CD
→ Prometheus / Grafana
→ Slurm
→ Hermes Orchestrator
→ Hermes Researcher
→ JupyterHub
→ Astro
```

## 4.23 References

- Kubernetes kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- Kubernetes high availability with kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- Kubernetes container runtimes: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- Kubernetes ports and protocols: https://kubernetes.io/docs/reference/networking/ports-and-protocols/
- Cilium Helm installation: https://docs.cilium.io/en/stable/installation/k8s-install-helm/
- Cilium compatibility: https://docs.cilium.io/en/stable/network/kubernetes/compatibility/
- Cilium system requirements: https://docs.cilium.io/en/stable/operations/system_requirements/
