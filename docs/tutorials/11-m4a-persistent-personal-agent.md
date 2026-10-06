# M4a — persistent personal-agent deployment and destructive continuity test

This runbook activates the smallest M4 personal-agent vertical slice.

It deliberately does **not** introduce durable memory, rich project workspaces,
skills, persistent personal Hermes profiles, Paperclip, accelerated inference
routing, or QPU execution.

The M4a assertion is narrower:

> Canonical conversation state belongs to ACP PostgreSQL and survives loss of
> the browser, Jupyter Pod, SSH session, ACP API Pod and personal-agent runtime
> Pod.

## 1. Deployment shape

The M4a deployment keeps the Phase-1 administrative worker intact and adds a
separate personal worker:

```text
Quantum Platform user-api
        |
        | short-lived agent:personal assertion
        v
agent-control-plane-api
        |
        v
ACP PostgreSQL  <-------- canonical project/conversation/task/run state
        ^
        |
personal-worker Deployment
        |
        +---- fresh ephemeral Hermes profile per run
        |
        +---- configured model endpoint

admin Hermes StatefulSet
        |
        +---- persistent admin-readonly profile
        +---- Prometheus diagnostic access
```

The personal worker is intentionally a `Deployment`, not a `StatefulSet`, and
has no PVC. Its `/tmp` is an `emptyDir`. Deleting the Pod therefore destroys
runtime-local state and is a valid M4a continuity test.

Persistent Hermes profiles are M4e.

## 2. Required compatible application versions

Do not deploy this manifest until compatible M4a commits/images exist for:

- `agent-control-plane`: schema v3 + personal turn worker/API;
- `quantum-platform`: `agent:personal` assertion + proxy/UI.

The ACP migration Job runs at sync wave 1. API/admin-worker/personal-worker run at
wave 2. The API readiness endpoint requires the latest schema, so a failed
migration prevents the new application slice from becoming Ready.

Pin the tested API and Hermes image digests through the existing configuration
workflow. The personal worker deliberately uses the same reviewed Hermes image
as the administrative worker.

## 3. Network boundary

The namespace remains default-deny.

The personal worker is allowed only:

- DNS;
- ACP PostgreSQL on TCP/5432;
- the explicitly configured model endpoint.

It is **not** allowed Prometheus access and receives no Kubernetes service-account
token. The existing administrative worker keeps its Prometheus path.

The configured model NetworkPolicy applies to both `worker` and
`personal-worker`; keep its destination narrow.

## 4. Static validation

Render before sync:

```sh
kubectl kustomize argocd/resources/agent-control-plane > /tmp/acp-m4a.yaml
python tools/check-agent-phase1.py /tmp/acp-m4a.yaml
```

Inspect the rendered personal worker:

```sh
grep -A120 'name: agent-control-plane-personal-worker' /tmp/acp-m4a.yaml
```

Verify:

- no ServiceAccount token mount;
- no PVC/profile volume;
- only the `tmp` emptyDir;
- pinned Hermes image digest;
- database/model Secret references;
- `acp-role: personal-worker`.

## 5. Migration and rollout

Back up ACP PostgreSQL before the first schema-v3 migration.

Then sync the ACP application and inspect the migration Job before trusting API
readiness:

```sh
kubectl -n agent-control-plane get job acp-migrate
kubectl -n agent-control-plane logs job/acp-migrate
kubectl -n agent-control-plane rollout status deployment/agent-control-plane-api
kubectl -n agent-control-plane rollout status deployment/agent-control-plane-personal-worker
kubectl -n agent-control-plane rollout status statefulset/agent-control-plane-hermes
```

Do not roll the database schema backward as an application rollback strategy.
Keep the additive migration and roll application images forward/back within their
compatibility window.

## 6. Manual M4a acceptance drill

### A. Establish canonical state

1. Sign into `quantum.nyameko.com` as the primary test researcher.
2. Open the M4a Personal Agent surface.
3. Create project **M4 Persistence Test**.
4. Create conversation **Persistence Drill**.
5. Send:

   ```text
   Remember this marker: ACP-PERSIST-7F31
   ```

6. Wait for the personal run to succeed.
7. Record the project UUID, conversation UUID and run UUID from the API/browser
   developer view or database-safe operational tooling.
8. Confirm the assistant reply is visible after a full page reload.

### B. Destroy client state

9. Close the browser completely.
10. Launch the user's Jupyter workbench.
11. When a Jupyter ACP client exists, attach it to the same conversation UUID.
    Until that client lands, use an authenticated API test from the workbench to
    retrieve the same conversation.
12. Stop/delete the Jupyter user Pod.
13. Disconnect all SSH sessions.

None of these actions should alter the ACP conversation.

### C. Destroy runtime state

Capture the personal-worker Pod name:

```sh
kubectl -n agent-control-plane get pod -l acp-role=personal-worker
```

Delete it:

```sh
kubectl -n agent-control-plane delete pod -l acp-role=personal-worker
kubectl -n agent-control-plane rollout status deployment/agent-control-plane-personal-worker
```

Because the worker uses only `emptyDir`, this destroys its runtime-local Hermes
profile/session state.

Do **not** delete the PostgreSQL PVC.

### D. Restart API state

Restart the stateless API:

```sh
kubectl -n agent-control-plane rollout restart deployment/agent-control-plane-api
kubectl -n agent-control-plane rollout status deployment/agent-control-plane-api
```

### E. Resume elsewhere

14. Reopen Quantum Platform.
15. Select **M4 Persistence Test** and **Persistence Drill**.
16. Confirm the same project UUID and conversation UUID.
17. Confirm the original user message and assistant response.
18. Confirm the earlier task/run remains visible through the authenticated API.
19. Ask:

   ```text
   What marker did I give you earlier?
   ```

20. Require the next run to recover `ACP-PERSIST-7F31` from the canonical
    transcript, despite the previous Hermes runtime state having been destroyed.

This is the core M4a proof.

## 7. Cross-user isolation

Create/use a second normal Quantum Platform user.

Verify that user cannot:

- list the first user's project;
- list the first user's conversation;
- retrieve the conversation by a known UUID;
- retrieve the first user's personal run by a known UUID;
- append a turn to the first user's conversation.

A 404-style response is preferred at the API boundary so object existence is not
unnecessarily disclosed.

## 8. Worker interruption semantics

A run that was already marked `running` when its worker dies becomes terminal
`failed / worker_interrupted` when the replacement worker starts.

The canonical user message remains.

M4a does not attempt exactly-once model generation or resume a half-generated
assistant response. The user/client can explicitly retry with a new turn after
observing the failed run.

## 9. Telemetry

Kube-state-metrics exposes the personal-worker Deployment state. Prometheus alerts
if the desired personal-worker replica is unavailable for five minutes.

Operationally inspect:

```sh
kubectl -n agent-control-plane get deployment agent-control-plane-personal-worker
kubectl -n agent-control-plane get pods -l acp-role=personal-worker
kubectl -n agent-control-plane describe pod -l acp-role=personal-worker
```

Do not place conversation UUIDs, user IDs, message contents or run IDs into
Prometheus labels.

Detailed per-run history remains in ACP PostgreSQL/API rather than metrics.

## 10. Permanent automated conformance

After the first live manual drill succeeds, preserve it as an automated staging
test.

The automated test must prove:

```text
browser/client state irrelevant
Jupyter Pod state irrelevant
SSH process state irrelevant
ACP API process state irrelevant
personal-worker process state irrelevant
Hermes runtime cache reconstructable
ACP PostgreSQL authoritative
second user isolated
```

The test should create a unique marker per run, record the created identifiers,
restart/delete disposable components, then assert exact recovery and isolation.

## 11. Rollback

If the personal-agent path is unhealthy:

1. stop/scale the personal-worker Deployment through GitOps;
2. roll Quantum Platform back to a compatible image;
3. roll ACP API/admin worker back only to a version compatible with schema v3;
4. retain ACP PostgreSQL/PVC and all canonical data;
5. investigate before re-enabling personal turns.

Do not delete database volumes or downgrade migrations merely to disable M4a.
