# M4a — Persistent Personal Agent: architecture, failure analysis, deployment and continuity evidence

**Status:** Historical operator-observed browser/API/worker destructive continuity proof: **PASS**, 30 October 2026. Full cross-client automated staging conformance and independently observed live second-user denial remain **open** in [ACP issue #21](https://github.com/nyameko/agent-control-plane/issues/21). This document is an instructional and provenance record, **not** evidence of a database/PVC disaster-recovery restore, a Jupyter/SSH client integration, or an ongoing health guarantee.

**Audience:** Platform engineers, research software engineers, graduate students, security trainees, operators and future maintainers.  
**Reading prerequisites:** Linux, HTTP, SQL transactions, containers, Kubernetes Deployments/StatefulSets, GitOps, and LLM completion endpoints.  
**Related hands-on runbooks:** [M4a deployment](11-m4a-persistent-personal-agent.md), [M4a closeout](12-m4a-closeout-evidence.md), [LiteLLM staging](13-litellm-m4a-operator-secrets-image-and-rollout.md), [ACP milestone](https://github.com/nyameko/agent-control-plane/blob/main/docs/M4-PERSISTENT-AGENTS.md).

## Learning outcomes

At the end of this module a researcher or engineer should be able to:
1. Identify the authority of each subsystem and distinguish canonical PostgreSQL data from ephemeral runtime and browser state.
2. Trace an authenticated personal turn from the browser through Quantum Platform, ACP, LiteLLM, vLLM, Hermes, and back to an immutable assistant reply in the canonical conversation.
3. Explain tenant/subject isolation, idempotency, transactional task/run/message linkage and the worker's singleton database lock.
4. Diagnose failures by separating Kubernetes readiness, inference availability, Hermes initialization, model generation, subprocess lifecycle, persistence and frontend rendering.
5. Reproduce a **safe**, selectively destructive acceptance drill and document what it does and does not prove.
6. Interpret real M4a incident evidence and avoid erroneous fixes such as gratuitous restarts, longer timeouts, unbounded runtime package installations and undocumented image tag reuse.
7. Prepare the baseline against which M4b scoped memory can be demonstrated.

## 1. The problem and the acceptance claim

A personal research assistant is only useful if a researcher can return after closing the browser, losing a notebook Pod, replacing a worker or changing the agent runtime, and still recover the same project, conversation and research decisions. Persisting only a Hermes SQLite session or an in-browser transcript is insufficient: those data are tied to replaceable components.

**M4a architectural invariant:** ACP PostgreSQL is authoritative for minimal project identities, conversations, ordered messages and task/run lineage. The model/runtime is a bounded, replaceable consumer and producer of canonical context.

A proof of successful inference is weaker than a proof of **durable continuity**. M4a must demonstrate both. Memory, rich multiuser projects, skill governance and persistent personas are distinct milestones M4b–M4e.

## 2. System architecture and authority boundaries

```text
Researcher (authenticated browser / later Jupyter / SSH)
  |
  v
Quantum Platform (identity authority)
  - authenticated user session and stable AgentPrincipal UUID
  - creates short-lived signed agent:personal assertion
  - proxies /api/v1/agent/... (does not own conversation state)
  |
  v
ACP API  ---- scope/tenant checks ----> ACP PostgreSQL (canonical)
  |                                  project, conversation, message,
  |                                  task, run, event and lifecycle
  v
Personal worker (one replica, database advisory lock)
  - claims queued personal run
  - hydrates authorized conversation from ACP PostgreSQL
  - creates per-run temporary Hermes profile/session
  - runs bounded tool-free Hermes subprocess
  |
  v
Hermes adapter -> OpenAI-compatible LiteLLM restricted virtual key
  |                            |
  |                            v
  |                      A100 vLLM inference
  |                            |
  <---------------------- model response
  |
  v
ACP finish_personal() -> run status, assistant message, event
  |
  v
Quantum Platform polls run and renders canonical conversation
```

**Subsystems and what they do NOT own:**

| Component | Authority | Not authoritative for |
| --- | --- | --- |
| Quantum Platform | Human account, identity, AgentPrincipal, authorizations | Canonical agent conversation transcript |
| ACP PostgreSQL/API | Project/conversation/task/run/message provenance and policies | GPU execution state or scientific simulation data |
| Hermes personal worker | Execution of a specific bounded turn | Permanent memory, canonical chat history or privileges |
| LiteLLM | Restricted model routing, model credentials/usage gateway | ACP subject identity or durable conversation history |
| A100/vLLM | Inference response | Whether an ACP run committed successfully |
| Argo CD/GitOps | Kubernetes desired state | Validity of a generated scientific or conversational result |
| quantum-workflows (later) | Scientific workflow and result provenance | Human identity or ACP conversation ownership |

The ACP subject is the Quantum Platform `AgentPrincipal` UUID expressed as a stable external subject. POSIX UID/GID is a separate execution identifier; it is not the canonical memory/conversation ownership key.

### Why two separate Hermes workloads?

The administrative Hermes StatefulSet performs privileged *read-only* diagnostic duties and has a different trust profile. The personal worker is a **tool-free**, non-root, separate Deployment, with no ServiceAccount token, a temporary filesystem and a tightly scoped egress path. Do not combine these workloads just because they use the same upstream agent framework.

## 3. Storage, schema, identity and data flow

M4a uses the versioned ACP `acp1` schema. The implementation files to inspect are:

- `agent-control-plane/src/agent_control_plane/migrations/0002_m4a_personal_agent.sql` — minimal project/conversation/message tables, tenant+owner columns, ordered sequence and row-level security.
- `.../migrations/0003_m4a_personal_turn_ledger.sql` — `personal_turn` tasks, run links, message-to-run uniqueness, scoped task/run visibility.
- `.../db.py` — claim, context hydration, transaction and finish semantics.
- `.../personal_worker.py` and `.../personal_runtime.py` — isolated per-turn subprocess and Hermes.
- `quantum-platform/apps/user-api/portal/agent_api.py` — authenticated portal proxy.
- `quantum-platform/apps/users/src/pages/agent.astro` — UI and polling.
- `infra-hpc-qc-k8s/argocd/resources/agent-control-plane-personal-worker/deployment.yaml` — restricted workload.
- `infra-hpc-qc-k8s/argocd/applications/agent-control-plane-personal-worker.yaml` — isolated auto-sync.
- `infra-hpc-qc-k8s/argocd/resources/agent-control-plane/kustomization.yaml` — manually managed parent app.

A turn follows this state machine:

```text
POST turn (authenticated subject, idempotency key, client message id)
 -> canonical user message + personal task/run
 -> queued -> running [advisory-lock singleton worker]
 -> canonical transcript hydrated subject-safely
 -> fresh Hermes subprocess + restricted model request
 -> success: run = succeeded, assistant message inserted, event recorded
 -> failure: run = failed, failure_code recorded; no invented assistant reply
```

Do not assume that a GPU HTTP `200 OK` implies ACP success; the child may still be initializing, finalizing, failing validation or blocked before the database commit. Similarly, `Deployment READY=1` is process availability, not an end-to-end inference or continuity acceptance.

## 4. Runtime and inference settings that mattered

The current M4a adapter disables tools, Hermes-native persistent memory, project plugins, background review and profile identity. Per-turn Hermes state is ephemeral and the bounded conversation context is rebuilt from ACP.

The inference gateway supplied an ACP-specific restricted virtual key to LiteLLM with model alias `research-general`; the configured model was an A100-hosted OpenAI-compatible endpoint. The operator verified both non-streamed and streamed simple `ACP ONLINE` requests with a model-specific request field:

```json
{"chat_template_kwargs":{"enable_thinking":false}}
```

Without this override the thinking mode could consume the token budget without producing the required short final response. The adapter passes the extra body as a configured request override; it is not a hard-coded vendor-specific dependency.

**Critical Hermes initialization incident:** A Python stack snapshot revealed that importing the optional `agent.bedrock_adapter` caused `tools.lazy_deps.ensure()` to run an installer for `provider.bedrock` (`boto3==1.42.89`) even though ACP used `provider="custom"` through LiteLLM. The subprocess was stuck in `subprocess.run()`; normal personal runs timed out at 180 seconds. The code did not reach `run_conversation()`. This is why inference throughput and Kubernetes restarts were irrelevant.

Reviewed ACP [PR #27](https://github.com/nyameko/agent-control-plane/pull/27) addressed the issue with both:
- ephemeral Hermes profile policy `security.allow_lazy_installs: false`;
- explicit child environment `HERMES_DISABLE_LAZY_INSTALLS=1`.

**Why both controls?** The worker explicitly constructs the subprocess environment rather than inheriting all Pod variables. Setting the variable on the parent ConfigMap alone would not ensure it reached the child.

Further diagnosis showed that Hermes request handling itself succeeded. The isolated adapter trace printed:

```text
Diagnostic timed out: False
Exit code: 0
TRACE: respond started
TRACE: conversation started
TRACE: conversation exited
TRACE: agent close started
TRACE: agent close exited
TRACE: respond returned, characters: 10
```

The production personal-agent turn subsequently reported `succeeded` in **9 seconds**, with a canonical assistant reply saved.

### Diagnostic lessons from the real incident

| Symptom | Investigate first | Incorrect assumption |
| --- | --- | --- |
| Deployment object AGE shows 6 days | Pod AGE, imageID, rollout revision | No new deployment occurred |
| A100 logs `200 OK` | ACP run status, response and DB commit | The personal run succeeded |
| `personal_runtime_timeout` after 180s | Hermes child initialization, stack, tool calls | The GPU is inherently too slow |
| Direct streaming returns `[DONE]` in 0.26s | SDK/child runtime lifecycle | Streaming network path is broken |
| No `run_conversation` entry | Optional imports / lazy installers | Model generation stalled |
| New code visible but no new UI | Pinned frontend image digest vs GHCR publication | PR merge automatically deployed frontend |
| Browser reload still shows messages | Canonical DB record and authenticated API | Browser session is the canonical store |

**Production hardening backlog:** bounded sanitized phase diagnostics in personal worker; never dump prompts, keys or arbitrary SDK stderr into public logs. The current worker redirects its child stdout/stderr to `DEVNULL`.

## 5. CI and GitOps teaching example

There are two separate image/reconciliation modes, by design:

**ACP development personal worker:** ACP CI -> GitHub Actions publishes SHA-tagged Hermes images to GHCR -> infrastructure automation verifies both images -> updates only the personal-worker image field in infra Git -> isolated auto-synced Argo Application rolls the new worker. The parent ACP Application remains manual because it owns API, PostgreSQL, migration resources and administrative Hermes.

**Quantum Platform frontend:** merging UI code triggers CI and image publication. The users Deployment is pinned to a digest in the infrastructure Kustomization. **A new image in GHCR is not automatically deployed.** The reviewed digest promotion changes Git desired state, which Argo then reconciles. Restarting a Pod while the old digest remains pinned only deploys that same old image again.

Do not restart Argo CD controllers, PostgreSQL or every workload to fix a single frontend asset. Distinguish desired image, running Pod imageID and Git commit provenance.

## 6. The observed 30 October 2026 destructive continuity drill

### Baseline and evidence

Project: `5694662f-b8f9-4ee4-a9e4-d1160b9d4728`  
Conversation: `1366e585-7762-40c0-ab36-94c2d6a8db49`  
Title: `Persistence Drill`  
Initial observed messages: **12**  
Marker: `M4A-STARSHIP-7F31`

1. The researcher submitted a marker inside the existing canonical conversation. ACP persisted the user turn and the agent replied with the marker.
2. The operator recorded original project and conversation IDs from PostgreSQL.
3. After the turn completed, the operator restarted **only** the personal-worker Deployment. The Deployment rollout successfully finished.
4. The operator restarted **only** the ACP API Deployment. The rollout successfully finished.
5. The researcher opened the same conversation using a new authenticated Tor browser session. The earlier transcript appeared.
6. The researcher asked what marker had previously been provided. The restarted agent responded `M4A-STARSHIP-7F31`.
7. The operator repeated the two process rollouts and queried the canonical ledger. The three newest personal runs showed `succeeded`, blank failure codes and `reply_saved = t`.
8. A100 logs showed recent successful `/v1/chat/completions` HTTP responses. This is **supporting inference evidence**, not evidence of DB persistence by itself.

The test **proves** an established conversation can be reconstructed from ACP PostgreSQL after both personal-worker and API process replacement and browser-local state loss.

The test **does not prove** a separate Jupyter/SSH client implementation, deletion/restoration of the PostgreSQL volume, an authenticated second-user denial in the live environment, or that all permanent CI/staging restart tests are already automated. See ACP [issue #21](https://github.com/nyameko/agent-control-plane/issues/21) for those remaining conformance gates.

### Evidence-preserving SQL on `k8s-cp-01` only

These are read-only queries. Do not execute credential-bearing `printenv`, reveal private conversation content, or run migrations to collect evidence.

```bash
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
  psql -U acp_owner -d agent_control_plane -c "
SELECT p.id AS project_id, c.id AS conversation_id, c.title, count(m.id) AS messages
FROM acp1.conversation c
JOIN acp1.project p ON p.id=c.project_id
LEFT JOIN acp1.message m ON m.conversation_id=c.id
WHERE c.id='1366e585-7762-40c0-ab36-94c2d6a8db49'
GROUP BY p.id,c.id,c.title;"
```

```bash
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
  psql -U acp_owner -d agent_control_plane -c "
SELECT r.status, r.failure_code,
  EXISTS(SELECT 1 FROM acp1.message m WHERE m.run_id=r.id
    AND m.author_kind='assistant') AS reply_saved
FROM acp1.run r
JOIN acp1.task t ON t.id=r.task_id
WHERE t.kind='personal_turn'
ORDER BY t.created_at DESC
LIMIT 3;"
```

Also record Pod UIDs and actual immutable imageIDs:

```bash
kubectl -n agent-control-plane get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.uid}{"\\n"}{end}'
kubectl -n agent-control-plane get pods -l acp-role=personal-worker \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].imageID}{"\\n"}{end}'
```

**Do not repeat destructive testing automatically on a shared/live researcher service.** Use a staging tenant, controlled test accounts and approved maintenance period.

## 7. Guided workshop (disposable staging only)

**Lab objectives:** inspect schema/readiness, create project/conversation, send one marker, capture IDs, replace runtime/API Pods, reconnect, prove recovery, and test an unauthorized second user.

**Preconditions:** real isolated staging environment, two test AgentPrincipals, verified ACP schema, healthy restricted LiteLLM key, tested backup (if risk assessment requires), explicit operator approval, and a controlled time window.

1. **Inspect:** read `docs/M4-PERSISTENT-AGENTS.md`, worker/adapter code, deployment YAML, and current Argo Application status. Draw the authority diagram.
2. **Create a marker:** record project/conversation UUIDs and run linkage; verify assistant message persisted after browser refresh.
3. **Capture before-state:** record Pod UIDs, deployment imageIDs, PostgreSQL PVC identity and schema versions, without secrets or raw private transcript.
4. **Destructively replace disposable processes:** on `k8s-cp-01` run the following *only with human approval* and only when no active research turn would be interrupted:

   ```bash
   kubectl -n agent-control-plane rollout restart deployment/agent-control-plane-personal-worker
   kubectl -n agent-control-plane rollout status deployment/agent-control-plane-personal-worker --timeout=180s
   kubectl -n agent-control-plane rollout restart deployment/agent-control-plane-api
   kubectl -n agent-control-plane rollout status deployment/agent-control-plane-api --timeout=180s
   ```

5. **Recover:** reopen from a separate authenticated browser, confirm IDs/history and ask for the marker without re-supplying it.
6. **Prove isolation:** use subject B's real identity to attempt list/read/turn submission to A's conversation; all must fail without revealing existence. Do not use an administrator's unrestricted PostgreSQL owner query as an isolation test.
7. **Prove idempotency:** replay the same authorized request ID once in a disposable environment and assert no duplicate canonical message/run.
8. **Record evidence and limits:** include exact before/after UIDs, test owner/tenant identifiers in a protected report, run IDs/statuses, and whether all negative tests were executed; never report missing checks as passed.

## 8. Troubleshooting protocol

Order diagnostic checks by **authority**, not by convenience:

1. **User surface:** Is the browser logged in? Did the authenticated proxy accept the turn? What was the run ID/status?
2. **Canonical ledger:** Did ACP create a task and run? Queued, running, failed or succeeded? Did an assistant row get committed?
3. **Worker lifecycle:** Is exactly one worker active with advisory lock? Is the worker claiming or recovering runs? Readiness heartbeat is not execution completion.
4. **Hermes initialization:** Check whether `AIAgent.__init__` completes. Optional lazy package installs must be disabled for production runtime.
5. **Model route:** Verify authenticated LiteLLM virtual key, configured alias, network egress and streamed/nonstreamed response status with a safe synthetic request.
6. **Hermes completion:** Does the SDK reach and leave `run_conversation`, close resources and emit a valid nonempty final answer?
7. **Persistence:** Does `finish_personal` mark the run succeeded and atomically store the assistant response?
8. **Browser rendering:** Does the portal fetch the canonical message; does a reload also show run status? Portal issue #61 tracks richer polling and run-status recovery.

If an ACP run is already failed, repeatedly refreshing the page does not generate an assistant response. Never silently resubmit a turn with a new idempotency key because it can create duplicate research history.

## 9. Security and research-provenance lessons

- Per-user `AgentPrincipal` UUID and subject-scoped RLS prevent accidental shared histories; negative authentication testing is part of acceptance.
- An agent's claim of having consulted GitHub is not evidence. The M4a agent is deliberately tool-free; its honest response is to state it cannot access external repositories.
- Source URLs, DOI references, manifests and run evidence should be typed citations and reproducible records in later M4 phases, not hallucinated tool results.
- Do not put transcript content, model keys or token credentials into Prometheus labels, public CI logs or Discord messages.
- Failure codes and run status must be retained, not rewritten as successful assistant messages.
- An authenticated LLM is not a privileged infrastructure operator. Agent tool grants, approvals and role scopes come later.

## 10. Assessment, exercises and deliverables

**Exercise A — architecture:** identify five different state owners and explain why Hermes-local SQLite must not become canonical.

**Exercise B — database:** explain how `conversation_id`, message `sequence`, task `input_message_id`, `run_id` and the `message_personal_run_unique` constraint support continuity and deduplication.

**Exercise C — failure forensics:** given a vLLM `200 OK` and ACP `personal_runtime_timeout`, identify three execution stages that may still fail. Explain the Bedrock lazy-install stack trace.

**Exercise D — GitOps:** contrast the isolated auto-synced personal worker with the manually synced parent ACP and the digest-pinned Quantum Platform users Deployment. Explain why `rollout restart` cannot promote a new digest.

**Exercise E — conformance:** use a disposable test environment to capture the same UUID after process replacement and show the unauthorized subject's HTTP denial and message sequence unchanged.

**Expected student artifacts:** annotated architecture diagram, minimal run ledger and schema map, redacted diagnostic timeline, a green/failed/unknown acceptance matrix, and a short reflection on provenance and least privilege.

### Assessment rubric (20 points)

| Criterion | Points |
| --- | ---: |
| State authority / identity explanation | 4 |
| End-to-end trace and schema relationships | 4 |
| Correct failure attribution and root-cause analysis | 4 |
| Safe GitOps/rollout reasoning | 3 |
| Verified continuity evidence and honest test limitations | 5 |

## 11. Future development and known gaps

- **M4a follow-up:** permanent restart/isolation conformance in CI/staging; second-user negative live evidence; dedicated cross-client Jupyter/SSH tests when clients exist; diagnostic visibility; status/polling frontend UX.
- **M4b:** canonical explicit durable memory, provenance, retrieval and correction/revocation (ACP issue #31). A transcript is not a memory.
- **M4c:** projects, scoped memberships, artifacts and research workspaces.
- **M4d:** governed versioned skills with review and capabilities.
- **M4e:** persistent Hermes personas and runtime-native materializations, with ACP as authority.
- **M4f:** ubiquitous Quantum Platform Guide and Jupyter sidebar.
- **M4g:** Starship-style SSH/TUI adapter.
- **Post-M4:** researcher-specific inference budgets, literature/Discord digests, BYOK, team orchestrators, academic fair-use and privacy policies, and portable Org/Markdown archives. These are separate policy and product workstreams.

## References and provenance

1. [ACP M4 milestone](https://github.com/nyameko/agent-control-plane/blob/main/docs/M4-PERSISTENT-AGENTS.md).
2. [ACP identity/state ADR 0007](https://github.com/nyameko/agent-control-plane/blob/main/docs/adr/0007-acp-canonical-agent-context.md).
3. [ACP source and migrations](https://github.com/nyameko/agent-control-plane/tree/main/src/agent_control_plane).
4. [Quantum Platform personal agent frontend](https://github.com/nyameko/quantum-platform/blob/main/apps/users/src/pages/agent.astro).
5. [M4a persistence issue and closeout evidence #21](https://github.com/nyameko/agent-control-plane/issues/21).
6. [Hermes initialization fix PR #27](https://github.com/nyameko/agent-control-plane/pull/27).
7. [M4a frontend shortcut promotion PR #64](https://github.com/nyameko/quantum-platform/pull/64).
8. [LiteLLM / M4a operator runbook](13-litellm-m4a-operator-secrets-image-and-rollout.md).
9. [M4a live closeout runbook](12-m4a-closeout-evidence.md).
10. [M4b scope issue #31](https://github.com/nyameko/agent-control-plane/issues/31).

**Versioning note:** This tutorial documents observed events as of 2026-10-30 and intentionally does not claim current live metrics, backups, multi-user evidence or tests absent from the record. Keep acceptance evidence separate from normative instructions.
