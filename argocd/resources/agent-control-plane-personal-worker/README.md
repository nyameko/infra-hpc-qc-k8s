# ACP personal worker: single-owner GitOps deployment

The personal worker is the only Deployment in this child Argo application.
Its auto-sync **does not** own the ACP API, Hermes admin StatefulSet, database
or migration Job. The parent ACP application owns those resources.

Production watches `infra-hpc-qc-k8s/main`; changes and generated image
promotions are proposed as PRs **to dev only**. Both the worker and its init
container must use the same immutable Hermes digest as the parent ACP
Kustomization. The source-to-digest workflow updates these three references
in one reviewed PR.

The schema-check init container prevents a new worker image from starting
before its packaged migration version is present in ACP PostgreSQL. The parent
auto-sync migration hook is separately approval-capped so unreviewed schema
upgrades are blocked. This is a deployment guard, not a substitute for DB backup
or a tested restore procedure.

The worker uses `Recreate` due to its singleton PostgreSQL advisory lock.
Rollouts may interrupt in-flight research assistant turns; verify them in ACP
after rollout.

**Current release safety:** The last observed production schema was v4, while
the current source includes v8. Do not promote the automated worker rollout
until operator-reviewed migration and restore-test evidence are complete.

See [ACP GitOps automation](../../../docs/architecture/acp-gitops-digest-automation.md)
for the source/image/approval/reconciliation process and recovery gates.
