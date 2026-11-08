# Axis H200: observed storage and private access

**Status (2026-11-08):** operator-reported working configuration on a temporary
Rocky Linux 10 XD670. This document records evidence; source changes are **not**
live deployment. Do not deploy Slurm or vLLM as "complete" until a real workload
and negative GPU-isolation tests have been observed.

## Verified operational evidence

- Eight H200 GPUs and NVIDIA CDI available; a single pinned-GPU Podman CUDA
  smoke test passed on one GPU.
- Two *whole-namespace* XFS filesystems, separate from the OS drive, were
  initialised manually after disk-identity checks:
  `/srv/h200/inference/models` and `/srv/h200/science/scratch`, ~7 TiB each.
  The other six NVMe namespaces have **not** been initialised by this project.
- Operator fio test on science scratch: **5,245 MiB/s** sequential write
  (4 GiB file) and **6,334 MiB/s** 1-MiB random reads (30 seconds), zero fio
  errors. This is a smoke benchmark, not a production endurance test.
- Sebowa infrastructure WireGuard is `wg-fabric` on **UDP/51821**, separate
  from the researcher VPN `wg0` on **UDP/51820**.
- XD670 has a dedicated `wg-h200` client interface and connects outbound to
  Sebowa. Public inbound ports on XD670 are not needed.
- A new Sebowa WireGuard peer has handshaken successfully; ICMP works in
  both directions. The owner successfully ran **`ssh h200`** from their Arch
  workstation through the existing private jump host and enabled
  `wg-quick@wg-h200` on XD670.
- Existing ACE fabric peer remained operational.
- Initial failure was caused by **OpenStack Neutron ingress** allowing only
  the existing ACE public source on UDP/51821. Temporarily admitting the
  H200's source fixed the handshake. The Axis public NAT endpoint may change.
  Prefer a documented WireGuard-only roaming ingress policy for UDP/51821
  over guessing a wide provider CIDR. Keep unrelated SSH/API ports closed.

## Recovery and persistence

No root filesystem or NVIDIA driver changes are part of this workflow.
Keep the Axis portal as the independent recovery route until private SSH
works after a full host/network reconnect. Do not restart the running Sebowa
`wg-fabric` interface or overwrite its complete peer list ad hoc.

On XD670:

```bash
systemctl is-enabled wg-quick@wg-h200
wg show wg-h200
findmnt --mountpoint /srv/h200/inference/models
findmnt --mountpoint /srv/h200/science/scratch
nvidia-ctk cdi list
```

On Sebowa:

```bash
wg show wg-fabric latest-handshakes
nft list chain inet filter input
```

Current checked-in edge nftables did not permit UDP/51821 even though
a running rule was inserted by the operator; this PR adds the missing
listener permission to the source template. **Do not reload the entire edge
nftables ruleset just to install this change.** The template currently flushes
the ruleset and could remove independently managed live ACLs. Review all
effective rules and apply through the approved IaC rollout.

The floating IP and OpenStack security group are managed in the **private
Terraform environment**. This public repo does not store credentials,
Axis public egress IP, disk serials or WireGuard private/PSK keys. Confirm the
Neutron UDP/51821 roaming policy there; no SSH ingress to XD670 is required.

## Read-only Ansible audit and optional persistence

In ignored `ansible/inventories/private/axis-h200.yml`, use the already
working private SSH route (ProxyJump), the eight expected GPU UUIDs for the
existing `axis_h200_host` preflight and **both** existing XFS UUIDs plus
their physical disk serials. Example extra host variables:

```yaml
axis_h200_runtime_wireguard_interface: wg-h200
axis_h200_runtime_manage_persistence: false
axis_h200_runtime_mounts:
  - path: /srv/h200/inference/models
    uuid: "<VERIFIED_EXISTING_XFS_UUID>"
    serial: "<VERIFIED_DRIVE_SERIAL>"
  - path: /srv/h200/science/scratch
    uuid: "<VERIFIED_EXISTING_XFS_UUID>"
    serial: "<VERIFIED_DRIVE_SERIAL>"
```

From `ansible/`, on an approved workstation with Ansible installed:

```bash
ANSIBLE_HOST_KEY_CHECKING=True ansible-playbook \
  -i inventories/private/axis-h200.yml \
  playbooks/axis-h200-runtime.yml --check
```

Default mode is read-only: validates mounted XFS UUIDs and disk serials,
WireGuard status, and the pre-existing H200 readiness checks. Explicitly
setting `axis_h200_runtime_manage_persistence: true` allows **only** fstab
reconciliation of the already verified XFS filesystems and enabling the
existing WireGuard systemd service. It **never** creates a filesystem,
formats NVMe, generates WireGuard keys, changes the OS disk, or restarts
an existing WireGuard interface. Do not turn this flag on before review.

## Next operator milestones

1. Verify fresh WireGuard handshakes persist after the temporary wide
   OpenStack rule is withdrawn, including a reconnect/NAT change.
2. Serve a public open-weight model on one *inference* GPU with Podman CDI,
   a protected token, model cache mounted on the dedicated XFS volume and
   `127.0.0.1`-only port publication. Pin the observed image digest after
   smoke testing and configure a systemd Quadlet.
3. Run a true CUDA/scientific workload on *science* GPU 4.
4. Configure Slurm to manage **only GPUs 4–7** through explicit `gres.conf`
   device files and task/cgroup confinement; check the required controller
   and account architecture before installing. An inference Podman test on
   GPUs 0–3 does not itself prove cross-user device isolation.
5. Integrate the authenticated model and scientific job paths into the
   existing ACP / quantum-workflows integration, rather than create another
   bespoke scheduler.

Avoid root-owned shared scratch access for student jobs. Enforce permissions,
quotas/cleanup policy and verified cgroup device isolation before onboarding
untrusted users.
