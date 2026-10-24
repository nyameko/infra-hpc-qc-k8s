# M4a destructive continuity acceptance evidence

This checklist accompanies `tools/m4a-conformance.py`. **Do not close ACP issue #21 from script output alone.** The script is a client-side check; it cannot verify that Kubernetes Pod replacement actually occurred. All cluster commands below are **manual operator actions on `k8s-cp-01`**, after explicit approval and after verifying backups and compatible images.

## Prerequisites

- ACP schema v3 deployed on dedicated PostgreSQL with retained/bound PVC; database migration successful.
- ACP API and personal worker Ready; pinned image digests correspond to the reviewed commits; model generation succeeds through an approved authenticated route.
- Primary and secondary short-lived `agent:personal` bearer tokens issued for **different** AgentPrincipal subjects. Keep credentials out of files, shell history, logs and GitHub.
- A backed-up database and a window approved for stateless worker/API interruption.
- Independent evidence that the Quantum Platform personal client authenticates and reconnects to the same conversation.

## Prepare state (non-destructive)

From an authorized client with network access to ACP, outside the checkout or in a secure local session:

```sh
umask 077
# Export ACP_BASE_URL and both short-lived bearer tokens securely (not in shell history).
python tools/m4a-conformance.py --state /tmp/m4a-acceptance-state.json start
```

The file contains only a generated marker, UUIDs, transcript fingerprint and the idempotency key (not bearer secrets). Preserve it between phases. An existing state file causes `start` to fail deliberately.

## Destructive phases (record independent evidence)

1. Record UTC timestamp, Git revision/image digests and `argocd app get agent-control-plane` / resource health from `k8s-cp-01`.
2. Record `kubectl -n agent-control-plane get pods,pvc,jobs -o wide` and migration Job evidence. Confirm **PostgreSQL PVC remains bound**; do **not** remove or reinitialize the database.
3. Close browser, attach to the project/conversation from a separate authorized surface (portal/workbench API), and record returned project and conversation UUIDs. Stop the disposable Jupyter user Pod and disconnect the SSH client session.
4. From `k8s-cp-01`, after operator approval, record worker Pod UID, run `kubectl -n agent-control-plane delete pod -l acp-role=personal-worker`, then `kubectl -n agent-control-plane rollout status deployment/agent-control-plane-personal-worker`. Record **new Pod UID**. The worker has ephemeral `emptyDir` runtime state, so replacement also destroys its local Hermes cache.
5. Record API Pod UID, run `kubectl -n agent-control-plane rollout restart deployment/agent-control-plane-api` and `kubectl -n agent-control-plane rollout status deployment/agent-control-plane-api`. Record new UID and readiness.
6. Confirm the same PostgreSQL PVC identity and existing schema v3 after replacement, and revisit the portal on a fresh browser session.

No live destructive command is embedded in the test script or executed by this PR.

## Verify (after replacement)

```sh
python tools/m4a-conformance.py --state /tmp/m4a-acceptance-state.json verify
```

The verifier checks:
- Stable project/conversation UUIDs, project linkage, original message UUIDs and SHA-256 transcript fingerprint.
- Original run and task linkage, successful status and durable event history.
- Replay of the original idempotency key returns the original message/task/run without a duplicate.
- A second real user cannot enumerate the owner's project or conversation, read the known conversation/run, append a message or submit a turn.
- A new generated assistant turn reconstructs the original marker using canonical history.

The verifier **requires** a second-user bearer token. A real missing-user isolation check must fail closed.

## Closeout decision

Attach redacted outputs and evidence to [agent-control-plane issue #21](https://github.com/nyameko/agent-control-plane/issues/21): before/after resource IDs and timestamps, Argo status, database migration/PVC identity, script JSON, second-user test, and a portal/second-surface reconnection result. Include CI/staging conformance evidence and Phase-1 compatibility checks. **M4a is only complete after every required gate passes.**

LiteLLM PostgreSQL accounting/virtual-key budgets, Paperclip and GPU/QPU scientific execution are separately tracked; a secure approved model path is required for the live run but those broader workstreams are not M4a closure criteria.
