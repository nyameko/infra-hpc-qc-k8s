# Optional BatchSpawner / interactive-HPC Jupyter path

These manifests are retained for the niche case where the Jupyter single-user
server itself must run inside a Slurm allocation.

They are **not** the default live Jupyter deployment and must not be registered
through the app-of-apps tree in their current form. The production M2a path is
`argocd/resources/jupyterhub-workbench` using KubeSpawner.

Before re-enabling BatchSpawner, give it a distinct Application name,
namespace, Service/Ingress/PVC names and hostname so it cannot collide with the
workbench deployment.
