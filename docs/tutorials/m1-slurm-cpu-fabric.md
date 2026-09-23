# M1 — CPU Slurm fabric: deployment and acceptance

This is the CPU-only M1 foundation for Quantum Platform. **All research compute,
including future small development notebooks, is scheduled and accounted by Slurm.**
Kubernetes hosts the Hub, Astro/Django, ACP, ingress and monitoring services,
not user notebook kernels or batch scientific compute. Portal origin:
**https://quantum.nyameko.com**. Do not revert to the legacy users subdomain.

## GitOps/source boundary

* OpenStack desired state: Terraform in this repository. The public
  `terraform/environments/template` is a reference; merge its two new
  `slurm_cpu_03/04` entries and `compute_64c_flavor` variable into the
  **private** environment without overwriting existing provider or state files.
* Host desired state: `ansible/playbooks/slurm.yml`, protected private
  inventory, and the Slurm roles. The example inventory is **not** the
  production inventory. Keep the private inventory and Terraform state private.
* Kubernetes application desired state: Argo CD. M1 does not install
  JupyterHub or start user compute in Kubernetes.

## Verified capacity from 23 September 2026 operator evidence

OpenStack reports `C64.xlarge` as 64 vCPUs / 262144 MiB RAM.
The 14 reported existing VMs consume 128 vCPUs / 409600 MiB.
Two C64.xlarge instances would consume another 128 vCPUs /
524288 MiB. That gives 256/260 vCPUs and 933888/1080000 MiB
against the reported project limits, leaving only **4 vCPUs** and
146112 MiB. **The arithmetic does not prove the Nova scheduler has
enough physical capacity**: verify placement, cores/CPU-overcommit and
per-flavor quotas before apply. The Cinder quota is a separate limit.

## Database and identity

Quantum Platform's existing PostgreSQL database remains the source of truth
for account identity, programme membership, public SSH/WireGuard keys,
provisioning state, and user-profile metadata. Do not copy password hashes,
MFA secrets or private keys to Slurm.

The Slurm accounting database is a separate **MariaDB/MySQL** database used
by `slurmdbd` for clusters, accounts, associations, QoS, allocations and
job history. No second portal PostgreSQL database is needed. An auditable,
idempotent provisioning worker maps approved Quantum Platform users to
Unix identities and Slurm associations. Slurm controls allocation and job
state; the portal never invents available compute capacity.

Do not grant Slurm database access directly to Astro, Django or JupyterHub.
Future portal reads should go through a constrained service interface or
`slurmrestd` with server-side per-user authorization.

## Required shared home and persistent SSD design

A Cinder `ReadWriteOnce` volume cannot simply be attached and mounted
read-write on all Slurm login/compute hosts. A filesystem on such a volume
cannot be shared by adding more Kubernetes PVC mounts. For M1 use a
dedicated, private storage service with one Cinder-SSD-backed filesystem
exported as NFSv4 to `login1/2` and all compute nodes (or a supported
shared/parallel filesystem backed by persistent SSD storage).

The service owns the Cinder attachment. Every user gets a private
`/home/<stable-linux-username>` directory with consistent UID/GID, POSIX
permissions, ACL/quota policy, automated backup and restore testing.
Never mount the block volume simultaneously on multiple hosts. Do not
put this shared user data inside the portal's PostgreSQL PVC.

Before promoting the NFS approach to MPI production, benchmark metadata,
IOPS and aggregate throughput; high-throughput MPI scratch should use
a separate filesystem or dedicated local scratch with explicit stage-in/out.
Do not mistake a single NFS VM for a highly available parallel filesystem.

The Ansible playbook **refuses to enable user jobs** when `/home` is local.
Provision and mount persistent shared homes first. The new `slurm-common`
role checks `findmnt` on login/compute nodes.

## Operator deployment steps

1. In the **private** Terraform environment, copy the two `slurm_cpu_03`
   and `slurm_cpu_04` entries, set `compute_64c_flavor = "C64.xlarge"`,
   and apply the scoped security-group additions. Verify that proposed
   `10.50.0.32` and `10.50.0.33` are unused. Take a state backup.
2. Run `terraform fmt -check`, `terraform validate`,
   `terraform plan -out=m1.tfplan`. Review `terraform show m1.tfplan`.
   No existing resources should be replaced or deleted. Apply only
   the reviewed plan. Verify both VMs have the required vCPU/RAM.
3. Extend the private Ansible inventory with the two nodes using
   `ansible/inventories/example-slurm-hosts.yml`. Add the
   `slurm_cluster` group or load `group_vars/slurm_cluster.yml`
   via the playbook's `vars_files`.
4. Select one **verified Rocky Linux 9 Slurm package repository/release**.
   Install and pin a compatible build on controller, login and compute
   nodes; verify package names with `dnf repoquery`. Override
   `slurm_*_packages` for that repository and set
   `slurm_package_version` to the exact `sinfo -V` version. Do not
   mix incompatible OpenHPC/EPEL/SchedMD builds.
5. Create the *same* MUNGE key on all hosts. Store only its base64 value
   as `slurm_munge_key_b64` in encrypted **private** Ansible Vault
   variables; set an independent `slurm_db_password` there. Never
   commit or log either secret. Install the community.mysql collection
   with `ansible-galaxy collection install -r ansible/requirements.yml`.
6. Configure private DNS for all seven hosts, synchronized clocks,
   consistent Slurm/MUNGE identities, consistent Unix users and group
   IDs, persistent shared `/home`, and firewall/security-group
   reachability for Slurm 6817/6818/6819 and restricted exporter 9100.
   Ensure the controller resolves its own configured hostname and address.
7. Run `ansible-playbook -i inventories/private/hosts.yml
   playbooks/slurm.yml --check --diff` from `ansible/`.
   Then run the playbook without `--check` after reviewing effects.
   The playbook gates on package release, protected MUNGE key, CPU/RAM
   contracts, shared home, database connectivity, and scheduler health.
8. Complete post-install acceptance below. Only then add
   JupyterHub Slurm-backed spawner profiles.

## Slurm acceptance

```bash
munge -n | unmunge
sinfo -N -o '%N %P %t %c %m'
scontrol show nodes
sacctmgr -nP show cluster format=Cluster
sacctmgr -nP show association
squeue
srun --partition=cpu-small --nodes=1 --ntasks=1 hostname
srun --partition=cpu-large --nodes=1 --ntasks=1 hostname
```

For an MPI acceptance, ensure the same compatible MPI/PMIx runtime
and libraries are present on all participating hosts, stable shared
homes, and expected inter-node network access. Test a two-node
`srun --mpi=pmix ...` only after `srun --mpi=list` confirms support.
Verify multi-node output, process placement, `sacct` records, and
that all nodes recover to `IDLE`.

## Observability

The Prometheus `slurm-hosts` static job targets controller, both
login nodes and four compute nodes on private `:9100`. Install and
verify a **version-pinned** node_exporter service on each before
enabling alert rules. No user notebook content, credentials or public
keys should appear in metric labels. Scheduler metrics need a compatible
Slurm exporter with known metric names, followed by GitOps dashboards
for scheduler partitions, queue depth, job efficiency and accounting.
Wazuh agents should enroll new persistent nodes using the existing
agent playbook; Suricata belongs at the relevant visibility boundary,
not separately on every compute node.

## M2 contract, fixed now

All notebook sessions (including 1 vCPU/2 GiB development profiles)
must request Slurm allocations, obey Slurm QoS, consume accounting,
and terminate on expiration or cancellation. The Hub remains a
Kubernetes service; notebook kernels/servers run on the allocated
Slurm compute node. Use Quantum Platform OIDC/MFA and stable Linux
username mapping. A 32-vCPU/128-GiB/1-hour session is one illustrative
profile. Kubernetes must not silently run fallback user compute.

## Future integrations

A100/H200 join as separate Slurm partitions after CPU-only acceptance.
Open OnDemand contributes interactive-app and batch-connect patterns;
OpenHPC contributes packaged cluster recipes and operations practices.
Neither replaces the platform's unified research identity, Slurm
accounting, quantum workflows and future QRMI/QDMI QPU dispatch.

## Private-variable precedence and staging

The playbook explicitly loads public `group_vars/slurm_cluster.yml`, whose
secret placeholders are intentionally empty. Supply the encrypted **private**
overrides as extra vars so they take precedence. Example (from `ansible/`):

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventories/private/hosts.yml \
  playbooks/slurm.yml --ask-vault-pass \
  -e @inventories/private/slurm-secrets.vault.yml --syntax-check
ansible-playbook -i inventories/private/hosts.yml \
  playbooks/slurm.yml --ask-vault-pass \
  -e @inventories/private/slurm-secrets.vault.yml --check --diff
```

The protected file should contain `slurm_munge_key_b64` (base64 of the
same **1024-byte random binary key** for all Slurm hosts),
`slurm_db_password`, and any package list/version overrides.
Do not paste the actual key or passwords into shell history or issue/PR
comments. **Ansible check mode does not replace a full runtime test**:
some database/service commands depend on packages already installed.
Use the private inventory and vault only after the required shared
filesystem is mounted and backed up.

In the reference Nova quota, the two large compute VMs leave just
four vCPUs. A new C4 storage VM would exhaust that vCPU quota; request
quota headroom or use an approved existing storage/Manila service before
provisioning a dedicated Cinder-backed NFS gateway.
