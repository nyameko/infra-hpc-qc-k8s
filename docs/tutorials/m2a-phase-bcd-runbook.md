# M2a Phase B/C/D — shared home, KubeSpawner and persistence

This runbook is anchored to dev commit
`381c91e3dd989b3ebd4e1b38cae7588564517870`.

Today's MVP deliberately uses the existing shared Kubernetes workers. It does
not add/taint workers and does not remove Slurm capacity.

## Phase B — prove Kubernetes ↔ research NFS before JupyterHub

### B1. Private export inputs

Keep the real networks in protected vars, for example:

```yaml
storage_nfs_export_cidrs:
  - "<MGMT_CIDR>"
  - "<K8S_CIDR>"
```

Do not commit those values.

Update only the export file; this playbook does not inspect/format/mount Cinder
filesystems:

```bash
cd ansible
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/storage-nfs-exports.yml \
  -e @inventories/private/storage-private.yml
```

### B2. Prepare existing Kubernetes workers

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-storage.yml
```

This installs `nfs-utils`, verifies `storage.internal` resolves from each
worker and verifies TCP/2049 is reachable. If this fails, stop here: do not
debug JupyterHub yet.

### B3. Create a disposable smoke home

On the storage server:

```bash
sudo install -d -m 0700 -o 20999 -g 20999 /srv/home/jhub-smoke
```

From a login node, create a reverse-direction marker:

```bash
sudo -u '#20999' sh -c \
  'printf "phase-b ssh write\n" > /home/research/jhub-smoke/phase-b-from-ssh.txt'
```

### B4. Run the standalone Kubernetes NFS smoke pod

Run kubectl from `k8s-cp-01`:

```bash
kubectl apply -f argocd/resources/jupyterhub-workbench/namespace.yaml
kubectl apply -f tests/kubernetes/jupyter-nfs-smoke.yaml
kubectl -n jupyterhub wait --for=condition=Ready pod/jupyter-nfs-smoke --timeout=90s
kubectl -n jupyterhub logs jupyter-nfs-smoke
```

Then verify both directions:

```bash
# Kubernetes sees the SSH marker
kubectl -n jupyterhub exec jupyter-nfs-smoke -- \
  cat /home/research/jhub-smoke/phase-b-from-ssh.txt

# SSH/login sees the Kubernetes marker
cat /home/research/jhub-smoke/phase-b-from-kubernetes.txt
```

If those pass, Phase B is green. Delete only the pod; the files must remain:

```bash
kubectl -n jupyterhub delete pod jupyter-nfs-smoke
ls -l /home/research/jhub-smoke/phase-b-from-*.txt
```

## Phase C — deploy JupyterHub + KubeSpawner on shared workers

The workbench images for the anchor commit were successfully built/published by
the dev image workflow. KubeSpawner no longer requires a `node-pool=jupyter`
label today; an optional selector remains for the later dedicated pool.

### C1. Choose one private bootstrap researcher

For the first production-shaped test you may use `nlisa`, but reserve one
numeric UID/GID and use the same values everywhere. Verify they are unused
before assigning them:

```bash
getent passwd <UID> || true
getent group <GID> || true
```

Create the authoritative home on storage:

```bash
sudo install -d -m 0700 -o <UID> -g <GID> /srv/home/nlisa
```

This is still bootstrap identity plumbing. M3 will make Quantum Platform
authoritative for the mapping; do not create a second Jupyter-only home.

### C2. Create the bootstrap Secret privately

From `k8s-cp-01` after the namespace exists:

```bash
kubectl -n jupyterhub create secret generic jupyterhub-bootstrap \
  --from-literal=username=nlisa \
  --from-literal=uid='<UID>' \
  --from-literal=gid='<GID>' \
  --from-literal=password='<HIGH_ENTROPY_TEMP_PASSWORD>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Do not commit this Secret. Once the MVP is green, seal it with the existing
SealedSecrets workflow or replace it entirely with M3 identity integration.

### C3. Merge this branch to dev, then register the Argo application

The root app currently tracks `main`, while the JupyterHub application itself
tracks `dev`. Therefore during development explicitly register it once:

```bash
kubectl apply -f argocd/applications/jupyterhub-workbench.yaml
kubectl -n argocd get application jupyterhub-workbench
```

Watch the deployment:

```bash
kubectl -n jupyterhub get resourcequota,limitrange
kubectl -n jupyterhub get pvc
kubectl -n jupyterhub get pods -w
```

Expected Hub budget: 250m CPU / 512Mi request. Expected user workbench: 100m CPU
/ 1 GiB request, 2 CPU / 4 GiB limit. The namespace quota prevents the MVP from
consuming the shared worker pool uncontrollably.

### C4. Login and spawn

Open the private Jupyter ingress and log in with the bootstrap credentials.
For `nlisa`, verify from a terminal inside Jupyter:

```bash
id
echo "$HOME"
pwd
stat -c '%u:%g %a %n' /home/research/nlisa
touch /home/research/nlisa/phase-c-from-jupyter
```

Expected `HOME` and working directory are `/home/research/nlisa`.

## Phase D — prove ephemerality and persistence

Create and save:

```text
/home/research/nlisa/notebooks/m2a-persistence.ipynb
/home/research/nlisa/phase-d-persistence.txt
```

Then stop the server from JupyterHub (or delete only the single-user pod):

```bash
kubectl -n jupyterhub get pods
kubectl -n jupyterhub delete pod <single-user-pod>
```

Spawn again and verify both files are unchanged.

Also verify through SSH/login:

```bash
ls -la /home/research/nlisa/
```

Finally restart only the Hub:

```bash
kubectl -n jupyterhub rollout restart deployment/jupyterhub
kubectl -n jupyterhub rollout status deployment/jupyterhub
```

Log in again and verify the same home/files. Hub state persists on its Cinder
PVC; researcher data persists on the shared research filesystem.

## Phase D acceptance gate

- NFS works from the existing Kubernetes workers.
- Kubernetes and SSH see the same files.
- KubeSpawner schedules on today's shared workers.
- the single-user pod runs with the configured numeric UID/GID.
- `$HOME == /home/research/<username>`.
- stopping/deleting the single-user pod does not delete user data.
- respawn presents the same notebook/files.
- Hub restart does not remove user data.
- no user pod receives a Kubernetes service-account token.
- no MUNGE key, Slurm admin credential or QPU provider secret exists in the
  workbench.

After this gate, the next slice is the bounded notebook → execution API →
`quantum-workflows`/Slurm path. That is where `nlisa` can submit the first
real workflow without keeping HPC resources allocated while thinking/coding.
