# Axis H200: temporary host recovery and redeployment

**Status:** runbook and opt-in source for operator review. Based on verified
November 8, 2026 hardware and private networking evidence, not on a simulated
full-disaster recovery. Do not expose host APIs on public network interfaces.

## Recovery contract

- The Axis broker is the fallback administrative transport until the private
  WireGuard tunnel is restored. Access broker usernames can rotate.
- The standard private management route is workstation `ssh h200` through
  Sebowa's `10.60.0.1` jump host to `10.61.0.3` on XD670.
- Sebowa `wg0` researcher VPN is **10.60.0.0/24**; Sebowa `wg-fabric`
  infrastructure VPN is **10.61.0.0/24**, UDP/51821.
- The H200 WireGuard interface is `wg-h200`. It initiates the UDP session to
  the Sebowa public gateway. Sebowa's H200 peer does **not** need a static
  Endpoint; it learns the client's current NAT endpoint on handshake.
- A VPN port being accessible is separate from SSH authentication. Never
  install public SSH or HTTP listeners as a disaster-recovery shortcut.
- The public Neutron security group, owned in private Terraform, must permit
  authenticated roaming WireGuard traffic to Sebowa UDP/51821. Restrict
  other services. Source-IP /32 ACLs for Axis may fail when its NAT changes.
- Persist Sebowa's H200 peer in protected Ansible `wg_fabric_peers`; the
  existing template is a **complete peer list** and could otherwise remove
  the new peer on a later reconciliation.

## Persisted host state that must be recoverable

| Object | Host location | Recovery authority |
| --- | --- | --- |
| WireGuard private identity and preshared key | /etc/wireguard/wg-h200.conf | Protected Ansible Vault or encrypted off-host backup |
| Sebowa gateway peer + Neutron security group | Sebowa wg-fabric + PTA OpenStack | Existing private Ansible/Terraform inventory and state |
| Inference API token | /etc/vllm/h200.env, root:root 0600 | Protected Ansible Vault; rotate and update ACP if lost |
| Existing two XFS mounts | /etc/fstab and filesystem UUIDs | Inventory + non-destructive recovery role |
| Inference immutable container image and GPU UUID | Private Ansible inventory | Pinned OCI digest + GPU inventory |
| Model weights | /srv/h200/inference/models | Re-downloadable public cache, unless proprietary/license restricted |
| Research input/output | /srv/h200/science/scratch | Must be exported to durable external storage; not protected by this plan |

The **other six NVMe disks are not part of the pilot provisioning plan**.
The two existing pilot drives are whole-namespace XFS volumes. A rebuilt host
must not run `mkfs` or `wipefs` on them merely because they are present.
Back up scientific outputs before the temporary allocation expires.

## Safe execution sequence

1. On an administrative workstation, retrieve the reviewed repository source
   and its approved, ignored private inventory/Vault. Never commit raw tokens
   or private keys.
2. On a wiped or replacement XD670, use the Axis **broker** access to bootstrap
   `wg-h200`. Provide the original approved interface private key, PSK,
   endpoint and gateway public key **through Vault**, then opt into
   `ansible/playbooks/axis-h200-wireguard-restore.yml` by setting
   `axis_h200_wg_restore: true`.
   The restore role explicitly refuses to overwrite a live interface or
   pre-existing configuration. Its default is read-only.
3. Verify a new WireGuard handshake and reachability from Blackmyth with
   `ssh h200`. Revisit the Neutron UDP-only ACL if the public NAT source
   has changed. Do not remove the original Axis access.
4. Identify each NVMe by **serial + filesystem UUID**, not `nvmeXn1` name.
   Run `ansible/playbooks/axis-h200-runtime.yml` in default verification
   mode. If the existing mounts need fstab restoration, explicitly enable
   `axis_h200_runtime_manage_persistence: true`; this never formats disks.
5. Inspect `nvidia-smi` GPU UUIDs and `nvidia-ctk cdi list`, then pull
   the operator-approved immutable `docker.io/vllm/vllm-openai@sha256:...`
   image. Do not reuse an unverified `:latest` tag in automation.
6. Restore the secret `/etc/vllm/h200.env`, containing exactly
   `VLLM_API_KEY=<secret>` with root ownership and 0600 mode, from
   protected storage; if rotating, update the downstream private clients.
7. Stage the inference Quadlet by setting `axis_h200_vllm_manage: true`
   in private inventory and running `ansible/playbooks/axis-h200-inference.yml`.
   It is loopback-bound at `127.0.0.1:8000`, selects a single approved
   GPU UUID from physical GPUs 0–3, mounts the model cache and requires
   the XFS filesystem. No model pull or service startup is performed by
   default. Stop `h200-vllm-test` before explicitly setting
   `axis_h200_vllm_start: true`.
8. Verify `curl -H "Authorization: Bearer ..."`
   on `http://127.0.0.1:8000/v1/models` and an actual completion.
   Remote access should initially use `ssh -L` over WireGuard;
   a permanent K8s-to-H200 backend requires an authenticated,
   WireGuard-restricted service route and additional security review.

## Emergency verification commands

```bash
# On XD670:
wg show wg-h200
systemctl is-enabled wg-quick@wg-h200
findmnt --mountpoint /srv/h200/inference/models
findmnt --mountpoint /srv/h200/science/scratch
nvidia-smi --query-gpu=index,uuid,pci.bus_id --format=csv
nvidia-ctk cdi list
podman ps -a
ss -lnt
```

Never paste private WireGuard key material, service API tokens or the raw
contents of `/etc/wireguard/wg-h200.conf` into a public issue/chat.
For human acceptance, verify the host-key fingerprint independently rather
than disabling SSH host-key checks.

## Scope limitations

A clean host rebuild is **not** yet tested. The existing EL9/A100 Slurm
playbook must not be applied to Rocky 10. Researcher access, Slurm GPU
confinement and four-GPU multi-tenant isolation remain separate milestones.
An independently managed Podman inference container is not an enforceable
multi-user scheduler boundary without OS/cgroup policy.
