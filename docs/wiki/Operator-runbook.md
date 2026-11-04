# Operations and release runbook

## Read-only cluster triage

On the designated Kubernetes administration host:

```sh
kubectl get nodes -o wide
kubectl -n argocd get applications
kubectl -n quantum-platform get deploy,pods,svc
kubectl -n agent-control-plane get deploy,pods,jobs
kubectl -n monitoring get pods
```

Inspect one application before acting: `kubectl -n argocd get application <APP> -o yaml`; compare its desired Git revision, reported sync and health, resources, deployed image digest, admission events and corresponding application logs. Argo `Healthy` is not a migration/schema or functional acceptance assertion. Avoid dumping Secret YAML, token-bearing env or private research data into tickets.

## Deployment discipline

1. Create a feature change and an evidence-backed PR; review Terraform, Ansible, Helm, Kubernetes, documentation and security impact.
2. Validate static tests and image builds independently.
3. Stage changes on the intended branch/environment and verify immutable image digests and migration prerequisites.
4. Observe Argo diff before sync; protect database jobs against wrong order, re-entry or downgrade.
5. Promote only with a defined rollback strategy and after integration tests for identity, workbench, Slurm and ACP continuity.
6. Record expected versus observed versions, test timestamps and operators in release evidence. A green PR is not runtime proof.

Use `kubectl rollout status` for observation; a `rollout restart`, prune/force-sync or secret rotation is a change and needs approval. In a multi-operator environment, do not repair drift by blindly overwriting another operator's changes.

## Daily operational questions

| Symptom | First subsystem |
|---|---|
| Host unreachable | VPN/Neutron SG/edge nftables/routes |
| Portal HTTP failure | ingress/service/Pod/PostgreSQL |
| Jupyter spawn stalls | identity, hub, KubeSpawner, PVC/NFS |
| Slurm pending | account, QOS, partition, limits, backfill |
| Result missing | workflow artifact path and NFS permissions |
| Agent chat disappears | ACP authorization, migrations, PostgreSQL |
| GPU image cannot run | scheduler placement, runtime/driver/CUDA, quota |

For procedures see [installation](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/INSTALLATION.md), [M4 operator readiness](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/15-m4-live-readiness-and-memory-activation.md) and [credential recovery](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/credential-stores-and-recovery.md).