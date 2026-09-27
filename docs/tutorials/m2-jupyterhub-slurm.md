# M2 — JupyterHub → Slurm

## Goal

Kubernetes hosts the JupyterHub control plane. Slurm is the only notebook
compute plane.

```text
browser
  |
JupyterHub (Kubernetes)
  |
restricted SSH: submit/query/cancel
  |
Slurm login/gateway
  |
cpu-small / cpu-large
  |
jupyterhub-singleuser
  |
/home/research/<user>
```

The Hub does not receive `munge.key`.

## Profiles

| profile | partition | CPU | memory | walltime |
| --- | --- | ---: | ---: | ---: |
| Development | cpu-small | 2 | 8 GiB | 2 h |
| Interactive Large | cpu-large | 16 | 64 GiB | 8 h |

There is no local or Kubernetes notebook-compute fallback.

## Bootstrap identity

M2 uses only the disposable `jhub-smoke` account. Do not manually create
`nlisa` or another production researcher identity. M3 provisions real
identity from Quantum Platform approval.

## Trust boundary

The Kubernetes Hub gets a dedicated SSH key, not the MUNGE key. Its public key
is installed on the login tier as a forced command with `restrict`. The
gateway accepts only:

- `submit <user>`
- `query <jobid>`
- `cancel <jobid>`

Submission is executed as the provisioned POSIX user. The helper validates
membership in `jupyterhub-users`, the `jhub-` job prefix, the M2 partition
allow-list, and M2 walltimes.

## Private topology

Keep real host/IP mappings, WireGuard peers, OpenStack IDs, management
addresses and ACL details in protected inventory. Public Git may contain the
architecture and reference topology, but it should not be the authoritative
live network map.

## Deploy host-side prerequisites

Generate a dedicated gateway keypair:

```bash
ssh-keygen -t ed25519 -f ./jupyterhub-slurm -C jupyterhub-slurm
```

Put only the public key in protected Ansible inventory and explicitly enable
the smoke identity:

```yaml
jupyterhub_gateway_public_key: "ssh-ed25519 AAAA..."
jupyterhub_smoke_user_enabled: true
```

Then:

```bash
cd ansible
ansible-playbook -i inventories/private/hosts.yml \
  playbooks/jupyterhub-slurm.yml \
  --ask-vault-pass
```

Create `/home/research/jhub-smoke` on the authoritative shared storage using
UID/GID 20999. This is deliberately temporary.

## Kubernetes secrets

Create the two Secrets shown by `secret.example.yaml`, seal them locally with
kubeseal, and commit only ciphertext:

- `jupyterhub-bootstrap`: high-entropy temporary smoke password
- `jupyterhub-slurm-ssh`: dedicated private SSH key and pinned gateway host key

Never commit a private SSH key, smoke password, MUNGE key, kubeconfig, database
password or unsealed Secret.

## Required network paths

Both directions matter:

```text
Hub -> login gateway:22 -> Slurm
proxy -> allocated compute node:singleuser-port
compute node -> private Hub callback URL
```

Do not solve routing by broadly opening the management plane. The exact
compute CIDR and security-group rules belong in private environment data.

The compute nodes use `https://jupyter.quantum.nyameko.com/hub` as the Hub callback path, through the same browser-facing private/VPN endpoint. Keep that hostname private at the edge; DNS and HAProxy/Traefik must route it explicitly.

## M2 acceptance gate

Do not call M2 complete until all are green:

- browser login works as `jhub-smoke`
- only the two Slurm profiles are offered
- no local/Kubernetes compute fallback exists
- spawn creates a visible Slurm job
- pending/running state is reflected correctly
- `sacct` records user, partition, elapsed time and allocation
- Stop Server cancels its Slurm job
- spawn timeout leaves no orphan allocation
- Slurm walltime terminates the notebook
- CPU/memory cgroup limits apply
- a file under `/home/research/jhub-smoke` survives stop/re-spawn
- Hub restart reconciles or safely cleans up its allocation
- arbitrary gateway commands are rejected
- non-JupyterHub cancellation is rejected
- compute/user traffic cannot reach management-only services
- no Kubernetes pod or Secret contains `munge.key`

Useful checks:

```bash
squeue -o '%.18i %.12P %.24j %.12u %.2t %.10M %.6D %R'
sacct -X --starttime today \
  --format=JobID,JobName,User,Account,Partition,State,Elapsed,AllocCPUS,ReqMem
```

## M3 handoff

After M2 passes, remove the bootstrap authenticator and smoke identity.

```text
Quantum Platform approval
        |
desired provisioning state
        |
        +-- POSIX UID/GID
        +-- /home/research/<user>
        +-- SSH/WireGuard public keys
        +-- Slurm account/association/QoS
        |
JupyterHub entitlement
```

A100, H200, QPU and programme-specific profiles come only after that.
