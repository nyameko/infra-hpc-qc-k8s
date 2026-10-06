# M3 Sprint — Account, Workbench and Slurm Execution

This tutorial consolidates the M3 sprint that connected **Quantum Platform identity**
to private infrastructure, JupyterHub and Slurm.

The sprint is deliberately split into three milestones:

```text
M3a — Account + Access
    Quantum Platform account
    SSH key
    WireGuard key/config
    password/MFA
    VPN reconciliation

M3b — Research Workbench
    Quantum Platform identity
    POSIX UID/GID
    JupyterHub signed launch
    KubeSpawner
    shared NFS home
    launch / status / stop

M3c — Durable Execution
    Quantum Platform execution API
    restricted SSH gateway
    Slurm
    quantum-workflows cpu-smoke
    durable run state
```

The architectural rule across all three is:

> Quantum Platform owns the research identity and desired state. Infrastructure
> materializes that identity safely. JupyterHub and Slurm consume it; they do
> not become independent identity authorities.

---

## 1. Host/operator boundary

Two administration surfaces are intentionally kept separate.

### blackmyth — workstation

Use blackmyth for:

- Git;
- Ansible;
- `ssh-keygen` / `ssh-keyscan`;
- `kubeseal`;
- private inventory;
- plaintext Secret YAML kept outside Git.

The established infra repository layout is:

```text
~/Projects/infra-hpc-qc-k8s/
├── ansible/
│   ├── inventories/private/infra-hpc-qc-k8s.cert
│   └── inventories/private/...
├── secrets/
│   ├── jupyterhub/
│   └── slurm/
└── argocd/
```

The normal working directory is:

```text
~/Projects/infra-hpc-qc-k8s/ansible
```

Therefore a repository-root path such as `argocd/...` is written from there as:

```text
../argocd/...
```

### k8s-cp-01 — Kubernetes administration

Use `k8s-cp-01` for:

- `kubectl`;
- Argo/runtime inspection;
- Kubernetes rollouts;
- Pod logs;
- SealedSecret/Secret verification.

Do **not** make repository checkout on the control-plane node part of the normal workflow.

---

## 2. Identity model and UID/GID policy

A Quantum Platform user and a POSIX user are not two different people.

The same research identity has multiple representations:

```text
Quantum Platform User
    username = nlisa
    UID      = 20999
    GID      = 20999
          │
          ├── SSH
          ├── JupyterHub
          ├── Slurm
          └── NFS /home/research/nlisa
```

Canonical numeric allocation policy:

```text
0–999
    OS/system reserved

1000–4999
    local/admin/site-specific accounts

5000–5999
    infrastructure/service identities
    e.g. Slurm, MUNGE, gateway/exporter services

6000–19999
    reserved infrastructure/site space

20000–29999
    Quantum Platform research identities
    nlisa = 20999:20999

30000–59999
    reserved for future local/platform expansion

60000+
    federation / external identity space
```

The automated allocator should never recycle a retired UID/GID.

For the current bootstrap, `nlisa` is already established as:

```text
username: nlisa
uid:      20999
gid:      20999
home:     /home/research/nlisa
```

---

## 3. Private research-user inventory

Research identities are inventory state and should auto-load through Ansible
`group_vars`, rather than requiring `-e @file.yml` on every run.

Recommended private layout:

```text
ansible/inventories/private/
├── hosts.yml
└── group_vars/
    └── all/
        └── research-users.yml
```

Example private content:

```yaml
research_users:
  - name: nlisa
    uid: 20999
    gid: 20999
    shell: /bin/bash
    home_mode: "0700"
    execution_enabled: true
```

Verify what Ansible actually sees:

```bash
ansible-inventory \
  -i inventories/private/hosts.yml \
  --host login1 |
jq '{
  gateway_key_defined: (.jupyterhub_gateway_public_key // "" | length > 20),
  research_users: (.research_users // [])
}'
```

A private file merely existing under `inventories/private/` does not guarantee
Ansible auto-loads it. A top-level file such as
`inventories/private/research-users.yml` must either be supplied explicitly
or moved under the inventory's `group_vars/` tree.

---

## 4. Ansible precedence lesson

M3c exposed a real precedence bug.

The public file originally set:

```yaml
jupyterhub_gateway_public_key: ""
```

and the playbook loaded that file through `vars_files`.

That value outranked protected inventory variables, so a correct private key
appeared to Ansible as an empty string.

Public placeholders that are meant to be overridden by inventory belong in role
defaults:

```text
ansible/roles/jupyterhub_slurm_gateway/defaults/main.yml
```

not in a high-precedence `vars_files` layer.

When a supposedly defined private variable is missing, inspect the effective
inventory before assuming the file itself is wrong.

---

## 5. M3a — Account and access

M3a establishes the account/access control plane:

- login/reset/admin;
- native password management;
- TOTP/recovery codes;
- SSH key registration;
- WireGuard key registration;
- WireGuard client config generation;
- edge-side peer reconciliation.

The detailed tutorial is:

- [M3a — WireGuard peer reconciliation](m3a-wireguard-peer-reconciliation.md)

Important boundary:

```text
Quantum Platform
    desired VPN identity/key state
          ↓
authenticated internal reconciliation API
          ↓
edge reconciler
          ↓
WireGuard runtime peers
```

Static/admin peers remain infrastructure-owned.

---

## 6. M3b — Jupyter workbench identity handoff

### 6.1 POSIX prerequisite

Quantum Platform must know the numeric identity that already owns the shared
research home.

Verify migration:

```bash
kubectl -n quantum-platform exec \
  deploy/quantum-platform-user-api -- \
  python manage.py showmigrations portal
```

The M3b identity migration is:

```text
[X] 0005_person_posix_identity
```

For the current bootstrap:

```text
nlisa = 20999:20999
```

### 6.2 JupyterHub integration secrets

On blackmyth create two plaintext Secret YAML files outside Git:

```text
../secrets/jupyterhub/jupyterhub-workbench-platform.yaml
../secrets/jupyterhub/quantum-platform-jupyterhub.yaml
```

The JupyterHub-side Secret contains:

```text
launch_signing_key
api_token
crypt_key
```

The Quantum Platform-side Secret contains:

```text
JUPYTERHUB_LAUNCH_SIGNING_KEY
JUPYTERHUB_API_TOKEN
```

The signing key and API token must match across the two namespaces.

Seal from:

```text
~/Projects/infra-hpc-qc-k8s/ansible
```

using:

```bash
kubeseal \
  --cert inventories/private/infra-hpc-qc-k8s.cert \
  --format yaml \
  < ../secrets/jupyterhub/<plaintext>.yaml \
  >| ../argocd/resources/<target>/<name>-sealed.yaml
```

Only `kind: SealedSecret` output belongs in Git.

### 6.3 DNS and ingress

The private Jupyter hostname is:

```text
jupyter.quantum.nyameko.com
```

For the current private ingress it resolves to:

```text
10.51.0.100
```

Pi-hole can prove the record directly:

```bash
dig @10.60.0.1 +short jupyter.quantum.nyameko.com
```

Expected:

```text
10.51.0.100
```

On blackmyth, WireGuard/systemd-resolved should show the private DNS server on
the VPN link:

```bash
resolvectl status wg_infra_hpc_qc
```

If Pi-hole already has the new record but the browser still reports
`Server Not Found`, flush the negative DNS cache:

```bash
sudo resolvectl flush-caches
```

Then validate:

```bash
resolvectl query jupyter.quantum.nyameko.com
getent ahosts jupyter.quantum.nyameko.com
curl -I https://jupyter.quantum.nyameko.com/hub/health
```

A `200` health response proves the path:

```text
blackmyth → WireGuard DNS → Pi-hole → Traefik → JupyterHub
```

### 6.4 Signed launch flow

```text
Quantum Platform
      │
      │ short-lived signed assertion
      │ username + UID/GID + theme
      ▼
JupyterHub PlatformLaunchAuthenticator
      │
      ▼
KubeSpawner
      │
      ▼
jupyter-<username>
      │
      ▼
/home/research/<username>
```

The Hub service role is least privilege:

```text
read:users
read:servers
delete:servers
```

The portal does not receive Kubernetes credentials.

### 6.5 Dynamic NSS identity

The single-user image cannot contain every future research user.

The workbench therefore runs numerically as the authoritative UID/GID and uses
`libnss_wrapper` to synthesize passwd/group entries at startup.

Expected result:

```text
uid=20999(nlisa) gid=20999(nlisa)
HOME=/home/research/nlisa
PWD=/home/research/nlisa
```

NFS writes must remain numerically owned by:

```text
20999:20999
```

### 6.6 Theme and portal UX

The Quantum Platform light/dark selection is included in the launch assertion
and materialized into JupyterLab settings in the persistent research home.

The portal:

- opens Jupyter in a new tab;
- keeps the Quantum Platform dashboard/workbench open;
- shows a destructive red Stop button;
- disables Stop while termination is in progress;
- polls state during stop;
- preserves launch/status/stop semantics independently of Pod lifecycle.

### 6.7 Mutable dev image caveat

Until immutable image promotion is complete, the dev KubeSpawner uses:

```text
imagePullPolicy: Always
```

for the mutable `:dev` single-user image.

Otherwise a node may reuse an older cached workbench image after a successful
Git merge.

### 6.8 M3b acceptance

A successful acceptance run proves:

```text
Portal login
  ↓
signed launch
  ↓
JupyterHub
  ↓
jupyter-nlisa
  ↓
UID/GID 20999:20999
  ↓
/home/research/nlisa
  ↓
persistent NFS write
```

A `0-byte` `.ipynb` file is not a Jupyter/NFS corruption signal; it is simply
an empty file and Jupyter correctly reports it as non-JSON.

Detailed tutorial:

- [M3b — Quantum Platform identity handoff to JupyterHub](m3b-quantum-platform-jupyter-identity.md)

---

## 7. M3c — restricted Slurm execution

### 7.1 Trust boundary

```text
Quantum Platform user-api
      │
      │ dedicated SSH key
      ▼
slurm-login.internal
      │
      │ forced command
      ▼
jupyterhub-gateway
      │
      │ sudo only approved helper
      ▼
/usr/local/sbin/jupyterhub-slurm-helper
      │
      │ runuser -u <researcher>
      ▼
sbatch / squeue / sacct / scancel
```

The service key cannot open an interactive shell.

### 7.2 DNS bootstrap

Current M3c bootstrap:

```text
slurm-login.internal → 10.50.0.20 (login1)
```

Validate:

```bash
getent ahosts slurm-login.internal
dig @10.60.0.1 +short slurm-login.internal
```

Login-node HA is tracked separately. Do not weaken strict host-key checking just
to add round-robin DNS.

### 7.3 Gateway public key

Generate a dedicated keypair on blackmyth:

```bash
ssh-keygen \
  -t ed25519 \
  -a 100 \
  -C "quantum-platform-slurm-gateway" \
  -f ../secrets/slurm/quantum-platform-slurm-gateway
```

Only the public key enters protected inventory:

```yaml
jupyterhub_gateway_public_key: "ssh-ed25519 AAAA... quantum-platform-slurm-gateway"
```

Run:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/jupyterhub-slurm.yml
```

The role installs:

```text
jupyterhub-gateway
jupyterhub-users
/usr/local/sbin/jupyterhub-slurm-helper
/usr/local/sbin/jupyterhub-slurm-ssh-entry
/etc/sudoers.d/jupyterhub-slurm-gateway
forced-command authorized_keys entry
Apptainer/Lmod runtime
quantum-workflows CPU runner SIF
```

If the public-key assertion fails, none of those later artifacts will exist.

### 7.4 Research entitlement

For an execution-enabled user:

```yaml
research_users:
  - name: nlisa
    uid: 20999
    gid: 20999
    shell: /bin/bash
    home_mode: "0700"
    execution_enabled: true
```

The research identity role validates the UID/GID across controller, login,
compute and storage hosts; adds entitled users to `jupyterhub-users`; creates
the durable run directory; and creates/validates the Slurm association.

Durable state is:

```text
/home/research/<username>/.quantum-platform/runs/
```

### 7.5 Slurm account association

The `quantum-platform` account must be associated with the actual cluster
before adding users.

Correct order:

```text
ensure account + cluster association
        ↓
verify association
        ↓
ensure user association
        ↓
submit jobs
```

Do not rely only on `show account <name>`; the account may exist without the
required cluster association.

### 7.6 Known hosts

Capture the login host key using the semantic name:

```bash
ssh-keyscan \
  -t ed25519 \
  slurm-login.internal \
  > ../secrets/slurm/slurm-login-known-hosts
```

Strict host checking stays enabled.

### 7.7 Quantum Platform Slurm Secret

Create plaintext material outside Git at:

```text
../secrets/slurm/quantum-platform-slurm-gateway.yaml
```

A reliable form uses `data:` with base64 values:

```bash
cat >| ../secrets/slurm/quantum-platform-slurm-gateway.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: quantum-platform-slurm-gateway
  namespace: quantum-platform
type: Opaque
data:
  SLURM_GATEWAY_PRIVATE_KEY: $(base64 -w0 ../secrets/slurm/quantum-platform-slurm-gateway)
  SLURM_GATEWAY_KNOWN_HOSTS: $(base64 -w0 ../secrets/slurm/slurm-login-known-hosts)
EOF
```

The `>| ` form is intentional for zsh environments that protect existing
files from ordinary `>` clobbering.

Seal locally:

```bash
kubeseal \
  --cert inventories/private/infra-hpc-qc-k8s.cert \
  --format yaml \
  < ../secrets/slurm/quantum-platform-slurm-gateway.yaml \
  >| ../argocd/resources/quantum-platform/quantum-platform-slurm-gateway-sealed.yaml
```

Verify:

```bash
grep -H '^kind:' \
  ../argocd/resources/quantum-platform/quantum-platform-slurm-gateway-sealed.yaml
```

Expected:

```text
kind: SealedSecret
```

Kustomize resource list order is for composition/readability, not imperative
startup ordering. Argo sync waves and Kubernetes reconciliation provide the
real orchestration.

### 7.8 Runtime environment

After Argo creates the Secret, restart only the consumer:

```bash
kubectl -n quantum-platform rollout restart \
  deployment/quantum-platform-user-api
```

Verify without printing secret values:

```bash
kubectl -n quantum-platform exec \
  deploy/quantum-platform-user-api -- \
  sh -lc '
for v in \
  SLURM_GATEWAY_HOST \
  SLURM_GATEWAY_PRIVATE_KEY \
  SLURM_GATEWAY_KNOWN_HOSTS \
  QUANTUM_WORKFLOWS_CPU_IMAGE
do
  [ -n "$(printenv "$v")" ] && echo "$v=set" || echo "$v=MISSING"
done
'
```

All four must report `set`.

### 7.9 cpu-smoke acceptance

The end-to-end M3c target is:

```text
Quantum Platform /runs/
      ↓
Submit cpu-smoke
      ↓
restricted SSH gateway
      ↓
run as nlisa
      ↓
sbatch
      ↓
quantum-workflows CPU runner
      ↓
Slurm job ID + state
      ↓
durable result under shared NFS
```

The notebook Pod may be stopped while the Slurm workload continues.

Detailed tutorial:

- [M3c — Quantum Platform to Slurm cpu-smoke](m3c-cpu-smoke-slurm-execution.md)

---

## 8. Troubleshooting map

### Workbench says integration unavailable

Check:

```text
JUPYTERHUB_API_URL
JUPYTERHUB_API_TOKEN
JUPYTERHUB_LAUNCH_SIGNING_KEY
```

### Hub Pod is CreateContainerConfigError

Check whether the required Kubernetes Secret exists.

Do not restart the Sealed Secrets controller unless the controller itself is
unhealthy; normal SealedSecret reconciliation is automatic.

### Jupyter hostname does not resolve

Test Pi-hole directly first:

```bash
dig @10.60.0.1 +short jupyter.quantum.nyameko.com
```

If that works, inspect systemd-resolved/WireGuard DNS and flush negative cache.

### Workbench UID is numeric but unnamed

The numeric identity is still the security-critical truth. Ensure the current
single-user image includes the dynamic NSS wrapper and that a fresh image was
pulled.

### `HOME=/`

Ensure KubeSpawner explicitly provides `HOME=/home/research/<username>` and
spawn a fresh Pod from the current image.

### Gateway public key appears empty

Inspect effective Ansible inventory and variable precedence.

### `research_users` is undefined

Move private research-user state beneath inventory `group_vars`, or load it
explicitly. Prefer the former for durable inventory state.

### `sacctmgr add user` says account does not exist on cluster

Ensure the account-to-cluster association first, verify it through
`show association`, then add the user.

---

## 9. Sprint completion criteria

### M3a

- account/password/MFA works;
- SSH and WireGuard registration work;
- WireGuard reconciliation is live and auditable.

### M3b

- Portal knows the authoritative POSIX identity;
- Jupyter launch/status/stop work;
- Jupyter opens separately from the Portal;
- spawned Pod uses correct UID/GID;
- username/group names resolve in the container;
- `HOME` is the shared research home;
- NFS writes survive Pod replacement;
- theme persists.

### M3c

- [x] restricted gateway is installed on login tier;
- [x] no interactive shell is exposed by gateway key;
- [x] research user is entitled;
- [x] Slurm account + cluster + user associations exist;
- [x] Quantum Platform Slurm secret is sealed and consumed;
- [x] `cpu-smoke` returns a numeric Slurm job ID;
- [x] state transitions are queryable after the job leaves `squeue`;
- [x] durable result exists under the user's shared home;
- [x] reference job 15 completed with exit code `0:0` and `passed=true`.

---

## 10. Follow-up engineering work

- [x] automated POSIX allocator in the canonical `20000–29999` block;
- [x] never-reuse UID/GID ledger seeded at `21000`;
- [ ] fresh `21000:21000` user acceptance and POSIX desired-state reconciliation from Quantum Platform into infrastructure;
- highly available `slurm-login.internal` across login1/login2 while preserving
  strict SSH host-key checking;
- immutable image promotion instead of mutable `:dev` tags;
- production-grade programme-specific Slurm accounting and limits;
- token handoff hardening beyond query-string launch assertions.
