# Storage, data durability and recovery

## Three distinct classes

**Research files:** POSIX-owned NFS/XFS research home shared by login, compute and Jupyter; not a disposable Jupyter volume. **Platform databases:** application PostgreSQL with separate schemas/roles, migrations and backup strategy; a DB snapshot needs consistent restore and key custody. **Kubernetes service storage:** Cinder CSI-backed volumes and other PVCs for application services; capacity does not imply full research-home backups.

## Research identity and NFS

The same approved Quantum Platform research identity maps to a stable UNIX UID/GID across the login nodes, Slurm workers, KubeSpawner pods and NFS server. Never fix `Permission denied` by making the user home world-writeable or assigning an arbitrary different UID. Diagnose UID/GID and mount consistency:

```sh
id
findmnt /home/research
stat -c '%u:%g %a %n' "$HOME"
df -h "$HOME"
```

An administrator can inspect server export and mount state with `exportfs -v` and `findmnt` on the correct host. Avoid sharing a live export map in a public issue.

## Database state

Quantum Platform and ACP store different canonical records. PostgreSQL migrations must be checked against deployed images and schemas; a readiness probe may accept older versions. Before a migration, confirm checksums, role permissions, backups, rollback compatibility and any affected personal/project data.

## Disaster recovery gates

A successful backup job is insufficient. A trusted operator should periodically restore from an encrypted backup into an isolated environment, verify database integrity, research file ownership/permissions, SealedSecrets controller keys, signed certificate paths, service connectivity and a basic user/job test. Backups without recoverable secrets may be unusable.

Sources: [storage/NFS guide](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/m1-storage-nfs-xfs.md), [credential custody](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/credential-stores-and-recovery.md), [private-state recovery](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/private-state-disaster-recovery.md), [Cinder CSI tutorial](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/04c-deploying-cinder-csi-using-argocd.md).