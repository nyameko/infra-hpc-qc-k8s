# 2. Networking, Edge Security & Cyber Security Considerations

## 2.1 Defense in depth

```text
Internet
   │
   ▼
OpenStack security groups        (cloud-level boundary — stateful, per-port)
   │
   ▼
edge
   │
   ├── nftables        (host-level packet filtering)
   ├── WireGuard        (encrypted remote-access tunnel)
   ├── Pi-hole          (internal DNS + filtering)
   ├── Wazuh manager    (log/telemetry aggregation, HIDS)
   └── Suricata         (network IDS)
```

Two independent layers matter here: OpenStack security groups are enforced by the hypervisor/SDN and can't
be bypassed even if a VM is fully compromised at the OS level; nftables is enforced *inside* the VM and can
be bypassed by root on that VM. Neither layer is a substitute for the other — losing one still leaves the
other standing.

**Further reading:** [OpenStack Networking security groups](https://docs.openstack.org/nova/latest/admin/security-groups.html) ·
[nftables wiki](https://wiki.nftables.org/) · [NIST SP 800-207, Zero Trust Architecture](https://csrc.nist.gov/pubs/sp/800/207/final)
for the general principle of not trusting a single perimeter.

## 2.2 Canonical network segmentation

```yaml
mgmt_cidr: 10.50.0.0/24   # infrastructure management
k8s_cidr:  10.51.0.0/24   # Kubernetes nodes + API LB
vpn_cidr:  10.60.0.0/24   # WireGuard clients
```

Use exactly these three names everywhere — Terraform variables, Ansible group_vars, documentation prose.
Do **not** introduce `management_cidr` or `wireguard_cidr` as synonyms; see `docs/08` §8.2 for the drift
check that catches this.

## 2.3 SSH identity model

Two identities are used deliberately, not by accident:

| Identity | Purpose | Key source |
|---|---|---|
| `rocky` | Bootstrap/recovery | OpenStack-injected bootstrap key |
| `nyameko` | Normal administration | Separate administrative key installed by Ansible |

The bootstrap identity is kept available until recovery access via `nyameko` has actually been tested — not
removed the moment the playbook reports success. Normal access to private nodes goes through `edge` via SSH
`ProxyJump`, never directly.

SSH into `edge` itself has a two-stage lifecycle:

```text
Stage 1 (temporary):  bootstrap_ssh_cidr → edge:22   (needed to run Ansible for the first time)
Stage 2 (normal):     WireGuard          → edge:22   (public bootstrap rule removed once this is proven)
```

Removing the public bootstrap SSH rule after WireGuard is proven working is not optional hardening — treat
it as part of the deployment checklist, not a "nice to have."

**Further reading:** [OpenSSH `ProxyJump`](https://man.openbsd.org/ssh_config#ProxyJump) ·
[CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks) for baseline SSH hardening beyond what's covered
here.

## 2.4 WireGuard VPN

```text
10.60.0.0/24 (clients)
      │
      ▼
     wg0
      │
      ▼
    edge  (server: 10.60.0.1/24)
      │
  masquerade
      │
      ▼
external network
```

Key handling rule: **private keys never leave the host they were generated on.** The server's private key
is generated on `edge` and stays there; a client's private key stays on the client. Only public keys travel
between them. A client address such as `10.60.0.2/32` is safe to hand out; a private key never is.

**Further reading:** [WireGuard whitepaper](https://www.wireguard.com/papers/wireguard.pdf) ·
[wireguard.com](https://www.wireguard.com/).

## 2.5 nftables host firewall baseline

```text
input   → drop     (with explicit accept rules for required traffic)
forward → drop
output  → accept
```

Stateful filtering via conntrack:

```nft
ct state established,related accept
```

Always validate before applying a new ruleset — a bad `nftables.conf` on `edge` can lock out the only entry
point into the environment:

```bash
sudo nft -c -f /etc/nftables.conf
```

**Further reading:** [nftables wiki](https://wiki.nftables.org/) · [Red Hat: Getting started with
nftables](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_firewalls_and_packet_filters/getting-started-with-nftables_firewall-packet-filters).

## 2.6 DNS architecture

```text
VM / Pod
   │
   ▼
CoreDNS
   │
   ▼
10.50.0.10:53   (edge)
   │
   ▼
Pi-hole
   │
   ▼
upstream DNS
```

Pi-hole provides resolution, filtering, and internal infrastructure records. Its initial persistent state
lives on `edge`'s local disk; migrating it to Cinder-backed storage is a later hardening step, not a launch
blocker. **Do not expose Pi-hole's DNS port to the public internet** — permit DNS only from `mgmt_cidr`,
`k8s_cidr`, and `vpn_cidr`.

**Further reading:** [Pi-hole documentation](https://docs.pi-hole.net/) · [CoreDNS
documentation](https://coredns.io/manual/toc/).

## 2.7 Intrusion detection and monitoring

**Wazuh** rolls out in two phases:

```text
Phase 1 (now):   other hosts → Wazuh agents → edge / Wazuh manager
Phase 2 (later): Wazuh manager → Wazuh indexer → Wazuh dashboard   (deployed in Kubernetes)
```

The manager can collect and process agent events before the indexer/dashboard exist — you don't need to
wait for the full Kubernetes-hosted stack to get value from agent telemetry. Never expose the manager
publicly.

**Suricata** starts in **IDS mode only**. Do not flip it to inline IPS mode until the exact traffic path has
been tested — an untested inline IPS is a self-inflicted denial-of-service risk, not a security improvement.

**Further reading:** [Wazuh documentation](https://documentation.wazuh.com/) ·
[Wazuh architecture overview](https://documentation.wazuh.com/current/getting-started/architecture.html) ·
[Suricata documentation](https://docs.suricata.io/) · [MITRE ATT&CK](https://attack.mitre.org/) as the
reference framework for mapping what these tools actually detect.

## 2.8 Three separate access-control planes

It's easy to think of "access control" as one thing. In this platform it is at least three independent
planes, each with its own model and its own failure mode:

| Plane | Mechanism | Governs |
|---|---|---|
| Cloud | OpenStack security groups | Which VM can talk to which VM/port, before the OS boots |
| Cluster | Kubernetes RBAC + `NetworkPolicy` (via Cilium) | Which identity can call the API server; which pod can talk to which pod |
| HPC | Slurm accounting, QOS, partitions | Which user can submit to which partition, with what resource limits |

A hole in one plane is not automatically covered by another — a Kubernetes `NetworkPolicy` does nothing for
an attacker who has SSH access to `slurm-cpu-01` outside the cluster, and Slurm QOS limits do nothing for a
pod-to-pod lateral-movement attempt inside Kubernetes. Design and test each plane on its own terms.

**Further reading:** [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
[Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) ·
[Cilium NetworkPolicy](https://docs.cilium.io/en/stable/security/policy/) · [Slurm accounting and
QOS](https://slurm.schedmd.com/qos.html).

## 2.9 Threat model: what this environment is actually defending against

| Threat | Primary mitigation | Where it's documented |
|---|---|---|
| Unauthenticated external actor probing `edge` | OpenStack SG + nftables default-drop + Suricata IDS | §2.1, §2.5, §2.7 |
| Stolen/leaked WireGuard client key | Per-client keys (revoke individually), PSKs, `vpn_cidr` isolation | §2.4 |
| Compromised WireGuard client pivoting inward | `vpn_cidr` routed only through `edge`, not directly to `mgmt_cidr`/`k8s_cidr` | §2.2, `docs/01` §1.4 |
| Hermes orchestrator credential misuse | Read-only by default, no Git push token, human-approved change path | `docs/06` §6.3 |
| Lateral movement inside Kubernetes | Cilium `NetworkPolicy`, RBAC least privilege | §2.8 |
| Slurm job used as an attack vector (e.g. exfiltration, crypto-mining) | Accounting/QOS limits, no user logins on the controller | `docs/05` |
| Secret sprawl in Git | Never-commit list, Vault/SOPS progression | `docs/08` §8.1 |
| Untested inline IPS causing self-inflicted outage | Suricata stays IDS-only until path is proven | §2.7 |

This table is deliberately short — it's a starting map for course discussion, not a completed risk
register. A good workshop exercise is extending it with likelihood/impact scoring and mapping each row to a
MITRE ATT&CK technique.

**Further reading:** [MITRE ATT&CK](https://attack.mitre.org/) · [NIST SP 800-30, Guide for Conducting Risk
Assessments](https://csrc.nist.gov/pubs/sp/800/30/r1/final) · [NIST SP 800-207, Zero Trust
Architecture](https://csrc.nist.gov/pubs/sp/800/207/final).

## 2.10 Secrets handling — see `docs/08`

Nothing in this document should ever require a credential to be committed to Git. If a networking task
seems to require that, stop and read `docs/08` §8.1 first.
