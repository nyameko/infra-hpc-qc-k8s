# M2a Tutorial — KubeSpawner with a shared NFS research home

Status: validated on 2026-09-28.

## Goal

Run JupyterHub in Kubernetes with disposable KubeSpawner notebook pods while
keeping the researcher's canonical POSIX home on shared NFS:

```text
browser
  -> JupyterHub / KubeSpawner
  -> ephemeral user Pod
  -> /home/research/<user>
  -> shared NFS

SSH / Slurm
  -> /home/research/<user>
  -> the same shared NFS
```

The notebook process is ephemeral. User files are not.

## 1. Platform operating model

Git, Terraform and Ansible are operated from the admin workstation. Kubernetes
manifests flow through GitHub and Argo CD. The Kubernetes control-plane host is
used for `kubectl` inspection and live cluster actions; it does not need a Git
checkout.

## 2. Permit Kubernetes workers to reach NFS

The storage NFS security group must allow TCP/2049 from the Kubernetes worker
security group. Apply only after verifying Terraform proposes no unrelated
changes.

The NFS server exports the research filesystems to both the existing
management/HPC client network and the Kubernetes worker network. Real CIDRs
remain in private variables.

```bash
cd ansible
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/storage-nfs-exports.yml
```

## 3. Validate NFS from every Kubernetes worker

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-storage.yml
```

The playbook verifies DNS, TCP/2049, NFSv4.2 mounting and cleanup by temporarily
mounting `storage.internal:/srv/home` read-only on every worker.

A successful result resembles:

```text
storage.internal:/srv/home nfs4
ro,nosuid,nodev,...vers=4.2...
clientaddr=<K8S_WORKER_IP>
addr=<STORAGE_IP>
```

### Why a client root user cannot read every research home

The export uses `root_squash`. Client UID 0 is mapped to the anonymous NFS
identity, so root on a login or Kubernetes node cannot bypass a `0700` home
owned by another UID. That is expected security behavior. Perform authoritative
filesystem administration on the storage server itself.

## 4. Provision one consistent POSIX research identity

Keep the real assignment in protected vars:

```yaml
research_users:
  - name: <RESEARCH_USER>
    uid: <UID>
    gid: <GID>
    shell: /bin/bash
    home_mode: "0700"
```

Check the UID/GID are unused, then provision them everywhere a POSIX process can
run:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/research-identities.yml \
  -e @inventories/private/research-users.yml
```

The user and primary group are created consistently on the Slurm controller,
login nodes, compute nodes and storage server. The physical home is created only
on storage at `/srv/home/<user>`; login and compute nodes see it through the
existing NFS mount as `/home/research/<user>`.

## 5. Keep BatchSpawner and KubeSpawner from fighting

The legacy BatchSpawner Application is retained for future interactive-HPC use,
but its Deployment is parked at zero replicas and it no longer owns the live
Jupyter ingress.

The primary M2a path uses uniquely named objects:

```text
Deployment/jupyterhub-workbench
Service/jupyterhub-workbench
ConfigMap/jupyterhub-workbench-config
PVC/jupyterhub-workbench-data
Ingress/jupyterhub-workbench
```

Verify:

```bash
kubectl -n jupyterhub get deployment,service,ingress,pvc,configmap
```

Expected core state:

```text
deployment/jupyterhub             0/0
deployment/jupyterhub-workbench   1/1
```

and only `Ingress/jupyterhub-workbench` should own
`jupyter.quantum.nyameko.com`.

## 6. Bootstrap one Jupyter researcher

For M2a, create the temporary Jupyter authentication Secret directly on the
cluster. The UID/GID must match the POSIX identity provisioned above.

```bash
kubectl -n jupyterhub create secret generic \
  jupyterhub-workbench-bootstrap \
  --from-literal=username='<RESEARCH_USER>' \
  --from-literal=uid='<UID>' \
  --from-literal=gid='<GID>' \
  --from-literal=password='<TEMP_PASSWORD>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Do not commit this Secret. Quantum Platform provisioning replaces this bootstrap
step in the next milestone.

## 7. Verify the real shared home from Jupyter

Inside the spawned Jupyter terminal:

```bash
id
echo "$HOME"
pwd
stat -c '%u:%g %a %n' "$HOME"
mkdir -p ~/notebooks
touch ~/notebooks/m2a-persistence.ipynb
touch ~/phase-d-persistence.txt
```

Then from a login node:

```bash
sudo -iu <RESEARCH_USER>
ls -la
```

The same files must be present.

Validated M2a evidence showed the research home surviving with:

```text
notebooks/
phase-d-persistence.txt
```

## 8. Prove Jupyter is disposable

Inspect the running Hub:

```bash
kubectl -n jupyterhub get pods -o wide
```

Restart it:

```bash
kubectl -n jupyterhub rollout restart deployment/jupyterhub-workbench
kubectl -n jupyterhub rollout status deployment/jupyterhub-workbench
```

After rollout, return to the login node as the research user and verify the
files still exist.

This proves the key contract:

```text
ephemeral Kubernetes/Jupyter process
              !=
persistent researcher state
```

## 9. Validated milestone

The M2a milestone established:

- NFS is reachable and mountable from all Kubernetes workers.
- the same numeric research identity exists across SSH, Slurm and storage;
- the authoritative research home is shared across SSH and Jupyter;
- KubeSpawner runs on today's shared Kubernetes worker pool;
- the JupyterHub Deployment can be replaced without losing user data;
- BatchSpawner remains available as a future niche path without competing with
  the primary workbench.

## 10. Next step

The next architecture slice is not a larger notebook Pod:

```text
research workbench
      -> logical execution request
      -> execution API / quantum-workflows
      -> Slurm CPU/GPU or QPU provider
```

That keeps expensive resources allocated only while scientific work is actually
executing.
