# M4a personal-worker auto-rollout (development only)

This Kustomize package owns exactly one Deployment:
`agent-control-plane-personal-worker`.

The parent `agent-control-plane` Argo Application must **not** include the same
Deployment, to avoid competing owners. The separate
`agent-control-plane-personal-worker` Application is automatically synced,
but the parent Application retains **manual** sync and its PostgreSQL/migration
resources are not exposed to this auto-rollout.

## Flow

1. A developer merges reviewed ACP source into the ACP `dev` branch.
2. ACP GitHub Actions CI must succeed; the subsequent Container images
   workflow publishes both `sha-<source-commit>` images to GHCR.
3. A five-minute scheduled workflow in this **infrastructure repo** checks the
   current ACP `dev` commit and verifies **both** immutable-by-convention
   tags exist in GHCR. No images are downloaded onto blackmyth or k8s-cp-01.
4. The workflow edits only the worker Deployment image reference and commits
   that single file directly to infra `main`. This commit is the audit trail.
5. The isolated Argo Application observes the changed Git manifest and
   reconciles only that Deployment. `imagePullPolicy: Always` ensures a new Pod
   contacts GHCR.
6. Verify on `k8s-cp-01` with `kubectl -n agent-control-plane get pods
   -l acp-role=personal-worker` and compare `imageID`.

No hand-written Git commit SHA annotation is needed. The primary ACP API and
administrative Hermes StatefulSet remain on their own existing GitOps policies.

## Initial activation / operational cautions

- **Human review and approval of this automation PR is required** before it
  is promoted to infrastructure `main`, which is the root Application's source.
- Move ownership of the Deployment out of the parent Application before enabling
  the child auto-sync; the parent is manual and `prune` is disabled by default.
- The workflow needs `GITHUB_TOKEN` with repository Contents **Read and write**
  permission, and a branch policy that permits bot commits to `main`. If
  direct bot pushes are prohibited, use a PR-based release gate rather than
  bypassing branch protection.
- The two GHCR packages must be readable by the GitHub-hosted runner.
  Missing image tags result in a no-op, NOT a rollout.
- Scheduled GitHub Actions runs can be delayed; this is eventual delivery,
  not an instantaneous event-driven webhook.
- Only enable this for the explicitly approved development worker. Do not
  expand it to the ACP API, PostgreSQL, migrations, or production workloads.
- The generated bot commit may not trigger other workflows when made using
  `GITHUB_TOKEN`. It is constrained to one existing image field, and the
  reviewed automation workflow validates the exact file diff.
- If a personal turn is active during a Recreate rollout, ACP may mark it
  `worker_interrupted`. Do not use this policy for stable researcher service
  without draining / coordination.

## One-time control-plane verification

On `k8s-cp-01`, verify Argo owns the single worker and status is healthy:

```sh
kubectl -n argocd get applications agent-control-plane agent-control-plane-personal-worker
kubectl -n agent-control-plane rollout status deployment/agent-control-plane-personal-worker --timeout=180s
kubectl -n agent-control-plane get pods -l acp-role=personal-worker -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].imageID}{"\\n"}{end}'
```

To stop automated rollouts, suspend the scheduled workflow and disable
`spec.syncPolicy.automated` on the child Application through the approved
GitOps process.
