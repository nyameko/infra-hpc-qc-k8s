# M4 live release and acceptance — operator evidence pack

**Status:** source merged, **live acceptance not yet observed**. Last direct operator
report showed ACP schema v4 and ACP API/Hermes `OutOfSync / Healthy`. Do not
claim migration 5/6/7, new images, revocation or portability merely because
GitHub CI or Argo health is green.

**Operator:** work on `k8s-cp-01`. **Scope:** ACP M4a–M4g, Quantum Platform
Guide and Jupyter; not the M5 H200 scientific runner.

## 1. Immutable source-to-deployment inventory

Source: `main` PRs [infra #248], [Quantum Platform #134], [ACP #78],
[Quantum Workflows #44], [PhotonicsLab #9]. All five are source-merged.

Published `main` container digest evidence (verified from CI **push logs**,
not `:main` tags):

| Source | Actual GHCR manifest digest |
|---|---|
| ACP API, main `937cb1e4...` | `sha256:17911f1a919f3a3f25424c4db4949e7bbcb1d4be022c571fb00d9f24f56d0eaa` |
| Hermes / ACP personal-worker, same ACP main | `sha256:876bc6877b85160dc78e265ac5311dcfbeb86e381080da484f12f4aa749df30e` |
| Quantum Platform Users, main `02fc19c6...` | `sha256:2c7e05081ad81102af8e4e15df8fc1f442eae8d2c919cef6aa71948223db7250` |
| Quantum Platform User API, same QP main | `sha256:47e99cb404c3daeb16357c9f8385cec774a8065d064fca8215fe74cfe8db84a6` |

The prior Infra `main` manifests pinned ACP API `2b0318...`, Hermes
`c480ca...`, QP Users `fd406e...`, and QP User API `561de7...`.
Those did not incorporate the latest merged ACP #78 + QP #134
conversation-review release. This PR only stages the replacement immutable
digests in `dev` — it does **not** deploy them.

## 2. Read-only baseline (safe before operator approval)

**Do not clone, pull, check out or execute repository scripts on
`k8s-cp-01`.** This host is not a development or deployment workstation.
The following `kubectl` commands can be pasted individually at its normal
administrative prompt. They use Kubernetes API reads; `kubectl exec` below
performs **only SQL SELECT** through a read-only transaction, without
printing a database URL, token or user content. Do **not** use the ArgoCD CLI.

```bash
kubectl -n argocd get applications quantum-platform agent-control-plane agent-control-plane-personal-worker
kubectl -n argocd get application agent-control-plane -o jsonpath='{range .status.resources[*]}{.kind}{" "}{.namespace}{"/"}{.name}{" "}{.status}{"\\n"}{end}'
kubectl -n agent-control-plane get deploy,sts,pods,jobs
kubectl -n agent-control-plane get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\\t"}{range .status.containerStatuses[*]}{.name}{"="}{.imageID}{" "}{end}{"\\n"}{end}'
kubectl -n quantum-platform get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\\t"}{range .status.containerStatuses[*]}{.name}{"="}{.imageID}{" "}{end}{"\\n"}{end}'
```

ACP schema inventory without displaying the credential:

```bash
kubectl -n agent-control-plane exec deployment/agent-control-plane-api -- python -c 'import os,psycopg; c=psycopg.connect(os.environ["ACP_DATABASE_URL"],options="-c default_transaction_read_only=on"); print("Versions:",c.execute("SELECT version,left(checksum,12) FROM acp1.schema_version ORDER BY version").fetchall()); print("Tables:",c.execute("SELECT to_regclass(\x27acp1.programme_conversation\x27)::text,to_regclass(\x27acp1.personal_profile\x27)::text").fetchone()); print("DB role:",c.execute("SELECT rolname,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user").fetchone()); c.close()'
```

Record only sanitized stdout, UTC timestamp, actual Pod imageIDs, observed
`Synced/OutOfSync` resource status, schema versions and required tables.
Do not publish full JWTs, database URLs, user chat bodies or assertions.
If the SELECT fails, report only the failure category; don't paste a traceback
that could include connection details.

Required schema checks: `acp1.schema_version` includes ordered
**1,2,3,4,5,6,7** with unchanged checksums; `programme_conversation` and
`personal_profile` resolve. App DB role must have `rolsuper=false`,
`rolbypassrls=false`, and **no DELETE on `acp1.message`**. The v7
empty-workspace delete permission on `acp1.conversation` is expected.

**The ACP API readiness check accepts multiple historical schema versions.**
It is not evidence that migration v7 ran.

## 3. Controlled release — requires human/operator authorization

These are **procedural gates, not commands executed by this PR**:

1. Review real live-vs-Git drift (including other Argo parents and hooks).
   Take a **verified restorable backup of ACP PostgreSQL**; preserve retained
   database PVCs and record backup metadata off-repository.
2. Review migration checksums and SQL for `0005_m4c_programme_rooms.sql`,
   `0006_m4e_personal_profile.sql`, and
   `0007_m4f_empty_workspace_delete.sql`, as well as the migration job's
   Argo sync-hook behavior. Get **separate explicit approval** for migration.
3. Use the reviewed migration/compatible runtime deployment order and
   explicit GitOps authorization. Never blind-sync a production parent that
   could invoke schema-owner jobs. Observe migration results and actual Pod
   imageIDs. Review health AND functionality, and preserve rollback plan.
4. Promote the Quantum Platform frontend/proxy only after ACP's required
   endpoints and schema are available. Verify authenticated responses
   (including 403/404/409/412) from real accounts rather than trusting CI.
5. Do not run ACP `pytest` fixtures against live PostgreSQL: integration
   fixtures intentionally drop/reset schema **in their isolated test DB**.

## 4. M4 human acceptance matrix

**Do not check an item without a date, real account, actual response evidence,
run/conversation ID (redacted) and observed result.** Use `nlisa` as PI if
that account currently has approved programme rights. Use a separate approved
researcher A and B, plus an outsider or rejected member, with credentials
owned by each human; do not impersonate identities.

| Gate | Human/user action | Evidence required |
|---|---|---|
| M4a | Browser creates C1, Jupyter reads/resumes C1; approved ephemeral API/worker/Hermes replacement; revisit | Same ACP project, C1, message sequence; successful real model run; second-user 404 |
| M4b | Propose memory from grounded message, approve, new chat recalls; correct, revoke, new chat | Canonical source message ID, revision, approved-before and absent-after revocation; worker feature enabled |
| M4b UX | Click **Review conversation**; select, edit and propose; decline another | Read-only preview creates zero memories; candidate requires separate explicit approve; source-linked excerpts |
| M4c | PI creates shared room, two members list/post, outsider denied; revoke one member | Same programme room UUID/order; revoked member next read/list/post denied; private chat/memory excluded |
| M4d | Browse a reviewed immutable notebook reference and open via ordinary Jupyter Workbench | Git source SHA, environment prerequisites, no silent shell/Slurm run; separately establish skill enable/revoke and provenance |
| M4e | Save owner portable profile; replace ephemeral harness; run C2 in same conversation | Same identity + UUIDs + preferences, owner-B denial; **real independent second harness** evidence |
| M4f | Five unsent New Chat drafts; one first Send; page reload; errors/menus/keyboard/mobile | 0 rows until Send, 1 afterward, accessible actions, no imaginary model effort or usage |
| M4g | Browser-authenticated trusted terminal pairing (no manually supplied JWT), SSH reads/posts C1; revoke terminal | Trusted broker identity, per-request reauthorization, next-request denial, shell unaffected |
| Release | Two independent real researchers, browser + Jupyter + SSH; novice + advanced questions | Task completion time, failure clarity, real model and kernel versions, observability, operator approval |
| Continuity | Explicitly approved destructive validation only after tested backup and rollback | Database persisted/restore-proof across **specified** components and clients; no test fixture on live |

If M4e's second harness or M4g's portal-mediated SSH broker does not
exist in running code, mark **BLOCKED** and keep M4 open. A pre-supplied
bearer token or a standalone alternative model client is not a broker or
canonical ACP continuity proof. The existing M4g ADR remains design-only.
The deployed Guide's neutral `Processing class unavailable` indicator is
**correct** if no routing policy/effort telemetry was recorded.

## 5. Developer-only dummy cleanup (approved by project owner)

The last human user inventory contained **9** conversations: three old
`New chat` entries with **zero messages** (ID prefixes `4f0aa972`,
`545ed90e`, `6fbe6b80`), and one empty `M4 Persistence Test` project
(prefix `e59b2e44`). These are only **prefixes, not complete UUIDs**.
Other test conversations include messages and are **not eligible** for the
empty-only delete API. Never delete by title or prefix alone.

After v7 and Quantum Platform deletion UI are live, the actual logged-in
owner may individually delete the verified empty objects in `⋯`, then
check exact UUID `GET` returns 404 and other-user denial. A *full*
populated-test-record reset is a separately approved operation with
an explicit inventory and retained backup; do not silently cascade messages,
run audit, or memory sources.

## 6. M5 handoff (after actual M4 signoff)

M5's first question is:

> How do I deploy a user-chosen PennyLane finance / chemistry / nuclear
> model, with a versioned scientific input and Lightning backend, onto the
> H200 resource through the existing scheduler?

The scientific runner belongs to **quantum-workflows**, with upstream
`pennylane` and `pennylane-lightning` backends. ACP owns user intent,
authorized task/run, references, quota and result provenance; Quantum
Platform owns identity and UI; Slurm or Axis Atmos owns scheduling and
allocation. **Do not build a new scientific SDK or reuse the inference
H200 endpoint as if it were a scheduled scientific compute allocation.**

M5 acceptance must prove a CPU `lightning.qubit` reference first, then
an actually compatible `lightning.gpu` / NVIDIA cuQuantum stack on an
allocated H200 with recorded GPU ID, driver/CUDA versions, PennyLane plugin,
model Git SHA, shots/seed, Slurm job ID, results and CPU/GPU agreement within
a defined scientific tolerance. A generic prompt, a container-image build
or a Slurm job id without numerical validation is insufficient.

## Operator signoff

```text
UTC time:
Reviewer / operator:
Source main SHAs:
Published image digests:
Actual running Pod imageIDs:
DB schema versions + verified backup metadata:
Current Argo sync + health:
M4a: PASS / FAIL / BLOCKED — evidence
M4b: PASS / FAIL / BLOCKED — evidence
M4c: PASS / FAIL / BLOCKED — evidence
M4d: PASS / FAIL / BLOCKED — evidence
M4e: PASS / FAIL / BLOCKED — evidence
M4f: PASS / FAIL / BLOCKED — evidence
M4g: PASS / FAIL / BLOCKED — evidence
Two-researcher human usability: PASS / FAIL / BLOCKED — evidence
Cross-client + destructive continuity: PASS / FAIL / BLOCKED — evidence
Privileged release approval:
M4 overall: PASS only when all mandatory gates have observed evidence
```

[infra #248]: https://github.com/nyameko/infra-hpc-qc-k8s/pull/248
[Quantum Platform #134]: https://github.com/nyameko/quantum-platform/pull/134
[ACP #78]: https://github.com/nyameko/agent-control-plane/pull/78
[Quantum Workflows #44]: https://github.com/nyameko/quantum-workflows/pull/44
[PhotonicsLab #9]: https://github.com/nyameko/photonicslab/pull/9
