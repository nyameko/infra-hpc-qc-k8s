# M3a — Quantum Platform WireGuard research-peer reconciliation

## Ownership

Static administrative peers remain in protected Ansible
`wireguard_admin_peers` and are rendered into `wg0.conf`.

Research peers are managed separately:

```text
Quantum Platform WireGuardKey
  -> allocate client /32 in protected pool
  -> edge reconciler polls desired peer API
  -> wg set wg0 peer ...
  -> edge persists only its managed-peer index
  -> edge acknowledges success
  -> portal marks the client configuration provisioned
```

The reconciler never enumerates or removes static/admin peers. It only removes
keys recorded in its own state file.

## Protected configuration

Quantum Platform SealedSecret/environment:

- `WIREGUARD_RECONCILER_TOKEN`
- `WIREGUARD_CLIENT_POOL`
- `WIREGUARD_RESERVED_ADDRESSES`
- `WIREGUARD_CLIENT_ENDPOINT`
- `WIREGUARD_SERVER_PUBLIC_KEY`
- `WIREGUARD_CLIENT_DNS`
- `WIREGUARD_CLIENT_ALLOWED_IPS`

Edge private Ansible inventory:

```yaml
wireguard_platform_reconciler_enabled: true
wireguard_platform_reconciler_token: <same-high-entropy-token>
```

The public role defaults deliberately contain no live CIDR, endpoint, peer map
or token.

## Failure semantics

If the portal API is unavailable, the reconciler changes nothing.

If any local `wg set` fails, it does not acknowledge provisioning.

Revoked portal keys disappear from desired state and are removed only if they
were previously installed by the platform reconciler.

A WireGuard interface restart temporarily removes dynamic peers because static
`wg0.conf` remains Ansible-owned; the persistent timer restores research peers
on its next successful reconciliation.
