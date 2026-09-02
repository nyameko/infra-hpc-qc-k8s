# Tutorial 4 — Kubernetes Platform: Cilium and Worked Network-Security Debugging

## 1. Purpose

Tutorial 4 begins after the six-node Kubernetes cluster has been bootstrapped and turns it into a functional platform.

This tutorial is intentionally an incident-driven lab. The target is not merely:

```text
"Cilium installed"
```

The target is:

```text
control plane healthy
+ node networking healthy
+ service networking healthy
+ cross-node connectivity healthy
+ security boundaries still restrictive
```

The deployment exposed a particularly useful real-world failure: Cilium itself became healthy, VXLAN worked, but the Cilium connectivity test failed at a Kubernetes NodePort because the OpenStack security groups did not yet permit the NodePort range. The same testing also exposed ICMP host-health behavior.

---

## 2. Starting state

Kubernetes:

```text
v1.36.4
```

Nodes:

```text
CP1 10.51.0.11
CP2 10.51.0.12
CP3 10.51.0.13
W1  10.51.0.21
W2  10.51.0.22
W3  10.51.0.23
```

API endpoint:

```text
10.51.0.100:6443
```

Runtime:

```text
containerd 2.3.4
```

---

## 3. Baseline Kubernetes validation

Before Cilium, verify:

```bash
kubectl cluster-info
kubectl get --raw='/readyz?verbose'
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
```

The expected pre-CNI state is:

```text
control-plane components → Running
kube-proxy              → Running
CoreDNS                 → Pending
nodes                   → NotReady
```

That `NotReady` condition is expected until a CNI is installed.

---

## 4. HAProxy validation

The API load balancer should be listening:

```bash
sudo systemctl is-active haproxy
sudo ss -ltnp | grep ':6443'
```

And the backend history should show:

```text
cp1 UP
cp2 UP
cp3 UP
```

This proves that the endpoint used by kubeconfig is backed by three live API servers.

The repository history records the transition from initial API-LB debugging to a working three-backend configuration. citeturn154630view0

---

## 5. Cilium baseline

The first installation deliberately keeps kube-proxy.

```text
Cilium 1.20.1
kube-proxy replacement: false
VXLAN: enabled
IPv4: enabled
```

This is the simplest good baseline for the existing kubeadm cluster.

The live Cilium output from the deployment showed:

```text
Kubernetes: Ok 1.36 (v1.36.4)
Cilium: Ok 1.20.1
KubeProxyReplacement: False
Routing: Tunnel [vxlan]
```

Six Cilium agents, six Envoy DaemonSet pods, and one operator were all healthy.

---

## 6. Install Cilium

The CLI used during the deployment was:

```text
cilium-cli v0.20.0
```

and the cluster image version was:

```text
v1.20.1
```

The baseline installation was:

```bash
cilium install 1.20.1
```

Then:

```bash
cilium status --wait
```

The successful state was:

```text
Cilium:             OK
Operator:           OK
Envoy DaemonSet:    OK
Desired: 6
Ready:   6/6
```

CoreDNS moved from `Pending` to `Running` as Cilium became available.

---

## 7. Cilium architecture in this deployment

The baseline looks like:

```text
Kubernetes
   │
   ├── kube-proxy
   │
   └── Cilium
         │
         ├── CNI
         ├── eBPF datapath
         ├── service handling
         └── NetworkPolicy
```

Cilium's ClusterPool IPAM currently allocated pod addresses from its own pool, observed as:

```text
10.0.0.0/24
```

This must not be confused with the kubeadm `--pod-network-cidr` value:

```text
10.244.0.0/16
```

Those address spaces represent different layers of the deployment.

---

## 8. Cilium node-to-node transport

The current status showed:

```text
Routing: Network: Tunnel [vxlan]
tunnel-port: 8472
```

Therefore Kubernetes nodes need:

```text
UDP 8472 ← k8s_cidr
```

The local socket check was:

```bash
sudo ss -lunp | grep 8472
```

A node showed:

```text
0.0.0.0:8472
[::]:8472
```

UDP reachability tests from CP1 reached every Kubernetes node.

This established that VXLAN itself was not the remaining problem.

---

## 9. Cilium health transport

Cilium health uses:

```text
TCP 4240
```

and host-level health tests can also use ICMP.

Therefore the Kubernetes OpenStack security groups permit:

```text
TCP 4240 ← k8s_cidr
ICMP      ← k8s_cidr
```

This distinction became important later: the Cilium agent could be reached by HTTP while ICMP to the node stack still timed out.

---

# Worked Example — Debugging the Cilium connectivity test

## 10. Run the real connectivity test

After Cilium reports healthy:

```bash
cilium connectivity test --debug
```

The test creates workloads that validate:

- same-node connectivity
- cross-node connectivity
- service discovery
- DNS
- ClusterIP
- NodePort
- NetworkPolicy
- L7 behavior

Do not accept `cilium status` alone as proof of a healthy platform.

---

## 11. The failure we actually encountered

The test advanced through the normal deployment stages, including:

```text
Cilium agents
CoreDNS
same-node endpoints
cross-node endpoints
ClusterIP
```

and then failed at:

```text
NodePort 10.51.0.12:31196
```

In an earlier run it failed against CP1; in the later debug run it selected CP2. The exact node is not important.

The important value is:

```text
31196
```

---

## 12. First hypothesis: VXLAN

Because this is a Cilium test, an obvious suspicion is:

```text
cross-node test fails
    ↓
VXLAN is blocked
```

But the deployment had already established:

```text
UDP 8472 is present
UDP 8472 reaches all Kubernetes nodes
Cilium agents are healthy
```

The correct response was therefore **not** to keep changing Cilium configuration.

Instead, identify the port.

---

## 13. Identify the NodePort

Kubernetes NodePorts use the default range:

```text
30000-32767
```

Therefore:

```text
31196
```

is a Kubernetes NodePort.

The test path is roughly:

```text
client pod
   ↓
node IP:31196
   ↓
kube-proxy NodePort
   ↓
Kubernetes service
   ↓
pod
```

VXLAN port 8472 and NodePort 31196 are completely different traffic paths.

---

## 14. OpenStack security-group fix

The Kubernetes node security groups therefore need:

```text
TCP 30000-32767 ← k8s_cidr
UDP 30000-32767 ← k8s_cidr
```

for both:

```text
k8s-control-plane
k8s-worker
```

Example Terraform:

```hcl
resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_tcp_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_tcp_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_udp_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_udp_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}
```

The source is intentionally restricted to:

```text
10.51.0.0/24
```

We do **not** expose NodePorts to `0.0.0.0/0`.

The NodePort/ICMP rules were subsequently committed as a dedicated infrastructure change, preserving the iteration in Git history. citeturn409697view4

---

## 15. Add ICMP for node-health diagnostics

The Cilium debug output also showed:

```text
Host connectivity to node IP:
  ICMP to stack: Connection timed out
  HTTP to agent: OK
```

That is an important teaching result.

The agent is alive, but a lower-level health probe is blocked.

Permit:

```text
ICMP ← k8s_cidr
```

on both Kubernetes security groups.

A minimal Terraform example is:

```hcl
resource "openstack_networking_secgroup_rule_v2" "k8s_icmp_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_icmp_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}
```

This change was made as a separate committed iteration after the Cilium baseline. citeturn409697view4

---

## 16. Final Kubernetes SG model

The Kubernetes security-group design is now conceptually:

### Control plane

```text
SSH 22              ← mgmt_cidr
API 6443            ← k8s_cidr
etcd 2379-2380      ← k8s_cidr
kubelet 10250       ← k8s_cidr
VXLAN UDP 8472      ← k8s_cidr
health TCP 4240     ← k8s_cidr
ICMP                ← k8s_cidr
NodePort TCP 30000-32767 ← k8s_cidr
NodePort UDP 30000-32767 ← k8s_cidr
```

### Worker

```text
SSH 22              ← mgmt_cidr
kubelet 10250       ← k8s_cidr
VXLAN UDP 8472      ← k8s_cidr
health TCP 4240     ← k8s_cidr
ICMP                ← k8s_cidr
NodePort TCP 30000-32767 ← k8s_cidr
NodePort UDP 30000-32767 ← k8s_cidr
```

The API load balancer separately allows:

```text
6443/tcp ← vpn_cidr
6443/tcp ← k8s_cidr
```

The individual control planes do not expose their API directly to VPN clients.

---

## 17. Why these rules do not belong in edge nftables

The edge firewall protects:

```text
edge 10.50.0.10
```

The OpenStack Kubernetes SG protects:

```text
10.51.0.11
10.51.0.12
10.51.0.13
10.51.0.21
10.51.0.22
10.51.0.23
```

Therefore NodePort, VXLAN and Kubernetes health rules are cloud-network rules for the Kubernetes VMs.

Do not turn the edge nftables template into a giant shared policy for every service in the environment.

---

## 18. Cilium diagnostics

Useful commands:

```bash
cilium status --wait
```

```bash
kubectl -n kube-system get ciliumnodes
```

```bash
kubectl -n kube-system get pods -o wide
```

```bash
kubectl -n kube-system exec ds/cilium -- \
  cilium-dbg status --verbose
```

The successful baseline showed:

```text
Kubernetes: Ok
Cilium: Ok 1.20.1
KubeProxyReplacement: False
Routing: Tunnel [vxlan]
Controller Status: 28/28 healthy
```

The same report also showed the health discrepancy described above, which made it useful evidence rather than merely a status screen.

---

## 19. Re-run the connectivity test after every network change

After Terraform changes:

```bash
terraform plan
terraform apply
```

then:

```bash
cilium connectivity test --debug
```

The exact failing test is more important than a generic "Cilium failed" message.

A port such as `31196` should be translated back to the subsystem that owns it.

---

## 20. Deferred Cilium features

The project intentionally starts with:

```text
kube-proxy replacement = false
Hubble Relay            = disabled
ClusterMesh             = disabled
```

That is not an unfinished baseline. It is sequencing.

### Hubble

Hubble should be introduced soon because it is the observability layer we want for:

- flow visibility
- policy troubleshooting
- service paths
- security demonstrations

### kube-proxy replacement

Later, we can deliberately repeat the cluster exercise with kube-proxy replacement and compare the datapath.

It is not a good emergency fix for the current NodePort failure.

### ClusterMesh

ClusterMesh becomes useful when multiple Kubernetes clusters need to communicate. It is not required to make this single cluster healthy.

---

## 21. Educational observability exercise

After Prometheus and Grafana are deployed, repeat:

```bash
cilium connectivity test
```

while actively watching the dashboards.

The exercise should correlate:

```text
connectivity test
   ↓
Cilium flows
   ↓
packet/service behavior
   ↓
Prometheus metrics
   ↓
Grafana dashboards
```

Students should observe how a functional connectivity test maps to metrics and network events.

This is intentionally a later exercise; the baseline should be stable first.

---

## 22. Current platform checkpoint

```text
✓ OpenStack network and VMs
✓ Rocky Linux base configuration
✓ Edge / WireGuard / Pi-hole
✓ Wazuh manager
✓ Suricata IDS
✓ Kubernetes API load balancer
✓ HAProxy SELinux configuration
✓ containerd 2.3.4
✓ Kubernetes 1.36.4 prerequisites
✓ kubeadm control-plane bootstrap
✓ 3 control planes
✓ 3 workers
✓ kube-proxy
✓ Cilium 1.20.1
✓ Cilium VXLAN baseline
✓ NodePort security-group iteration
✓ ICMP node-health security-group iteration
→ Cinder CSI
→ Argo CD
→ Prometheus / Grafana
→ Slurm
→ Hermes Orchestrator
→ Hermes Researcher
→ JupyterHub
→ Astro
```

---

## References

- Kubernetes networking: https://kubernetes.io/docs/concepts/cluster-administration/networking/
- Kubernetes Services / NodePort: https://kubernetes.io/docs/concepts/services-networking/service/
- Kubernetes ports: https://kubernetes.io/docs/reference/networking/ports-and-protocols/
- Cilium installation: https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/
- Cilium Helm: https://docs.cilium.io/en/stable/installation/k8s-install-helm/
- Cilium system requirements: https://docs.cilium.io/en/stable/operations/system_requirements/
- Cilium routing: https://docs.cilium.io/en/stable/network/concepts/routing/
- Cilium Hubble: https://docs.cilium.io/en/stable/observability/hubble/
- Cilium kube-proxy replacement: https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/
- Cilium ClusterMesh: https://docs.cilium.io/en/stable/network/clustermesh/
