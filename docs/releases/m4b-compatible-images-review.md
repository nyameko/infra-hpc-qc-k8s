# M4b compatible-image GitOps staging — NOT a deployment authorization

This is a preparation change for ACP #31/#45. The latest ACP source commit with passing CI is `dab5e4c84eac428a990fe948c21a78b41ba1c04f`.

| Workload | Published immutable OCI manifest digest |
| --- | --- |
| ACP API/migrator | `ghcr.io/nyameko/agent-control-plane@sha256:b1289eab095fae443979d10ca1d5a27e8111a7689ddb346cb76ea7217e945bc4` |
| ACP personal Hermes worker | `ghcr.io/nyameko/agent-control-plane-hermes@sha256:73fbc34301e9cd700e6fbb5cb6ba1f46018e1a9c22a439fdda5f81c56433f9c5` |

Source proof: [ACP container build run](https://github.com/nyameko/agent-control-plane/actions/runs/41143207396) (both build jobs successful). The digest is an **OCI index digest**; the Kubernetes runtime may show a platform-specific manifest/image digest. Compare with registry metadata and the build provenance rather than assuming those strings must be equal.

## Observed live baseline (operator's read-only preflight)

- ACP Argo parent OutOfSync / Healthy, worker child Synced / Healthy.
- PostgreSQL schema versions **1, 2, 3** only. v4 NOT deployed.
- Live API image ID `sha256:5862983e290a384a4ad92281e8ceeac3dc200b9e0feaaa72abbf9f021f58e63c`.
- Worker Deployment still references M4a-era `sha-102959770de203a358263d774e7462d0bcce0e1e`.
- `ACP_PERSONAL_MEMORY_ENABLED` not present in `acp-config`; M4b retrieval remains disabled.
- ACP PostgreSQL and Hermes state PVCs are Bound; preserve them.

## Critical release sequencing

**Do not merge/promote this PR to `main` before deciding how to isolate the automatic personal-worker child reconciliation.** The worker Application already has automated self-healing targeting `main`: a promotion can restart it even without a manual Argo parent sync. In contrast, the parent ACP Application is manual and has an `acp-migrate` Sync hook. **Do not sync the parent just to reconcile the API image**; that can run schema-v4 migration.

1. Review GitHub CI and render Kustomize output: API image and migration-job image must both resolve to the same immutable **API** image. Worker resolves to the Hermes image. No memory enablement flags or DB resources are modified by this PR.
2. Operator signs off on maintenance/recovery and records exact live images and health. Obtain backups and restore evidence before any DB migration.
3. Resolve **one of** the explicit safe compatibility rollout mechanisms: (a) a separately reviewed migration-free API overlay/Argo Application with nonoverlapping resource ownership and manual sync, or (b) an approved Argo resource-selective operation that **provably excludes the Sync hook** (supported by an audited dry-run/diff). Do not add an application that competes for ownership of the same Deployment without a transition plan.
4. A separately authorized worker reconciliation can follow only when its image is expected to work against schema v3. Ensure no automatic unexpected worker rollout due to a `main` merge.
5. Verify API and worker are actually running **v3/v4-compatible** binaries while DB is still v3. Verify M4a regression: auth, turns, run status, model generation, canonical persistence.
6. **Only after compatibility is proven**, separately approve controlled checksum-tracked schema-v4 migration. Parent Application must not trigger any unreviewed other changes. Confirm `acp1.schema_version` 1–4 and forced RLS on memory tables. Do not rewrite historical migration SQL.
7. Separate third approval for `ACP_PERSONAL_MEMORY_ENABLED=1` and real destructive C1→C2 recall/revoke acceptance. Do not set flag now.

## Rollback boundary

Before migration, revert to the last observed healthy v3-compatible image only under operator approval. After migration, **never blindly restore an M4a-only binary or downgrade schema**; use a tested v3/v4-compatible release and forward repair. Preserve both PVCs, database ledger and state.

This PR is **Git diff + CI only**. It is not permission to deploy, migrate, touch secrets, or attach H200 GPUs.
