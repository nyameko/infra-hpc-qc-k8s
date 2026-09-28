# M2a Phase B/C/D — shared home, KubeSpawner and persistence

This runbook reflects the actual operating model:

- Git + Argo CD own Kubernetes manifests.
- `kubectl` is run from `k8s-cp-01` for live inspection/actions only.
- There is no Git checkout and no need for one on the control-plane node.
- Phase B validates NFS from the Kubernetes **hosts** with Ansible.
- Phase C/D validate read/write persistence using the real bootstrap research identity and a real KubeSpawner workbench.

## Phase B — host-level NFS preflight

The NFS export must permit both the management/HPC client network and the
Kubernetes worker network. Keep the actual CIDRs in protected vars.

Update only the exports:

```bash
cd ansible

ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/storage-nfs-exports.yml
```

Then validate all existing Kubernetes workers:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes-storage.yml
```

That playbook:

1. installs `nfs-utils`;
2. resolves `storage.internal`;
3. verifies TCP/2049;
4. mounts `storage.internal:/srv/home` read-only at a temporary host path;
5. verifies the mount with `findmnt`;
6. unmounts it and removes the temporary directory.

It deliberately does **not** create a synthetic research user, write into a
0700 home, create a Kubernetes Pod, or require repository files on the control
plane.

### Why root could not inspect the old jhub-smoke directory

The research export uses `root_squash`. Root on a client is mapped to the NFS
anonymous identity and therefore cannot bypass a `0700` directory owned by
another UID. That is expected and desirable. A process running as the matching
UID could access it; the old `setpriv` write proved that, but it is not part of
the production-shaped validation path anymore.

Phase B is green when every Kubernetes worker reports a verified temporary
read-only NFSv4 mount and leaves no persistent mount behind.

## Phase C — real bootstrap research identity + KubeSpawner

### C1. Provision one consistent POSIX identity

Do not hand-create a user on one login node. Put the bootstrap researcher in a
protected vars file, for example:

```yaml
research_users:
  - name: nlisa
    uid: <UNUSED_UID>
    gid: <UNUSED_GID>
    shell: /bin/bash
    home_mode: "0700"
```

Check the chosen UID/GID are unused, then run:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/research-identities.yml \
  -e @inventories/private/research-users.yml
```

This creates the same POSIX identity on the Slurm controller, login nodes,
compute nodes and storage server, and creates the authoritative
`/srv/home/nlisa` only on storage. The login/compute hosts see that home
through the existing NFS mount.

### C2. Bootstrap Jupyter authentication privately

The workbench reads username, UID, GID and temporary password from
`Secret/jupyterhub-workbench-bootstrap`. Create it directly on the cluster for
the MVP; do not commit it.

On `k8s-cp-01`:

```bash
kubectl get namespace jupyterhub >/dev/null

kubectl -n jupyterhub create secret generic jupyterhub-workbench-bootstrap \
  --from-literal=username=nlisa \
  --from-literal=uid='<UID>' \
  --from-literal=gid='<GID>' \
  --from-literal=password='<HIGH_ENTROPY_TEMP_PASSWORD>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

M3 replaces this bootstrap with Quantum Platform identity/provisioning.

### C3. Argo CD ownership

Only **one live Jupyter implementation** may own a resource set.

The primary live path is:

```text
Application/jupyterhub-workbench
  -> argocd/resources/jupyterhub-workbench
  -> uniquely named jupyterhub-workbench objects
  -> KubeSpawner
```

The legacy BatchSpawner design is retained in Git as an optional/niche path but
must not own the same Deployment, Service, PVC, ConfigMap or Ingress.

After the corrective PR is merged into the branch tracked by Argo, inspect from
`k8s-cp-01`:

```bash
kubectl -n argocd get applications jupyterhub jupyterhub-workbench
kubectl -n jupyterhub get deploy,svc,ingress,pvc,cm
```

The workbench objects should be named `jupyterhub-workbench*`.

### C4. Spawn the real workbench

Open the private Jupyter endpoint and log in as `nlisa`.

Inside the Jupyter terminal:

```bash
id
echo "$HOME"
pwd
stat -c '%u:%g %a %n' /home/research/nlisa
mkdir -p ~/notebooks
printf 'phase-c jupyter write\n' > ~/phase-c-from-jupyter.txt
```

Expected:

- the pod runs with the provisioned numeric UID/GID;
- `$HOME=/home/research/nlisa`;
- the file is immediately visible from `login1` as `nlisa`.

From `login1`:

```bash
sudo -iu nlisa
cat ~/phase-c-from-jupyter.txt
```

That is the first meaningful read/write proof because it uses the real identity
that will also submit Slurm/quantum-workflows jobs.

## Phase D — prove pod ephemerality and home persistence

Inside Jupyter create/save:

```text
~/notebooks/m2a-persistence.ipynb
~/phase-d-persistence.txt
```

On `k8s-cp-01`, identify the single-user pod:

```bash
kubectl -n jupyterhub get pods -o wide
```

Stop the server from JupyterHub, or delete only that user pod:

```bash
kubectl -n jupyterhub delete pod <single-user-pod>
```

Spawn again and verify both files remain.

Then restart only the Hub:

```bash
kubectl -n jupyterhub rollout restart deployment/jupyterhub-workbench
kubectl -n jupyterhub rollout status deployment/jupyterhub-workbench
```

Log in/spawn again and verify the same home/files.

## Acceptance gate

- every Kubernetes worker can mount the NFS export read-only at host level;
- no temporary NFS test Pod or fake user is required;
- `nlisa` has one consistent UID/GID across login, Slurm and storage;
- KubeSpawner creates a real workbench pod on the shared worker pool;
- the workbench mounts the same `/home/research/nlisa` used by SSH/Slurm;
- files written from Jupyter are immediately visible through SSH;
- deleting/recreating the user Pod does not delete notebooks or user data;
- restarting the Hub does not delete user data;
- the user Pod has no Kubernetes service-account token;
- the user Pod contains no MUNGE key, Slurm admin credential or QPU provider secret.

After this gate the next slice is the bounded workbench -> execution API ->
`quantum-workflows` -> Slurm path.
