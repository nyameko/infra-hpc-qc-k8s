# Tutorial 2 — Networking, Edge Security and Security-Groups

## 1. Purpose

This tutorial builds the network and security model used by the platform and records the debugging lessons that emerged while implementing it.

The key idea is defense in depth:

```text
Cloud network boundary
        ↓
OpenStack security groups
        ↓
Host boundary
        ↓
nftables
        ↓
Administrative identity
        ↓
WireGuard
        ↓
Cluster boundary
        ↓
Cilium
```

The layers overlap in protection, but they should not duplicate ownership.

---

## 2. Canonical networks

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr: 10.51.0.0/24
vpn_cidr: 10.60.0.0/24
```

These names were standardised after earlier iterations used variants such as `management_cidr` and `wireguard_cidr`.

Do not create synonyms. Variable naming drift creates failures that look like service failures but are really inventory-resolution failures.

The current repository tutorial explicitly treats these three names as canonical. citeturn768666view0

---

## 3. OpenStack security groups versus nftables

OpenStack security groups apply before traffic reaches the guest OS. nftables runs inside the guest.

```text
packet
  ↓
OpenStack SG
  ↓
VM NIC
  ↓
nftables
  ↓
service
```

Therefore a connection timeout to a VM can be caused by an OpenStack rule even when the service itself is healthy.

Likewise, a packet can pass the cloud SG and still be rejected by the guest firewall.

The practical teaching rule is:

> Always identify which layer owns the traffic path before changing a firewall rule.

---

## 4. Edge nftables

The edge host uses a default-drop input and forwarding policy:

```nft
chain input {
    policy drop;
}

chain forward {
    policy drop;
}

chain output {
    policy accept;
}
```

Stateful return traffic is accepted with:

```nft
ct state established,related accept
```

The edge firewall permits only its own responsibilities:

- WireGuard UDP 51820.
- temporary bootstrap SSH.
- VPN SSH.
- internal DNS.
- Wazuh agent traffic.
- VPN forwarding/NAT.

Kubernetes API, VXLAN and NodePort rules do not belong in the edge firewall because those traffic paths terminate on Kubernetes VMs.

The repository's current networking tutorial makes the same ownership distinction. citeturn768666view0

---

## 5. WireGuard

WireGuard provides the administrative entry path:

```text
10.60.0.2/32   workstation
       │
       ▼
10.60.0.1/24   edge
       │
       ▼
private networks
```

The workstation uses split routing:

```text
AllowedIPs =
  10.50.0.0/24,
  10.51.0.0/24,
  10.60.0.0/24
```

Normal Internet traffic remains local to the workstation.

The server's private key is generated on `edge` and remains there. The client private key remains on the client. Public keys may be exchanged; private keys must never enter Git.

---

## 6. Temporary SSH lifecycle

During bootstrap, a temporary public rule is intentionally retained:

```text
bootstrap_ssh_cidr → edge:22
```

Once WireGuard and recovery have been verified:

```text
public TCP/22  → remove
VPN TCP/22     → retain
```

This is a deployment checkpoint rather than an early hardening exercise. Removing it too early can lock out the operator while infrastructure is still changing.

---

## 7. Pi-hole

Pi-hole belongs on edge because DNS is infrastructure.

The intended architecture is:

```text
Kubernetes pod
      ↓
CoreDNS
      ↓
10.50.0.10:53
      ↓
Pi-hole
      ↓
upstream DNS
```

DNS is not exposed publicly. Only management, Kubernetes and VPN networks should reach it.

### Worked failure: Podman short image name

The initial Quadlet configuration used:

```text
pihole/pihole:latest
```

The systemd-launched Podman service could not resolve that short image name non-interactively.

The corrected form was:

```text
docker.io/pihole/pihole:latest
```

Lesson:

> Infrastructure services should use explicit image registries, especially when started by non-interactive systemd units.

---

## 8. Wazuh

Wazuh is deliberately staged:

```text
now:
other VMs → Wazuh agents → edge manager

later:
manager → Kubernetes indexer → Kubernetes dashboard
```

A stale/broken Wazuh repository initially caused unrelated DNF failures. Removing the bad repository and checking `dnf repolist` isolated the problem.

The corrected Wazuh repository is the 4.x channel rather than the broken earlier path.

Lesson:

> Package-manager failures may come from an unrelated enabled repository. Inspect repositories before assuming the named package is broken.

The repository history records the dedicated Wazuh fix. citeturn154630view0

---

## 9. Suricata

Suricata is deployed IDS-first.

The Rocky repositories did not provide the required package directly, so EPEL, CRB and the OISF COPR were used.

Inline IPS was intentionally deferred.

That decision illustrates a broader rule:

> Measure a traffic path before placing a blocking control inline.

An untested IPS can turn an infrastructure problem into a complete outage.

---

## 10. SSH and user management

The bootstrap identity is `rocky`; the normal administrator is `nyameko`.

Ansible creates `nyameko`, installs the SSH public key, and configures passwordless sudo.

Private VM SSH is routed through the edge bastion with `ProxyJump`.

This gives the project an explicit recovery hierarchy instead of mixing bootstrap and long-term administration.

---

## 11. Kubernetes API security boundary

The API load balancer is:

```text
10.51.0.100:6443
```

Desired OpenStack security rules:

```text
api-lb
  6443/tcp ← vpn_cidr
  6443/tcp ← k8s_cidr

k8s-control-plane
  6443/tcp ← k8s_cidr
```

The direct:

```text
vpn_cidr → control-plane:6443
```

rule was explicitly removed.

This forces API access through the single HA entry point rather than exposing each control plane independently.

The repository records that security-boundary change in commit history. citeturn409697view9turn154630view6

---

## 12. Worked failure: HAProxy security group

Initial state:

```text
HAProxy listener: working
kube-apiserver on CP1: working
CP1 → VIP: timeout
```

The first investigation correctly checked whether the VM actually had:

```text
10.51.0.100/24
```

and whether anything else occupied port 6443.

The service and socket were valid, but the OpenStack `api-lb` security group allowed the API port from the wrong subnet.

The rule was corrected to:

```text
6443/tcp ← k8s_cidr
```

After the Terraform change:

```bash
nc -zv 10.51.0.100 6443
curl -k https://10.51.0.100:6443/healthz
```

returned success.

Lesson:

```text
service healthy
+ listener healthy
+ connection timeout
= investigate the network boundary
```

---

## 13. Worked failure: HAProxy and SELinux

The HAProxy configuration passed:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

but systemd failed to start it:

```text
cannot bind socket (Permission denied)
```

The diagnosis was:


```bash
getenforce
getsebool haproxy_connect_any
```

which showed SELinux enforcing and:

```text
haproxy_connect_any --> off
```

The supported correction was:

```bash
sudo setsebool -P haproxy_connect_any on
```

The Ansible role was then updated to make that setting persistent.

Lesson:

> Syntax validation is not runtime authorization.

A service must pass configuration parsing, systemd startup, socket binding, network policy and SELinux policy checks.

This was captured as a specific repository fix. citeturn154630view0

---

## 14. Kubernetes node traffic

The Kubernetes cloud firewall eventually needs rules for several independent traffic classes:

```text
6443/tcp              API
2379-2380/tcp         stacked etcd
10250/tcp             kubelet
8472/udp              Cilium VXLAN
4240/tcp              Cilium health
ICMP                   Cilium/node health diagnostics
30000-32767/tcp       Kubernetes NodePort
30000-32767/udp       Kubernetes NodePort
```

The source for node-to-node traffic remains:

```text
10.51.0.0/24
```

not the Internet.

---

## 15. Why 8472 is different from NodePort

Cilium's initial deployment uses VXLAN:

```text
Cilium tunnel = VXLAN
```

VXLAN traffic uses:

```text
UDP 8472
```

That is overlay transport.

NodePort traffic is different:

```text
client → node-IP:NodePort → service → pod
```

The two should not be conflated.

A working VXLAN path therefore does not prove that a NodePort path is allowed.

---

## 16. Cilium node health

The baseline also permits:

```text
TCP 4240 ← k8s_cidr
ICMP      ← k8s_cidr
```

Cilium health can show HTTP agent reachability while ICMP-to-host tests fail.

That is valuable because it demonstrates that different health signals validate different layers.

---

## 17. Worked diagnostic: Unix socket versus network socket

The initial ad-hoc CRI test was:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -m shell \
  -a 'systemctl is-active containerd; systemctl is-active kubelet; crictl info >/dev/null && echo CRI_OK'
```

It failed against:

```text
unix:///run/containerd/containerd.sock
```

with:

```text
connect: permission denied
```

This was initially suspected to be networking.

It was actually a Unix-socket permissions issue because the ad-hoc command was executed as `nyameko` rather than root.

The correct test is:

```bash
ansible control_plane:workers \
  -i inventories/private/hosts.yml \
  -b \
  -m shell \
  -a 'systemctl is-active containerd; systemctl is-active kubelet; crictl info >/dev/null && echo CRI_OK'
```

That returned:

```text
active
active
CRI_OK
```

on all six nodes.

The lesson is extremely reusable:

> First identify whether an endpoint is a TCP/UDP service or a local Unix-domain socket. A Unix socket permission error is not an OpenStack firewall failure.

---

## 18. Security troubleshooting workflow

When a connectivity test fails:

```text
1. Identify destination and port
        ↓
2. Identify protocol
        ↓
3. Identify owning layer
        ↓
4. Check OpenStack SG
        ↓
5. Check host firewall
        ↓
6. Check service socket
        ↓
7. Check application health
        ↓
8. Re-run the exact test
```

This workflow prevented the project from repeatedly weakening security groups whenever a higher-level test failed.

---

## References

- OpenStack security groups: https://docs.openstack.org/nova/latest/admin/security-groups.html
- nftables: https://wiki.nftables.org/
- WireGuard: https://www.wireguard.com/
- Wazuh: https://documentation.wazuh.com/
- Suricata: https://docs.suricata.io/
- Kubernetes ports: https://kubernetes.io/docs/reference/networking/ports-and-protocols/
- Kubernetes NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Cilium system requirements: https://docs.cilium.io/en/stable/operations/system_requirements/
