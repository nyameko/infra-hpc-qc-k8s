# ACP immutable-image GitOps automation (M4 release candidate)

**Status:** proposed on infra `dev`; not proof of a running rollout. All new
pull requests target `dev`. Production Argo applications watch infra `main`,
which must be promoted separately by the operator's normal reviewed process.

## Dependency and ownership boundaries

1. ACP source `main` CI must succeed. Its existing `images.yml` publishes
   **both** full-commit SHA-tagged GHCR images (API and Hermes).
2. The infra `acp-digest-promotion.yml` scheduled/manual workflow reads the ACP
   `main` source SHA and inspects the *published* OCI manifest digests of
   `sha-<full-sha>` tags; it never builds or pushes upstream images.
3. The only promoted fields are the two immutable digests in the ACP parent
   Kustomization and the matching Hermes images of the personal worker **and**
   its schema-check init container. The update script rejects changed manifest
   shapes, invalid digests or a missing paired image.
4. Automation opens/updates an infra PR **against dev only**. It never merges,
   pushes to `main`, calls Kubernetes, invokes a migration, or installs secrets.
   The reviewer's production promotion remains `dev -> main`.
5. Only infra `main` drives Argo CD. The ACP parent Application uses
   `automated: {prune: false, selfHeal: true}`. Its existing Sync-wave-1
   schema hook precedes API/Hermes wave 2; PostgreSQL, PVCs, secrets and durable
   history are never pruned by this Application.
6. The personal-worker child Application remains the sole owner of its Deployment.
   Its auto-update init container reads the schema via the existing restricted
   application database credential and waits for the **exact schema version
   packaged in its image** before starting the worker.

## Schema upgrade safety: current v4 is NOT cleared for automatic v8

The operator observed production schema versions `1,2,3,4` on 6 Nov 2026.
The current ACP release source contains migrations through v8.

The parent's migration hook now checks the **highest schema version shipped in
the selected image** against the separately approved migration ceiling. Initial
`ACP_APPROVED_MIGRATION_VERSION=4` deliberately blocks an unapproved v4 -> v8
migration. A blocked hook stops that Argo application sync before its API and
Hermes wave-2 workloads are changed.

For a schema-changing release, require an operator-reviewed migration PR to
`dev`, a **restorable off-PVC PostgreSQL backup**, a successful isolated
restore test, reviewed SQL/checksums and an explicit migration approval recorded
with the release. After those gates, either the operator runs the approved
versioned migration through the existing migration Job and verifies the ledger,
or raises the approved version ceiling in a separate reviewed infra PR before
promoting that approval to `main`. Do not bypass the gate by manually patching
Kubernetes resources or Argo objects.

A production schema already at the image's required version can pass the hook,
which continues checking historical migration checksums. Subsequent
**same-schema** image promotions are fully automated after `main` promotion.
A newly added schema version will fail closed until separately authorized.

The existing worker Deployment uses `Recreate` because its process holds an
exclusive PostgreSQL advisory lock. A rollout can interrupt in-flight personal
turns; schedule and verify accordingly. If the schema gate blocks the new init
container, worker availability may be reduced until an approved migration.
**Do not promote this deployment policy to production while the database is v4.**

## Verification gates

- GitHub Actions: source `main` CI and images workflow green; both paired
  published tags resolve to OCI digests; infra `manifests.yml` and
  `test_acp_image_digests.py` pass on the review branch.
- If `GITHUB_TOKEN` creates the automatic PR, GitHub does not automatically
  trigger additional PR workflows from that bot event. The workflow runs
  promoter tests itself; branch rules still require explicitly observed CI.
  Prefer a properly scoped GitHub App token if the repo policy requires normal
  PR-triggered checks. No bypass of branch protection.
- Production prior to promotion: verify off-cluster backup and restore evidence,
  migration approval, deployed/desired image refs, child application ownership
  and any in-flight runs. Review changes to both Argo applications.
- After approved promotion: confirm Argo synced/healthy, migration Job completed,
  `acp1.schema_version` is the expected version, both API and Hermes digests
  match the promoted Kustomization, and the worker Pod's *init and main*
  container images use the same Hermes digest.
- Run the existing ACP M4 tests: signed Guide turn, RLS/wrong-user denial,
  memory correction/revocation, browser-Jupyter-SSH UUID continuity, and
  Slurm run provenance. Healthy Pods are insufficient evidence.

## Recovery

- For an image-only regression, revert the reviewed infra image digest commit
  through `dev` and the usual production promotion. Never delete a PVC.
- For a migration regression, **do not apply reverse SQL or downgrade to
  schema-incompatible binaries**. Stop automatic promotion, preserve data,
  consult the tested restoration plan, and prefer an operator-reviewed forward
  repair migration.
- Emergency suspension: adjust Argo auto-sync only through the documented
  approved operational procedure, then record the corresponding GitOps fix;
  don't leave untracked live-state overrides.

Historical guide: [controlled v4 rollout](../releases/m4b-v4-controlled-rollout-2026-10-31.md).
