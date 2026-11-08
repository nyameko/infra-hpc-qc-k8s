# Axis H200 ↔ existing Sebowa Slurm controller: private transport gate

**Status:** source-only opt-in to the existing `edge` role. Do not use
this file as evidence that H200 can reach the controller yet.

## Fixed current topology

- XD670 `wg-h200` WireGuard: `10.61.0.3/32`, outbound UDP to Sebowa
  fabric listener. XD670 has no public SSH/Slurm/API listener.
- Sebowa `wg-fabric`: `10.61.0.1/24`, management `10.50.0.10/24`.
  Existing ACE peer `10.61.0.2` must continue to operate.
- Existing `slurmctld`: `slurm-controller-01`, `10.50.0.12`,
  cluster `quantum-cpu` (no new scheduler, no new SlurmDBD).
- H200 science node is a **future** `slurmd` peer, not an installed
  or registered Slurm node. It must not use EL9 RPMs on Rocky 10.
- Earlier operator output: XD670-to-edge ping works (~228 ms RTT), but
  XD670-to-controller TCP/6817 and ICMP fail. XD670-to-ACE peer
  `10.61.0.2` is **not** routed by H200's current AllowedIPs. Do not
  add ACE lateral access just for Slurm.

## Explicit prerequisites before enabling forwarding

1. On **Sebowa edge**: `sysctl net.ipv4.ip_forward` must report `1`.
   `nft -a list chain inet filter forward` shows default drop, with no
   current approved H200 ↔ controller ACL in the checked-in template.
2. On **controller**: verify `ip -4 route get 10.61.0.3`. A
   specific route to H200 through edge `10.50.0.10` is required
   if its ordinary default gateway does not already know this path.
3. On **OpenStack Neutron**: verify source and destination port-security
   and security-group rules for the routed `10.61.0.3` address, not
   only the Edge UDP/51821 listener. A Neutron port with antispoofing
   enabled may reject forwarding traffic whose source IP does not
   match the port fixed IP or configured allowed-address pairs.
   Do **not** disable port security or add a wildcard allowed pair
   simply to make packets pass. Scope changes to the exact H200 /32.
   Keep OpenStack/Terraform changes in the **protected** environment.
4. Check forward packet arrival at edge, controller and XD670 to
   distinguish nftables drop, Neutron rejection, missing return route,
   and host firewalls. Establish outbound compute-to-controller
   TCP/6817 and controller-to-compute TCP/6818 independently.
5. Confirm the existing ACE `wg-fabric` handshake and the user's
   `wg0` SSH access remain working **before and after** each change.
6. Only `sbatch` is in scope for initial acceptance. Interactive
   `srun` will need a separate review of the configured
   `SrunPortRange` and login-to-compute connectivity.

## Source-controlled firewall gate

Disabled by default. Set the following in reviewed protected edge inventory
**only after return routing, Neutron, host security groups and negative
reachability tests are ready**:

```yaml
edge_h200_slurm_forward_enabled: true
edge_h200_slurm_peer_ip: 10.61.0.3
edge_h200_slurm_controller_ip: 10.50.0.12
edge_h200_slurm_diagnostic_icmp: false
```

The `edge.nft.j2` template then allows only:

| Initiator | Destination | Port | Purpose |
| --- | --- | --- | --- |
| H200 10.61.0.3 | Slurm controller 10.50.0.12 | TCP/6817 | `slurmd` → `slurmctld` |
| Slurm controller 10.50.0.12 | H200 10.61.0.3 | TCP/6818 | `slurmctld` → `slurmd` |

Conntrack already permits replies to established connections.
No general `wg-fabric`→`10.50.0.0/24`, `wg0`→H200, public Slurm,
SlurmDBD/6819, or arbitrary intra-fabric permissions are added.
ICMP echo-request forwarding is separately opt-in and off by default.

The edge nftables file starts with `flush ruleset`. **Do not rerun the
complete edge role/restart nftables on a live remote gateway** without first
reconciling runtime rules and having independent recovery access. Its
Ansible template now runs `nft -c` for syntax validation before
installation, but that check does not prove runtime reachability or
absence of collateral policy changes.

A manual, temporary runtime test on Sebowa can use these **two narrowly
scoped** forward rules after observing the live chain and obtaining change
approval; they disappear on reload and do **not** install return routes:

```bash
sudo nft insert rule inet filter forward \
  iifname "wg-fabric" oifname "eth0" \
  ip saddr 10.61.0.3 ip daddr 10.50.0.12 \
  tcp dport 6817 counter accept comment "temp-h200-ctld"

sudo nft insert rule inet filter forward \
  iifname "eth0" oifname "wg-fabric" \
  ip saddr 10.50.0.12 ip daddr 10.61.0.3 \
  tcp dport 6818 counter accept comment "temp-ctld-h200"
```

Replace `eth0` only after verifying Sebowa's live management interface.
Capture handles with `sudo nft -a list chain inet filter forward` and
remove the exact handles with `sudo nft delete rule inet filter forward
handle N` when reverting. Do not flush the chain.

**Important:** these rules alone are insufficient if the controller return
route or Neutron forwarding policy is missing. Use read-only tests first;
do not conclude that Axis UDP is broken from a controller ping failure.

## Identity and accounting — not implemented by this network change

- Keep Quantum Platform authoritative for permanent research UID/GID and
  programme entitlements; reconcile accounts rather than run manual useradd
  on each node. Do not install student SSH keys on XD670.
- Current controller `AccountingStorageEnforce=none` and
  `GresTypes=(null)`. Before any H200/A100 student allocation, add reviewed
  GRES-only science GPU 4–7 and configure explicit Slurm associations,
  QOS/account policy and enforcement, with staged negative tests.
- Avoid privileged `root` cancellation gateway calls. Submit/cancel as the
  authorised POSIX researcher to preserve Slurm's native owner checks.
- On the temporary H200 host, use scratch for execution staging, not as
  the default home or authoritative storage. Durable files live on
  persistent Sebowa-managed storage.

Upstream references:
- [Slurm network requirements](https://slurm.schedmd.com/network.html)
- [Slurm scancel owner enforcement](https://slurm.schedmd.com/scancel.html)
- [Slurm accounting](https://slurm.schedmd.com/accounting.html)
