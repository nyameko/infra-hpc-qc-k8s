# Kubernetes, GitOps and immutable application releases

## Ownership order

Terraform creates provider resources; Ansible configures host and kubeadm; Cilium supplies networking; Cinder CSI provides persistent Kubernetes volumes; Argo CD reconciles workloads and operational services. A user should never need to manually apply YAML to obtain a Jupyter notebook. Application code lives in its owning repository; the infrastructure repository deploys its image with reviewed manifests.

The Argo root Application and per-service declarations are under `argocd/bootstrap/` and `argocd/applications/`. Use the corresponding `argocd/resources/` definitions for services including ingress, monitoring, databases, JupyterHub, Quantum Platform, ACP and LiteLLM.

## Safe read-only checklist

```sh
kubectl get nodes -o wide
kubectl -n argocd get applications
kubectl -n argocd get application <APP> -o yaml
kubectl -n <NAMESPACE> get deployments,pods,services
kubectl -n <NAMESPACE> get events --sort-by=.lastTimestamp
```

Review the application source revision, image **digest**, health, sync, observed Pod imageIDs, mount/PVC state, logs and database migration level. A source branch name, image channel and live deployment digest are different concepts. A GitHub PR being merged does not change a running Pod by itself. Argo `OutOfSync/Healthy` is not equivalent to a failed application; inspect the actual resource delta.

## Release procedure

Create a feature PR with tests and manifest impact; build and pin the image; stage any reversible schema expansion; review GitOps diff; promote to the correct environment; observe rollout readiness and subsystem acceptance; document rollback and source/image provenance. Do **not** perform force sync/prune, broad restarts, database migration or `kubectl apply` as part of a read-only diagnosis.

## Storage and secrets

A persistent service PVC is not a replacement for the research NFS home. Commit only properly sealed ciphertext and non-secret manifests; preserve controller recovery keys and recoverable credential originals in protected custody. Never read/reprint Secret values to a public incident ticket.

Sources: [Argo overview](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/argocd/README.md), [GitOps tutorial](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/04b-argocd-gitops-secrets-ksops.md), [Cinder CSI boundary](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/04a-cinder-csi-and-the-ansible-to-gitops-boundary.md), [versions](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/VERSIONS.md).