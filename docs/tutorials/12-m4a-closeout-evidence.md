# M4a closeout — portal-first destructive continuity (operator runbook)

**This is the authoritative M4a live acceptance route.** Do not clone repositories, install `argocd` CLI, or place ad-hoc Python scripts on `k8s-cp-01`. Use the existing Quantum Platform personal-agent page in the researcher's browser and the installed `kubectl` on `k8s-cp-01`. The optional historical `tools/m4a-conformance.py` is **not** required for closeout.

M4a still **cannot** close from Kubernetes Ready/Healthy states alone. The canonical project, conversation, messages, task/run/event lineage, idempotency and subject isolation must survive disposable runtime interruption with observed evidence. Do not treat Hermes' profile volume as the canonical transcript.

## Gate 0: Prerequisites and safe evidence (no destruction)

On `k8s-cp-01`, record redacted outputs:

```sh
kubectl -n argocd get applications agent-control-plane litellm
kubectl -n agent-control-plane get pods,deployments,statefulsets,pvc -o wide
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
  psql -U acp_owner -d agent_control_plane \
  -c '\dt acp1.*'
kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
  psql -U acp_owner -d agent_control_plane \
  -c 'SELECT version FROM acp1.schema_version ORDER BY version;'
```

The database tables live under schema **`acp1`**, so plain `\dt` (default `public`) can misleadingly say "no tables". Require schema versions **1, 2, 3**, correct app health and a successful **authenticated** LiteLLM `research-general` model request using a restricted ACP credential (not LiteLLM's master key). Preserve the existing canonical 20 GiB PostgreSQL PVC; do not touch its volume. Keep secrets and transcript contents out of public GitHub logs.

## Gate 1: Establish a canonical conversation in the researcher portal

On `blackmyth`'s browser, log into the deployed Quantum Platform User Portal and open its **Personal Agent** page (route `/agent/`; the site chooses its origin). It calls the existing authenticated proxy `/api/v1/agent/...` and generates a per-user `agent:personal` EdDSA JWT on the server, not in the browser.

1. Create project **M4 Persistence Test** and conversation **Persistence Drill**.
2. Send a unique harmless fact such as **ACP-PERSIST-7F31-<random suffix>** and confirm the assistant's reply is displayed and persisted.
3. Capture project UUID, conversation UUID, message sequence / IDs, and task/run UUID from the portal's browser Developer Tools Network responses. Record the original POST's `Idempotency-Key` and `client_message_id` privately. No custom client script, secret exports, or repository checkout is required on the control plane.
4. With the PostgreSQL owner session on `k8s-cp-01`, check canonical rows without dumping content:
   ```sh
   kubectl -n agent-control-plane exec agent-control-plane-postgres-0 -- \
     psql -U acp_owner -d agent_control_plane \
     -c 'SELECT count(*) AS projects FROM acp1.project; SELECT count(*) AS conversations FROM acp1.conversation; SELECT count(*) AS messages FROM acp1.message; SELECT count(*) AS tasks FROM acp1.task; SELECT count(*) AS runs FROM acp1.run; SELECT count(*) AS events FROM acp1.event;'
   ```
   Record the identified test conversation's message IDs/order in the portal's Network response; totals alone are not evidence of continuity.

## Gate 2: Destroy only disposable state (operator-approved)

1. Record before-restart API and personal-worker Pod names/UIDs: `kubectl -n agent-control-plane get pods -o wide` and `kubectl -n agent-control-plane get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.metadata.uid}{"\n"}{end}'`.
2. Close the researcher browser, disconnect the client SSH session, and if participating in this drill, **identify and stop only the disposable test user's Jupyter Pod** (not production shared services).
3. On `k8s-cp-01`, after approving the brief interruption:
   ```sh
   kubectl -n agent-control-plane rollout restart deployment/agent-control-plane-personal-worker
   kubectl -n agent-control-plane rollout status deployment/agent-control-plane-personal-worker --timeout=180s
   kubectl -n agent-control-plane rollout restart deployment/agent-control-plane-api
   kubectl -n agent-control-plane rollout status deployment/agent-control-plane-api --timeout=180s
   ```
4. Record new Pod UIDs and unchanged PostgreSQL PVC name/Bound identity. Do **not** restart or erase PostgreSQL, wipe any PVC, reset the DB, or repeat migration hooks.

## Gate 3: Reconnect, reconstruct, isolate

1. Reopen the researcher portal in a new browser session, ideally on a second device/surface, sign in as the same user, select the **same project and conversation UUIDs** and verify exactly the original canonical transcript/messages and sequence remain.
2. Ask **"What marker did I give you earlier?"**, and require the new assistant reply to reproduce the marker. Confirm the new run succeeds and is stored in the canonical message/run history.
3. With a **different** real researcher account, confirm their project list does not contain the first subject's project. Using that second account's authenticated browser session, a direct URL `/api/v1/agent/conversations/<FIRST_USER_CONVERSATION_UUID>/` must return a not-found response; attempts to append or submit a turn must also be denied. Capture the HTTP results, not credentials.
4. Replay the **same original POST including `Idempotency-Key` and `client_message_id`** once through the browser's authenticated Network developer-tools replay mechanism (if supported by the browser). It must reference the original message/task/run and must **not** add a second message/run. The existing automated CI idempotency checks are supplemental evidence, not substitutes for lost canonical history.
5. Confirm the original project's/conversation's/message IDs, initial task/run/event IDs, and PostgreSQL records survive unchanged, with additional new turn appended and no cross-user access.

## Gate 4: Close ACP issue #21 only with observed results

Attach a short, redacted evidence summary to [ACP issue #21](https://github.com/nyameko/agent-control-plane/issues/21): Git revision and image IDs, ACP schema versions, before/after Pod UIDs, unchanged PVC IDs, initial and recovered conversation IDs, event/run checks, subject-B denial, and test result. A successful model answer **without verified canonical preservation**, or all green Kubernetes readiness checks alone, is not sufficient.

LiteLLM's virtual-key budgeting and Paperclip are parallel workstreams; authenticated model generation and an ACP-scoped restricted key are required for the personal-agent run. M4b memory, M4c projects, M4d skills, M4e profiles, M4f Guide and M4g SSH are **not** M4a closure conditions.
