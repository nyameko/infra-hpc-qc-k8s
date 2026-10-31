# M4b PostgreSQL v4 controlled production rollout — operator review gate

**State:** proposed; not deployed. **Production operator:** `k8s-cp-01` only. Track ACP [#31](https://github.com/nyameko/agent-control-plane/issues/31), [#45](https://github.com/nyameko/agent-control-plane/issues/45), and infra [#28](https://github.com/nyameko/infra-hpc-qc-k8s/issues/28).

## Observed facts / release artifacts
- Operator last observed live ACP schema versions **1,2,3**, parent Argo Application OutOfSync/Healthy, API at `ghcr.io/nyameko/agent-control-plane@sha256:5862983e290a384a4ad92281e8ceeac3dc200b9e0feaaa72abbf9f021f58e63c`, and personal worker at `ghcr.io/nyameko/agent-control-plane-hermes@sha256:73fbc34301e9cd700e6fbb5cb6ba1f46018e1a9c22a439fdda5f81c56433f9c5`.
- Desired API and migration-hook image in infra `main` is `ghcr.io/nyameko/agent-control-plane@sha256:b1289eab095fae443979d10ca1d5a27e8111a7689ddb346cb76ea7217e945bc4` from ACP commit `dab5e4c84eac428a990fe948c21a78b41ba1c04f`; [CI/image build](https://github.com/nyameko/agent-control-plane/actions/runs/41143207396).
- Current ACP migration hook: `argocd/resources/agent-control-plane/migrate-job.yaml`, Sync wave 1, owner credentials. ACP parent Application sync is manual. Worker child auto-syncs only its Deployment.
- ACP `db.ready()` accepts versions 3/4; `ACP_PERSONAL_MEMORY_ENABLED` defaults false. `migrate.py` is checksum-tracked, versions 1–4, and migration 0004 creates owner-bound memory tables, revisions and forced RLS.
- Updated Quantum Platform browser/proxy images are already running; their memory backend may return 503 while ACP remains on schema v3 and/or the old API image.

## Hard stop conditions
Never run an unrestricted parent Argo sync merely to update the API. No migration without a verified **restorable** PostgreSQL backup, reviewed diff, acknowledged downtime/rollback path, and separately recorded operator authorization. No memory hydration flag until successful schema v4 verification and a second explicit approval. No secrets/logged memory contents in issue evidence.

## Gate 0 — read-only preflight

```sh
kubectl -n argocd get applications agent-control-plane agent-control-plane-personal-worker quantum-platform litellm
kubectl -n agent-control-plane get deployments agent-control-plane-api agent-control-plane-personal-worker -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image'
kubectl -n agent-control-plane get pods -l acp-role=api -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.imageID}{"\\n"}{end}{end}'
kubectl -n agent-control-plane get pods -l acp-role=personal-worker -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.imageID}{"\\n"}{end}{end}'
kubectl -n agent-control-plane get configmap acp-config -o jsonpath='{.data.ACP_PERSONAL_MEMORY_ENABLED}{"\\n"}'
kubectl -n agent-control-plane get pvc
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- psql -X -v ON_ERROR_STOP=1 -U acp_owner -d agent_control_plane -c 'BEGIN READ ONLY; SELECT version FROM acp1.schema_version ORDER BY version; COMMIT;'
```

Use ArgoCD UI/diff (read-only) to list **every** OutOfSync object and pending sync operation. Record the exact Kubernetes Deployment diff and desired source revision. The parent may have unrelated changes; selective API sync must target only the named Deployment and must not carry configmap/secrets/DB/hook changes.

## Gate 1 — compatible API only (requires operator approval)

Argo CD's resource-selective sync can avoid hook execution; **verify the exact installed ArgoCD CLI/API behavior first** (ArgoCD docs: https://argo-cd.readthedocs.io/en/stable/user-guide/selective_sync/). Use the existing ArgoCD UI to select **only** `apps/Deployment agent-control-plane-api`, verify the preview contains **only** that Deployment and **no** `acp-migrate` hook, and do not enable prune, force, replace or apply-out-of-sync-only shortcuts. If the UI cannot show this restriction unambiguously, stop.

Check that the new image supports existing v3 schema without memory activation. After approved selective sync, observe the live image digest, Pods Ready, `/ready` state, logs filtered to error metadata (no secrets), and a signed authenticated M4a browser turn. Verify schema remains 1,2,3. The worker must remain on its current compatible image and the ConfigMap must remain unchanged.

**No commands to execute this production-changing sync are included in this proposal.** The operator must explicitly approve the scoped action after the diff is reviewed.

## Gate 2 — backup and recovery

Before invoking any migration:
- Record PVC and database ownership, PostgreSQL server version and free capacity; verify logical dump tool version/permissions.
- Obtain an encrypted, access-restricted, timestamped **full logical `pg_dump -Fc` backup** outside the ACP database PVC, with backup file digest and safe retention; take and verify a storage snapshot if available. Do not attach dumps to public issues or place them in Git.
- **Test restoration into a disposable isolated database** and validate schema versions 1–3, table ownership, row counts, authentication/invariants and representative canonical project/conversation continuity; record restore-test outcome and recovery owner.
- Agree on maintenance window, success/rollback criteria and secure recovery procedure. A backup by itself does not constitute a tested recovery.
- Prefer a single reviewed, manually authorized migration job invocation with owner credentials and **exact reviewed image**, not an unrestricted parent sync; verify no competing migration is active, and preserve checksum history.

## Gate 3 — controlled forward v4 migration (requires separate approval)

Once the compatible API and worker are observed on v3, backup restoration passed, and the migration SQL/sha256 and privileges were reviewed, approve **one** execution of the existing `python -m agent_control_plane.migrate` in the reviewed `acp-migrate` Job using its owner credential. Execute via a deliberately constrained, documented GitOps operation; do not assume the parent OutOfSync state implies every resource should sync. Observe completion/exit status and transactional DB ledger. A failed migration must **stop**, not retry ad hoc or edit the historical `0004` SQL. Seek forward correction reviewed as a new migration where needed.

Read-only post-verification:
```sh
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- psql -X -v ON_ERROR_STOP=1 -U acp_owner -d agent_control_plane -c 'BEGIN READ ONLY; SELECT version FROM acp1.schema_version ORDER BY version; SELECT to_regclass('\''acp1.memory_item'\'') AS memory_item, to_regclass('\''acp1.memory_revision'\'') AS memory_revision; COMMIT;'
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- psql -X -v ON_ERROR_STOP=1 -U acp_owner -d agent_control_plane -c "BEGIN READ ONLY; SELECT c.relname,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='acp1' AND c.relname IN ('memory_item','memory_revision') ORDER BY c.relname; COMMIT;"
```

Require versions **1,2,3,4** and FORCE RLS = true for both memory tables. Require existing API/worker health and a new M4a transcript/run regression test. Confirm logs and monitoring report no failed 5xx flood or DB privilege errors.

## Gate 4 — memory behavior; then optional activation

With the API and DB verified at v4, authorize a test research principal to create a source user message in conversation C1, propose a memory, inspect provenance and approve revision 2. Verify unapproved/expired memory exclusion; verify other subject denial; correct active memory and assert revision; revoke and verify no further retrieval. Avoid storing live secrets or personally sensitive details.

**Only then** approve a separate feature-flag GitOps PR to set `ACP_PERSONAL_MEMORY_ENABLED=1` on the worker. Verify rollout of worker settings, persistent state and schema v4. Start C2 with the same principal and a **fresh ephemeral Hermes run**, establish observable real model recall (not a mocked responder), then perform worker replacement/browser reopening. Repeat with revoked memory and different principal, expecting no disclosure. Record opaque message/run IDs, Pod UIDs and redacted response evidence.

## Rollback rule

- Before schema v4: an approved rollback to known working API/worker images is possible while database remains v3.
- After schema v4: **do not** downgrade to old schema-v3-only API or run reverse SQL. Use verified v3/v4-compatible binaries, preserve historical migration ledger and repair forward with approved migrations if needed.
- Never delete a PVC or restore a database into production without a separate recovery authorization.

## Release-evidence template

```text
Time / reviewer / operator:
ACP and infra source SHAs:
Desired and live API + worker digests:
Argo parent diff reviewed and only API selected:
No migration hook in API-only preview:
M4a regression with DB still v3:
Encrypted backup location (private), checksum, restoration evidence:
Separate migration approval:
Migration job run/result and schema 1,2,3,4:
Both memory tables FORCE RLS:
Source / candidate / approval / correction / revocation tests:
Memory feature-flag approval and actual value:
Real fresh Hermes C1 -> C2 result and no cross-user leakage:
Before/after restart evidence:
Remaining limitations / decision:
```

**Closure:** Do not close ACP #31 until all applicable live acceptance tests are evidenced. This runbook is a review artifact, not proof of a deployment.
