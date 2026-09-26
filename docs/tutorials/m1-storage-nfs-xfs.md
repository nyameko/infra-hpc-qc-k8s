# M1 — Persistent research storage with Cinder SSD, XFS quotas and NFSv4

M1 deliberately separates durable storage from compute. The OpenStack deployment
creates `storage-nfs-01` at `10.50.0.40` and attaches three independent
Ceph-backed Cinder SSD block volumes:

| Filesystem | Size | Server mount | Client mount | Policy |
|---|---:|---|---|---|
| Home | 512 GiB | `/srv/home` | `/home` | XFS user quotas |
| Datasets | 2048 GiB | `/srv/datasets` | `/datasets` | XFS project/programme quotas |
| Staging | 512 GiB | `/srv/staging` | `/staging` | XFS user/project quotas + retention gate |

Scratch is intentionally **not** part of these 3 TiB. M1 uses bounded local
compute-node storage for temporary work until local ephemeral SSD/NVMe flavors
are available.

## Safety boundary

Terraform/Cinder attachment order is not a filesystem identity. Before running
the storage role, inspect the server:

```bash
ssh storage-nfs-01
lsblk -o NAME,SERIAL,SIZE,TYPE,FSTYPE,MOUNTPOINTS
ls -l /dev/disk/by-id/
```

Map each Cinder volume to a stable `/dev/disk/by-id/...` path in the **private**
Ansible inventory:

```yaml
storage_nfs_devices:
  home: /dev/disk/by-id/<verified-home-device>
  datasets: /dev/disk/by-id/<verified-datasets-device>
  staging: /dev/disk/by-id/<verified-staging-device>
```

The role refuses missing devices and refuses to overwrite any existing
non-XFS filesystem. This is deliberate.

## Quota model

Quantum Platform is authoritative for User / PI / Research Programme policy.
The storage server is the enforcement point.

* `/home`: UID-scoped XFS user quota. M1 defaults are 20 GiB soft / 25 GiB hard.
* `/datasets`: XFS project quotas on programme directory trees. No programme
  receives capacity merely because a Unix user exists; declare programme
  policy explicitly.
* `/staging`: UID-scoped XFS quota, default 100 GiB soft / 125 GiB hard.
  Staging objects are temporary.

Populate `storage_quota_users` and `storage_programmes` from protected
provisioning data. These lists contain only the UID/GID/project mapping needed
for filesystem enforcement; passwords, MFA secrets and SSH private keys never
belong here.

Example:

```yaml
storage_quota_users:
  - username: researcher
    uid: 20001
    gid: 20001
    home_soft_gib: 20
    home_hard_gib: 25
    staging_soft_gib: 100
    staging_hard_gib: 125

storage_programmes:
  - name: exoplanets
    gid: 30001
    project_id: 40001
    dataset_soft_gib: 400
    dataset_hard_gib: 500
```

Inspect enforcement:

```bash
sudo xfs_quota -x -c 'state' /srv/home
sudo xfs_quota -x -c 'report -h -u' /srv/home
sudo xfs_quota -x -c 'report -h -p' /srv/datasets
sudo xfs_quota -x -c 'report -h -u' /srv/staging
```

## Staging expiry safety gate

The infrastructure installs an hourly `quantum-staging-expiry.timer`.
It does **not** delete a staging object merely because it is old.

A staged transfer directory becomes deletable only when it contains:

* `.expires_at`: Unix epoch expiry time, and
* `.notifications_complete`: proof that the platform notification workflow
  has completed the configured warning sequence.

Quantum Platform issue #8 owns user-facing quota and expiry telemetry and the
50/75/90 percent usage warnings plus 7-day/3-day/1-day/deletion email sequence.
The storage worker refuses deletion if the notification gate is absent.

## NFS

The server exports the three XFS mountpoints over NFSv4 with `root_squash`.
Only the private Slurm login/compute security groups have TCP/2049 access.
Clients use hard NFS mounts so transient server/network failure does not silently
turn an interrupted write into successful job output.

This M1 gateway is intentionally a single NFS service endpoint. Ceph provides
durable backing for the Cinder block volumes but does **not** make the NFS
gateway itself highly available. Test outage/recovery and backups before
production research use.

## Deployment

From `ansible/`:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/storage.yml --syntax-check
ansible-playbook -i inventories/private/hosts.yml playbooks/storage.yml --check --diff
ansible-playbook -i inventories/private/hosts.yml playbooks/storage.yml
```

Then validate from both login nodes and all four compute nodes:

```bash
findmnt /home /datasets /staging
df -hT /home /datasets /staging
touch /staging/.m1-write-test && rm /staging/.m1-write-test
```

Run storage acceptance before Slurm. The combined `playbooks/m1-hpc.yml`
preserves that ordering.

## Observability and security

`storage-nfs-01:9100` is scraped separately as the `storage-hosts` job.
The standard node_exporter filesystem and NFSd collectors expose filesystem
capacity, disk/network health and NFS server activity. Grafana gets aggregate
infrastructure telemetry only.

Per-user names, email addresses, programme membership and private paths must
not become Prometheus labels. User-specific quota/retention state belongs in
the authenticated Quantum Platform API/UI.

The storage playbook also enrolls `storage-nfs-01` with the existing Wazuh
agent role. The private inventory must provide the same Wazuh manager/version
variables already used for other persistent OpenStack hosts.
