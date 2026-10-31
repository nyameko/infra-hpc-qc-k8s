# M4a/M4b live-readiness gate — read-only operator evidence

**Status:** Proposed runbook, not deployment authorization.  
**Operator:** On `k8s-cp-01` only (where `kubectl` is already configured).  
**Track:** [ACP #45](https://github.com/nyameko/agent-control-plane/issues/45), [ACP #21](https://github.com/nyameko/agent-control-plane/issues/21), [ACP #31](https://github.com/nyameko/agent-control-plane/issues/31).  
**Reuses:** `docs/tutorials/12-m4a-closeout-evidence.md`. That document remains authoritative for the M4a destructive continuity drill.

## Operator safety boundary

**Gate 0 is purely observational.** Do not run `kubectl apply`, ArgoCD sync, rollout restart, `psql` migrations, Helm upgrades, delete, patch, scale or GitOps/image changes. Do not expose JWTs, API keys, DB passwords, SealedSecrets, memory content, internal host IPs, browser cookies or full Pod environment dumps. Only share the redacted evidence fields below.

A green GitHub Actions run, a merged PR, an ArgoCD Healthy state or an image tag is **not** evidence of the deployed schema/image digest. An ArgoCD Sync hook can rerun `acp-migrate`; do **not** sync the parent `agent-control-plane` Application to look at its status.

## Gate 0 — what is actually deployed (read-only)

The following are **individual commands** to paste in an existing `k8s-cp-01` terminal. No repository checkout, extra binaries, scripts or root privileges on the control plane are required.

### 0A. GitOps and controller status

```sh
kubectl -n argocd get applications agent-control-plane agent-control-plane-personal-worker litellm quantum-platform
kubectl -n agent-control-plane get deployments,statefulsets,pods,pvc
kubectl -n litellm get deployments,pods
kubectl -n quantum-platform get deployments
```

Capture for each relevant Application the current sync/health, and for the ACP PostgreSQL claim the `Bound` status. **Do not delete or modify a PVC.**

### 0B. GitOps desired tags versus live workload images

```sh
kubectl -n agent-control-plane get deployment agent-control-plane-api -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}{"\n"}'
kubectl -n agent-control-plane get deployment agent-control-plane-personal-worker -o jsonpath='{.spec.template.spec.containers[?(@.name=="personal-worker")].image}{"\n"}'
kubectl -n litellm get deployment litellm -o jsonpath='{.spec.template.spec.containers[?(@.name=="litellm")].image}{"\n"}'
kubectl -n quantum-platform get deployment quantum-platform-user-api -o jsonpath='{.spec.template.spec.containers[?(@.name=="user-api")].image}{"\n"}'

kubectl -n agent-control-plane get pods -l acp-role=api -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.phase}{"  "}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}'
kubectl -n agent-control-plane get pods -l acp-role=personal-worker -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.phase}{"  "}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}'
kubectl -n litellm get pods -l app.kubernetes.io/name=litellm -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.phase}{"  "}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}'
```

Record immutable runtime `imageID` digests separately from requested tags. Existing **Git** desired state at the time of this proposal has the personal worker pinned to the M4a-era `sha-102959770de203a358263d774e7462d0bcce0e1e` image, while the later M4b code was merged to ACP `main`. This is a **potential release mismatch**, not proof that the live worker is outdated. The parent ACP Application still references `main`, with a manual-sync migration hook; never infer that the API has been upgraded just because `main` changed.

### 0C. Verify the feature-flag setting only (never dump full environment)

```sh
kubectl -n agent-control-plane get configmap acp-config -o jsonpath='{.data.ACP_PERSONAL_MEMORY_ENABLED}{"\n"}'
```

An empty line or value other than `1` means the code's `ACP_PERSONAL_MEMORY_ENABLED` opt-in should not be enabled by this ConfigMap. Record whether the Deployment has an explicit override **without disclosing any unrelated environment values**. The Git-tracked ConfigMap currently lacks this key. Confirm that the actual worker uses the ConfigMap; do not assume that a tag can prove the feature is active.

### 0D. PostgreSQL schema and forced RLS (read-only SQL)

**These SELECTs show versions/table metadata only, not any memory content.** Run on the existing PostgreSQL Pod. The SQL begins with `BEGIN READ ONLY` to prevent writes even if it is changed accidentally.

```sh
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
  psql -X -v ON_ERROR_STOP=1 -U acp_owner -d agent_control_plane \
  -c 'BEGIN READ ONLY; SELECT version FROM acp1.schema_version ORDER BY version; COMMIT;'

kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
  psql -X -v ON_ERROR_STOP=1 -U acp_owner -d agent_control_plane \
  -c "BEGIN READ ONLY; SELECT to_regclass('acp1.memory_item') AS memory_item, to_regclass('acp1.memory_revision') AS memory_revision; COMMIT;"

kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
  psql -X -v ON_ERROR_STOP=1 -U acp_owner -d agent_control_plane \
  -c "BEGIN READ ONLY; SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='acp1' AND c.relname IN ('memory_item','memory_revision') ORDER BY c.relname; COMMIT;"
```

Require the ordered schema versions to include `1, 2, 3, 4` before enabling M4b endpoints/hydration. Both memory tables must exist with `relrowsecurity=true` and `relforcerowsecurity=true`. This does **not** replace the CI runtime-policy tests and does not prove the migration was applied with the intended checksum: also inspect the redacted ordered migration ledger/checksum metadata and Argo operation record before any release decision.

### 0E. Observe migration hook history without invoking it

```sh
kubectl -n argocd get application agent-control-plane -o jsonpath='{.status.operationState.phase}{"  "}{.status.operationState.finishedAt}{"\n"}'
kubectl -n agent-control-plane get jobs acp-migrate --ignore-not-found
```

The Sync hook may have been automatically deleted after success; absence of a Job is **not** evidence of either success or failure. Do not `kubectl apply` or Argo sync to regenerate this Job.

## Gate 1 — operator interpretation and release hold

| Observation | Operator action |
| --- | --- |
| v3 or missing v4 tables | **HOLD.** Never enable M4b memory endpoints or the worker flag. |
| API/worker still running M4a-only images | **HOLD.** Plan a separate GitOps PR to publish/roll out compatible pinned images first; no migration in that step. |
| v4 schema + v4-compatible API/worker digests | Proceed to authentication/behavioral checks in an approved test session; still do not infer memory is enabled. |
| App has wrong schema or worker crashes | Restore prior **v3/v4-compatible** image only under an approved recovery plan; do not roll back DB DDL or launch a second unreviewed migration. |
| ArgoCD reports OutOfSync or a migration hook is pending | **HOLD.** Verify desired vs actual and human approval before any sync; syncing can mutate PostgreSQL. |
| Any doubt about pinned images, backups or RLS | **HOLD.** No pilot activation until resolved. |

## Gate 2 — approved rollout sequence (documentation only; do not execute now)

1. Record the immutable ACP release SHA, image **digest** and signed CI evidence for both API and Hermes worker. Verify both support schema versions 3 and 4 with memory feature off.
2. Review a separate **infra feature branch/PR to `dev`** pinning compatible API/worker images. ArgoCD parent migration hook must **not** run during the API/worker compatibility-only rollout. Check target Application ownership: parent manual; worker child auto-syncs just its Deployment.
3. After operator approval and verification of compatible images, back up ACP PostgreSQL and verify restore procedure. Approve and execute exactly one checksum-tracked forward v4 migration via controlled GitOps. Record the real schema version and migration metadata.
4. Verify v4 memory API (auth, idempotent create, approve/correct/revoke, scope isolation) with a controlled test account, not arbitrary personal/sensitive data.
5. Only after API and worker have compatible images and schema v4 is observed: review feature-flag activation as **another** approved infra PR (worker has `ACP_PERSONAL_MEMORY_ENABLED=1`), then perform the real **C1 to C2 fresh Hermes** test. Record before/after worker Pod UID, same ACP principal, memory source ID, memory revision, approved body marker (redacted in public evidence), successful run ID. Verify candidate exclusion, correction, revoked/expired exclusion and subject B denial.
6. Repeat with a browser close, worker/API replacement and temporary Hermes state destruction as in the existing M4a drill. Confirm Jupyter/SSH attachments separately as these surfaces become available.
7. Sign off ACP #21/#31/#45 **only** with observed evidence; do not close issues on CI or PR merge alone.

## Gate 0 evidence template

Record these fields in private operator notes and submit a **redacted** summary to ACP #45/#31:

```text
UTC timestamp:
k8s-cp-01 kubectl context name (non-secret):
GitOps Applications and sync/health:
ACP API Deployment tag + Pod imageID:
ACP Hermes worker Deployment tag + Pod imageID:
LiteLLM tag + Pod imageID:
Quantum Platform user-api tag:
ACP PostgreSQL PVC Bound status:
ACP schema_version rows:
memory_item / memory_revision exist?:
memory_item / memory_revision FORCE RLS?:
ACP_PERSONAL_MEMORY_ENABLED (0 / 1 / unset):
Argo parent last operation phase/time:
Compatible images proven by independent build/commit provenance?:
Release decision: HOLD / eligible for separate approved deployment step
Risks/blockers:
```

This template deliberately excludes usernames, emails, tokens, message bodies, internal IPs and credentials. The technical proof for issue #31 must later include authorization and real model use, not just SQL metadata.
