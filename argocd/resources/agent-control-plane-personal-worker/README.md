# ACP personal worker: single-owner GitOps deployment

The personal worker is the only Deployment in this child Argo application.
Its auto-sync **does not** own the ACP API, Hermes admin StatefulSet, database
or migration Job. The parent ACP application owns those resources.

Production watches `infra-hpc-qc-k8s/main`; changes and generated image
promotions are proposed as PRs **to dev only**. Both the worker and its init
container must use the same immutable Hermes digest as the parent ACP
Kustomization. The source-to-digest workflow updates these three references
in one reviewed PR.

A PreSync schema-check Job runs **before** any replacement of this `Recreate`
Deployment, using the same pinned Hermes image and restricted `acp-db-app`
credential. If its source-required schema is not installed, Argo stops the
child application sync and preserves the existing healthy worker. The worker
init container provides a second check if selective sync bypasses hooks.

The parent auto-sync migration hook is separately approval-capped so
unreviewed schema upgrades are blocked. The child PreSync check does not run
migrations or approve one; it is a deployment guard, not a substitute for DB
backup or a tested restore procedure.

An Argo **selective sync skips hooks** and MUST NOT be used to force this
Deployment ahead of a migration. When the preflight fails on an old revision,
Argo will not automatically retry the same failed commit; after an approved
migration, the operator must cause a reviewed new revision or explicitly
retry the child sync. Confirm schema before trying either operation.

The worker uses `Recreate` due to its singleton PostgreSQL advisory lock.
Rollouts may interrupt in-flight research assistant turns; verify them in ACP
after rollout.

**Current release safety:** PR #259 promoted the automatic deployment policy
to infra `main`. The last **observed** live schema was v4, while the current
source includes v8; actual post-promotion cluster state remains unverified.
If the worker was already replaced by #259 and is waiting in init, this new
PreSync hook cannot restore that Pod. Inspect live state and follow the
approved recovery/migration path; do not force-sync or delete PVCs.
Do not promote further worker changes until operator-reviewed migration and
restore-test evidence are complete.

See [ACP GitOps automation](../../../docs/architecture/acp-gitops-digest-automation.md)
for the source/image/approval/reconciliation process and recovery gates.
