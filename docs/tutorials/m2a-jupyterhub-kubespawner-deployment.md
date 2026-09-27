# M2a — JupyterHub KubeSpawner workbench deployment

## Goal

Deploy the primary researcher notebook path:

```text
browser
  -> private JupyterHub
  -> KubeSpawner
  -> cheap workbench pod
  -> /home/research/<user>
  -> later execution/workflow API
       -> Slurm CPU/GPU
       -> QPU broker
```

The notebook pod is an IDE/workbench, not an HPC reservation.

## Prerequisites

1. Public topology sanitization is merged.
2. Three dedicated Jupyter workers are joined and Ready.
3. Nodes are labelled `node-pool=jupyter`.
4. `storage.internal` resolves privately to the NFS service.
5. NFS exports admit the Kubernetes worker network.
6. OpenStack security groups permit TCP/2049 from Kubernetes workers to storage.
7. `/srv/home/jhub-smoke` exists with UID/GID 20999.
8. The sealed bootstrap password exists.

## Node pool

For the first deployment use three 8-vCPU / 64-GiB workers. Do not taint them
until Cilium/CSI/monitoring DaemonSet tolerations have been verified.

Example:

```bash
kubectl label node <jupyter-worker-1> node-pool=jupyter
kubectl label node <jupyter-worker-2> node-pool=jupyter
kubectl label node <jupyter-worker-3> node-pool=jupyter
```

Label existing service workers `node-pool=core`.

## Bootstrap identity

M2a deliberately uses only `jhub-smoke`. Do not create a production researcher
manually. Create its shared home on the storage server with UID/GID 20999 and
mode 0700. M3 will replace this with Quantum Platform provisioning.

## Secret

Create a high-entropy temporary password locally, create the
`jupyterhub-bootstrap` Secret, seal it with kubeseal, and commit only ciphertext.

## Deploy

After images have been published and the Argo application points at the intended
branch:

```bash
kubectl -n argocd get application jupyterhub-workbench
kubectl -n jupyterhub get pods -w
```

## Acceptance gate

- Hub health probe is green.
- Login as `jhub-smoke` succeeds.
- user pod lands only on a `node-pool=jupyter` node.
- pod request is 250m CPU / 1 GiB; limit is 2 CPU / 4 GiB.
- user pod has no Kubernetes service-account token.
- `$HOME` is `/home/research/jhub-smoke`.
- file created in Jupyter is visible over SSH and survives pod deletion/re-spawn.
- user cannot read another researcher's home.
- idle culler stops an idle server without deleting the home.
- deleting the pod does not affect an independent Slurm job/workflow.
- NFS loss fails visibly rather than silently switching to ephemeral home.
- Hub restart preserves Hub state on Cinder.
- no MUNGE key or Slurm administrator credential exists in the Hub/user pod.

## Next slice

After this gate is green, add the authenticated execution client/API. The user
will request logical targets such as `qiskit-aer-large`; policy resolves those
to Slurm/container resources. Do not expose partitions/QoS as the normal
notebook programming interface.
