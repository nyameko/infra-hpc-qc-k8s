# M4 v4 → v8 controlled recovery and human acceptance

**Status: candidate only; not approved or executed.** Source PR targets `dev`.
Production ACP Postgres was last observed at v4 on 6 Nov 2026. The GitOps
promotion from infra #259 already caused the ACP migration Sync hook to retry
and the independently auto-synced personal worker to block at
`wait-for-acp-schema`. The root and Quantum Platform were Healthy; ACP API
and Postgres Pods were Running. The worker was not serving.

## What failed and why

The parent application's `acp-migrate` Sync hook uses the new ACP image,
which includes SQL migrations 1–8, but caps automatic installation at v4.
Hence the hook exits with a deliberate nonzero status for the v4→v8 gap.
The worker's init check uses a v8 Hermes image and waits for v8.
The child Argo Application owns the worker independently from the parent;
its successful sync means a desired Deployment was applied, not a ready worker.
A later child `PreSync` guard (infra #260/#261) cannot restore an existing
worker replaced by the earlier promotion.

**Do not repeatedly inspect broad cluster resources**: the above is enough to
explain the observed states. If the hook log contradicts the expected guard,
inspect only its last non-secret lines and reassess. Avoid direct Argo CLI,
kubectl patch/force/prune, PVC deletion, casual rollback or manual SQL.

## Operator HOLD: never promote this release merely because CI passed

A `dev → main` infra promotion of this branch raises the explicit schema
approval ceiling to 8. The parent Argo Application is now auto-synced; thus
promotion to `main` authorizes the migration **immediately**. Before that
promotion the operator must record, in a private approved location:

1. A consistent encrypted, **off-PVC, off-cluster logical backup** of the ACP
   database (e.g. `pg_dump --format=custom`), location, checksum, capture
   timestamp and custodian; no secret/DB content in GitHub.
2. A **successful isolated restore** using the compatible PostgreSQL server
   version, with row-count and project/conversation continuity checks.
   Preserve production RLS grants and migration ledger.
3. Review every SQL source `0005`–`0008` in ACP against its exact immutable
   release image, checksum and access boundaries; verify no incompatible
   restore/downgrade behavior.
4. Written owner authorization of this schema upgrade, maintenance window,
   in-flight user-work policy and restoration/forward-fix decision.
5. Paired ACP API/Hermes image digests pinned in infra main, compatible with
   the reviewed migrations, and correct QP user-api schema (through portal
   0008 terminal pairing) deployed independently.
6. CI success on this PR, no confidential material in its diff; production
   promotion `dev → main` separately and deliberately reviewed.

If any gate is missing, **do not promote this candidate**. It deliberately
contains no live migration or backup command.

## Controlled release and one-time checks

When authorized, promote the reviewed source through the usual release
procedure. The parent ACP Argo auto-sync runs the one-shot migration hook
before API/Hermes wave 2; it uses `backoffLimit: 0` and
`restartPolicy: Never` to avoid pod-level retry flapping. A failed hook is a
STOP and must be diagnosed; do not bypass it by selective sync.
The separate child worker Application has no cross-application dependency
edge, so verify it sees the new DB schema before expecting readiness. A
failed PreSync on the same revision might require an operator-authorized
retry after migration.

**One read-only post-release evidence collection from `k8s-cp-01`:**

```bash
kubectl -n argocd get application root quantum-platform agent-control-plane agent-control-plane-personal-worker
kubectl -n agent-control-plane get deployment/agent-control-plane-api deployment/agent-control-plane-personal-worker statefulset/agent-control-plane-hermes statefulset/agent-control-plane-postgres
kubectl -n agent-control-plane exec deployment/agent-control-plane-api -- python -c 'import os,psycopg; c=psycopg.connect(os.environ["ACP_DATABASE_URL"]); print(c.execute("SELECT version FROM acp1.schema_version ORDER BY version").fetchall()); c.close()'
```

Expected: schema versions `1..8`; healthy synced applications; healthy
worker with its init finished; actual Pod imageIDs equal reviewed digests.
If unhealthy: do not retry broad sync or delete the Postgres PVC. Capture
only the failing Job/init container's redacted log and compare with the
reviewed release; restore/forward-fix only under recovery authorization.

## M4 human functional acceptance (not CI)

Only the owner operates live identities, Firefox, Jupyter, SSH and tests
involving a real secondary account. Record **opaque** project/chat/run IDs,
timestamps, revisions, error codes and screenshots without private content.

1. **M4a continuity** — As researcher A, sign into the portal, create a
   disposable project and C1, send a harmless unique marker, receive a REAL
   model answer, and record the project/conversation UUID. Close the browser,
   open Jupyter, load C1, confirm identical UUID/history and send another turn.
   Later repeat from the paired terminal. Test logout/browser reopening.
2. **M4b memory** — In C1 create a harmless explicit memory candidate, inspect
   its source, approve it, open C2 and retrieve it, then **correct** it.
   Confirm new conversation uses corrected value. Revoke it; C3 must no longer
   retrieve it. Do not use secrets or sensitive biographical facts.
3. **M4c projects/programmes** — Create/list/rename an authorized disposable
   private workspace. As approved PI, create a shared programme room, share with
   an authorized member, exchange an innocuous turn. Test outsider denial,
   revoke the member, then verify the next request fails and cached content is
   cleared. A live personal memory must never surface in shared room content.
4. **M4d skill/notebook** — From Guide open an actual immutable reviewed
   Qiskit/Bell notebook. Check source commit, prerequisites, user-scoped
   enable/revoke. If catalog is empty, mark skill-enablement **BLOCKED**;
   do not treat a synthetic CI fixture as an approved catalogue entry.
5. **M4e profile/alternate runtime** — Save a harmless personal preference and
   confirm a fresh Hermes turn uses it. In a separately approved disposable
   sandbox, run a PydanticAI alternative using an approved OpenAI-compatible
   local model route and an owner-scoped context snapshot; verify it does not
   create conflicting ACP identities/state and its run is traceable.
6. **M4f browser Guide** — Create a chat and send once: exactly one canonical
   conversation appears. Five abandoned drafts create zero conversations.
   Confirm one Guide entry point, status/error clarity, and normal link to
   Workbench, runs and documentation.
7. **M4g terminal pairing** — In a personal SSH login shell run the
   reviewed ACP terminal client with browser pairing. Approve in the portal,
   list C1 and send a new turn under the **same** UUID. Revoke the pairing:
   the next CLI request must be denied. SSH shell and Slurm remain usable.
   Herdr/tmux are optional terminal ergonomics, not auth providers.
8. **Destructive conformance (separate approval)** — After a restorable
   backup, replace ephemeral API/worker/Jupyter runtime through a reviewed
   GitOps/test plan; read C1 again and verify exact IDs/transcript. Repeat
   outsider denial. Do not delete any persistent database volume.

**M4 closeout** requires observed real model delivery, multiuser denial,
stable cross-client IDs, revised/revoked memories, one reviewed notebook
handoff, alternate-harness conformance, an actual scheduler result/reference
where applicable, and human-reported success. Mere healthy Pods or a merged
PR are not sufficient.

## Boundary after recovery

Once functional acceptance passes, M5 = small real scientific CPU→H200→
platform workflow. Optional Paperclip/OpenHands/Herdr pilots may proceed
in isolated service environments without adding a second authoritative ACP
database or gating that scientific path. Larger dependency upgrades move to M6.
