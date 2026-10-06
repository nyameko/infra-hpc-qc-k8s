# Private State Disaster Recovery

The public Git repository is **not** a complete backup of the platform.

```text
infra-hpc-qc-k8s/
├── ansible/inventories/private/
├── secrets/
└── other local protected configuration

external/private recovery material
├── Ansible Vault password / recovery material
├── OpenStack credentials / application credentials
├── WireGuard private configuration
├── SSH and service private keys
└── Sealed Secrets controller private key
```

This tutorial defines an offline disaster-recovery procedure for that protected
state.

The goals are:

- do not commit private infrastructure state to the public repository;
- keep at least one encrypted offline copy;
- keep a second encrypted copy in a physically separate location;
- include the keys required to recover encrypted GitOps secrets;
- test restore procedures periodically rather than assuming a backup is usable.

## 1. What Git already protects

Git remains the source of truth for non-secret desired state:

- Terraform modules;
- Ansible roles and playbooks;
- Argo CD resources;
- SealedSecret manifests;
- public examples and defaults;
- documentation.

A fresh clone of the repository should **not** contain production credentials,
private host inventories, VPN private keys or plaintext Kubernetes Secrets.

Git therefore answers:

> What should the platform look like?

The private recovery set answers:

> What protected identity, credentials and environment-specific state are
> required to rebuild it?

## 2. What must be backed up

### 2.1 Private Ansible inventory

Back up the complete private inventory tree:

```text
ansible/inventories/private/
├── hosts.yml
├── infra-hpc-qc-k8s.cert
├── group_vars/
│   └── all/
│       ├── site.yml
│       └── research-users.yml
└── any protected host_vars / environment files
```

This includes the authoritative private topology and bootstrap research identity
state used by the current environment.

### 2.2 Plaintext local secret workspace

Back up the local secret workspace that is intentionally excluded from Git:

```text
secrets/
├── jupyterhub/
├── slurm/
├── wazuh/
└── other service-specific plaintext Secret inputs
```

Treat this directory as highly sensitive.

### 2.3 Ansible Vault recovery material

If protected variables are encrypted with Ansible Vault, back up the vault
password or the documented recovery mechanism.

Do not depend on a password existing only in:

- terminal history;
- one password manager session;
- one person's memory.

Prefer a password manager for daily use and place an offline recovery copy
inside the encrypted disaster-recovery volume.

### 2.4 OpenStack credentials

Back up the credentials required to recreate and manage the OpenStack
environment, for example:

- application credentials;
- protected `clouds.yaml`;
- project/region identifiers needed during recovery;
- any non-reconstructable provider-specific access material.

Prefer scoped OpenStack application credentials over long-lived personal
passwords where possible.

### 2.5 WireGuard private state

Back up private WireGuard material that cannot be regenerated without
re-enrolling endpoints:

- administrator/client private keys where retained;
- protected endpoint configuration;
- recovery information for infrastructure peers.

Public keys and declarative peer policy may safely exist in their normal
desired-state locations; private keys belong only in protected storage.

### 2.6 SSH and service private keys

Include service identities such as:

- Quantum Platform → Slurm gateway private key;
- protected deployment/admin SSH keys where they are part of the recovery
  procedure;
- any future automation keys that cannot simply be rotated during a rebuild.

Prefer rotation over restoration where operationally practical, but document
which keys are expected to survive a disaster.

### 2.7 Sealed Secrets controller private key

This is critical.

The Git repository contains encrypted `SealedSecret` resources. Those
resources are encrypted for the controller key pair that existed when they were
sealed.

If the entire Kubernetes cluster is lost and a replacement Sealed Secrets
controller generates a different private key, existing encrypted manifests
cannot automatically be decrypted by the new key.

Therefore back up the controller's sealing-key Secret(s).

On `k8s-cp-01`, first inspect the controller keys:

```bash
kubectl -n kube-system get secrets   -l sealedsecrets.bitnami.com/sealed-secrets-key
```

Export the recovery Secret(s) directly into the mounted encrypted backup
volume, never into the Git working tree:

```bash
kubectl -n kube-system get secrets   -l sealedsecrets.bitnami.com/sealed-secrets-key   -o yaml   > /mnt/quantum-dr/recovery/sealed-secrets-controller-keys.yaml

chmod 600   /mnt/quantum-dr/recovery/sealed-secrets-controller-keys.yaml
```

If the installed controller uses a different label layout, inspect the
`kube-system` Secrets first and export the actual Sealed Secrets key Secret(s)
by name.

The exported file contains private cryptographic material and must never be
committed or left on an unencrypted filesystem.

## 3. Recommended backup model

Use at least three copies:

```text
Copy 1 — blackmyth
  active protected working state

Copy 2 — encrypted external SSD
  offline local disaster-recovery copy

Copy 3 — second encrypted device / off-site copy
  physically separate recovery copy
```

An encrypted external SSD is preferable to a cheap USB flash drive for the
primary offline copy. Flash media can still be useful as an additional small
recovery copy.

Do not make an ordinary private Git repository the sole backup for this
material. Git history is persistent, accidental pushes are easy, and a hosted
Git account should not become the root of trust for infrastructure recovery.

## 4. Prepare a LUKS2 recovery drive

**Warning:** the following initialization commands erase the selected target
partition. Verify the device name before running them.

Example only:

```bash
lsblk -f

sudo cryptsetup luksFormat --type luks2 /dev/<RECOVERY_PARTITION>
sudo cryptsetup open /dev/<RECOVERY_PARTITION> quantum-dr

sudo mkfs.ext4 -L quantum-dr /dev/mapper/quantum-dr

sudo mkdir -p /mnt/quantum-dr
sudo mount /dev/mapper/quantum-dr /mnt/quantum-dr

sudo chown "$USER":"$USER" /mnt/quantum-dr
chmod 700 /mnt/quantum-dr
```

Create the recovery layout:

```bash
mkdir -p   /mnt/quantum-dr/infra-hpc-qc-k8s/inventories-private   /mnt/quantum-dr/infra-hpc-qc-k8s/secrets   /mnt/quantum-dr/recovery   /mnt/quantum-dr/manifests
```

## 5. Back up repository-local protected state

From blackmyth:

```bash
cd ~/Projects/infra-hpc-qc-k8s

rsync -aHAX --delete   ansible/inventories/private/   /mnt/quantum-dr/infra-hpc-qc-k8s/inventories-private/

rsync -aHAX --delete   secrets/   /mnt/quantum-dr/infra-hpc-qc-k8s/secrets/
```

Use additional explicit `rsync` commands for other protected local
configuration. Do not copy the entire home directory indiscriminately.

## 6. Store external recovery material

Create clearly named protected files under:

```text
/mnt/quantum-dr/recovery/
```

Examples:

```text
recovery/
├── ansible-vault-recovery.txt
├── openstack/
│   └── clouds.yaml
├── wireguard/
│   └── ...
├── ssh/
│   └── ...
├── service-keys/
│   └── ...
└── sealed-secrets-controller-keys.yaml
```

Apply restrictive permissions:

```bash
chmod -R go-rwx /mnt/quantum-dr/recovery
```

Where a password manager is the primary store, the recovery drive may contain
the documented emergency recovery procedure rather than unnecessarily
duplicating every daily-use secret.

## 7. Create an integrity manifest

After backup:

```bash
cd /mnt/quantum-dr

find infra-hpc-qc-k8s recovery   -type f   -print0 |
sort -z |
xargs -0 sha256sum   > manifests/sha256sum.txt
```

Verify later with:

```bash
cd /mnt/quantum-dr
sha256sum -c manifests/sha256sum.txt
```

The integrity manifest detects corruption; it is not a substitute for
encryption or a second copy.

## 8. Safely disconnect the drive

```bash
sync
sudo umount /mnt/quantum-dr
sudo cryptsetup close quantum-dr
```

Store the device offline.

Do not leave the primary disaster-recovery device permanently attached to
blackmyth. An always-mounted backup can be damaged by the same compromise,
mistake or ransomware event as the active system.

## 9. Rotation and cadence

Recommended minimum cadence:

- after any credential/key rotation;
- after meaningful private inventory changes;
- after adding/removing platform-managed identity bootstrap data;
- after rotating the Sealed Secrets controller key;
- before and after major infrastructure migrations;
- at least monthly even during quiet periods.

For rapidly changing private configuration, a weekly offline rotation is
preferable.

Use two external devices in rotation where possible:

```text
Week A → backup SSD A
Week B → backup SSD B
Week C → backup SSD A
...
```

Keep one device physically separate from blackmyth.

## 10. Recovery order

A full rebuild should proceed in layers:

```text
public Git repositories
        ↓
private OpenStack credentials
        ↓
Terraform infrastructure
        ↓
private Ansible inventory
        ↓
Ansible host configuration
        ↓
Kubernetes control plane
        ↓
restore Sealed Secrets controller key
        ↓
Argo CD / SealedSecret reconciliation
        ↓
restore/recreate service credentials
        ↓
WireGuard / SSH access
        ↓
research identity reconciliation
        ↓
application validation
```

Do not restore application workloads before restoring the identity and secret
roots they depend on.

## 11. Sealed Secrets recovery drill

During a planned recovery exercise:

1. create or use an isolated Kubernetes test cluster;
2. install the same compatible Sealed Secrets controller;
3. restore the backed-up sealing-key Secret(s);
4. restart the controller;
5. apply a non-production SealedSecret encrypted with the historical
   certificate;
6. verify the controller can materialize the expected Kubernetes Secret.

Never discover during an actual disaster that the controller key backup was
incomplete.

## 12. Restore private inventory

On a rebuilt blackmyth/workstation:

```bash
mkdir -p ~/Projects/infra-hpc-qc-k8s/ansible/inventories/private
mkdir -p ~/Projects/infra-hpc-qc-k8s/secrets

rsync -aHAX   /mnt/quantum-dr/infra-hpc-qc-k8s/inventories-private/   ~/Projects/infra-hpc-qc-k8s/ansible/inventories/private/

rsync -aHAX   /mnt/quantum-dr/infra-hpc-qc-k8s/secrets/   ~/Projects/infra-hpc-qc-k8s/secrets/
```

Then validate before applying anything:

```bash
cd ~/Projects/infra-hpc-qc-k8s/ansible

ansible-inventory   -i inventories/private/hosts.yml   --graph

ansible-inventory   -i inventories/private/hosts.yml   --host k8s-cp-01
```

Do not run the full playbook suite until the recovered inventory has been
reviewed for stale addresses, retired credentials and environment drift.

## 13. Recovery verification checklist

A backup is accepted only if all of the following are true:

- encrypted volume opens using documented recovery material;
- private inventory files are readable;
- integrity checks pass;
- Ansible can parse the recovered inventory;
- OpenStack credentials authenticate;
- required WireGuard/SSH service keys are present or have an explicit rotation
  plan;
- Sealed Secrets controller private key backup exists;
- restore drill has been performed successfully;
- a second encrypted copy exists in a physically separate location.

## 14. What should not be backed up as authoritative private state

Avoid treating the following as canonical disaster-recovery inputs:

- generated Terraform caches;
- Python virtual environments;
- container layer caches;
- Jupyter temporary/runtime files;
- Kubernetes Pods;
- ephemeral Slurm spool files;
- regenerated build artifacts.

Prefer rebuilding those from Git, immutable images and declared infrastructure.

The recovery set should stay as small as possible while retaining every
non-reconstructable credential and private desired-state input.
