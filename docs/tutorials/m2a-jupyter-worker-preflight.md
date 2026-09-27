# M2a preflight — dedicated Jupyter workers and shared home

## Private environment inputs

The public Terraform template accepts a `jupyter_workers` map. Put actual node
names and fixed addresses only in the protected environment tfvars.

Example shape:

```hcl
jupyter_workers = {
  workbench_01 = {
    name     = "k8s-jupyter-01"
    fixed_ip = "<PRIVATE_ADDR>"
  }
  workbench_02 = {
    name     = "k8s-jupyter-02"
    fixed_ip = "<PRIVATE_ADDR>"
  }
  workbench_03 = {
    name     = "k8s-jupyter-03"
    fixed_ip = "<PRIVATE_ADDR>"
  }
}
```

They use the normal Kubernetes-worker security group and worker flavor unless a
different flavor is supplied privately.

## Join

Add the new hosts to the private Ansible `workers` inventory group and run the
existing Kubernetes prerequisite/join path. Do not publish that inventory.

After all three nodes report Ready, label them:

```bash
kubectl label node <jupyter-worker-1> node-pool=jupyter --overwrite
kubectl label node <jupyter-worker-2> node-pool=jupyter --overwrite
kubectl label node <jupyter-worker-3> node-pool=jupyter --overwrite

kubectl label node <core-worker-1> node-pool=core --overwrite
kubectl label node <core-worker-2> node-pool=core --overwrite
kubectl label node <core-worker-3> node-pool=core --overwrite
```

M2a intentionally does not taint the new pool yet. First verify that Cilium,
Cinder CSI, node-exporter and every required DaemonSet is present on each new
node.

## Shared home

The NFS role now accepts both management and Kubernetes client CIDRs. The
OpenStack storage security group also permits TCP/2049 from the Kubernetes worker
security group.

Before starting JupyterHub:

```bash
getent hosts storage.internal
showmount -e storage.internal
kubectl get nodes -l node-pool=jupyter
```

Create the smoke home on the authoritative storage server:

```bash
sudo install -d -m 0700 -o 20999 -g 20999 /srv/home/jhub-smoke
```

Do not create a separate Kubernetes PVC for the user's home.
