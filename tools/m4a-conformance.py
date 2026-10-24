#!/usr/bin/env python3
"""M4a live conformance client for an already deployed ACP.

This script intentionally has no Kubernetes credentials and performs no destructive
cluster action itself. Run "start", restart/delete disposable components with the
operator tooling, then run "verify" with a fresh short-lived ACP token.

Required environment:
  ACP_BASE_URL
  ACP_BEARER_TOKEN

Optional:
  ACP_SECOND_BEARER_TOKEN   exercises cross-user isolation during verify
"""

import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


def request(method, path, *, token, body=None, idempotency_key=None, expected=(200, 201, 202)):
    base = os.environ["ACP_BASE_URL"].rstrip("/")
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if idempotency_key:
        headers["Idempotency-Key"] = str(idempotency_key)

    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            payload = json.loads(response.read() or b"{}")
            if response.status not in expected:
                raise RuntimeError(f"{method} {path}: unexpected status {response.status}")
            return response.status, payload
    except urllib.error.HTTPError as exc:
        payload = exc.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path}: HTTP {exc.code}: {payload}") from exc


def poll_run(run_id, token, timeout=240):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        _, run = request("GET", f"/v1/runs/{run_id}", token=token)
        if run["status"] == "succeeded":
            return run
        if run["status"] == "failed":
            raise RuntimeError(
                f"run {run_id} failed: {run.get('failure_code') or 'unknown failure'}"
            )
        time.sleep(2)
    raise TimeoutError(f"run {run_id} did not complete within {timeout}s")


def messages(conversation):
    return conversation.get("messages", [])


def content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, dict) and isinstance(content.get("text"), str):
        return content["text"]
    return json.dumps(content, sort_keys=True)


def fingerprint(items):
    """Fingerprint canonical messages, including IDs, sequence, provenance and content."""
    import hashlib

    encoded = json.dumps(items, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def assert_original(state, detail, *, exact_count=False):
    require(detail["id"] == state["conversation_id"], "conversation ID changed")
    require(detail["project_id"] == state["project_id"], "project linkage changed")
    items = messages(detail)
    initial_count = state["initial_message_count"]
    require(len(items) >= initial_count, "original canonical messages were lost")
    if exact_count:
        require(len(items) == initial_count, "unexpected messages before continuation")
    original = items[:initial_count]
    require(
        [item["id"] for item in original] == state["initial_message_ids"],
        "original message UUIDs changed",
    )
    require(
        fingerprint(original) == state["initial_messages_sha256"],
        "original transcript or message lineage changed",
    )


def cmd_start(args):
    token = os.environ["ACP_BEARER_TOKEN"]
    require(not args.state.exists(), "state file exists; choose a new path for a new drill")
    marker = f"ACP-PERSIST-7F31-{uuid.uuid4().hex[:8].upper()}"
    idempotency_key = str(uuid.uuid4())
    client_message_id = f"m4a-start-{uuid.uuid4()}"
    original_content = {"text": f"Remember this marker: {marker}"}

    _, project = request(
        "POST", "/v1/projects", token=token, body={"title": "M4 Persistence Test"}
    )
    _, conversation = request(
        "POST",
        "/v1/conversations",
        token=token,
        body={"title": "Persistence Drill", "project_id": project["id"]},
    )
    _, turn = request(
        "POST",
        f"/v1/conversations/{conversation['id']}/turns",
        token=token,
        idempotency_key=idempotency_key,
        body={
            "content": original_content,
            "source_channel": "api",
            "client_message_id": client_message_id,
        },
    )
    run = poll_run(turn["run_id"], token)
    _, detail = request(
        "GET", f"/v1/conversations/{conversation['id']}", token=token
    )
    initial = messages(detail)
    require(
        any(marker in content_text(item.get("content")) for item in initial),
        "original user marker is absent from canonical conversation",
    )
    require(
        any(
            item.get("author_kind") == "assistant"
            and item.get("run_id") == run["run_id"]
            for item in initial
        ),
        "initial assistant response missing from canonical PostgreSQL transcript",
    )
    require(
        run.get("task_id") == turn.get("task_id")
        and run.get("conversation_id") == conversation["id"],
        "initial task/run lineage is inconsistent",
    )
    require(run.get("events"), "initial run has no recorded events")

    state = {
        "marker": marker,
        "project_id": project["id"],
        "conversation_id": conversation["id"],
        "initial_message_id": turn["message_id"],
        "initial_task_id": turn["task_id"],
        "initial_run_id": run["run_id"],
        "initial_message_count": len(initial),
        "initial_message_ids": [item["id"] for item in initial],
        "initial_messages_sha256": fingerprint(initial),
        "idempotency_key": idempotency_key,
        "client_message_id": client_message_id,
        "original_content": original_content,
    }
    args.state.write_text(json.dumps(state, indent=2) + "\n")
    args.state.chmod(0o600)
    print(json.dumps(
        {key: value for key, value in state.items()
         if key not in ("original_content", "initial_message_ids")},
        indent=2,
    ))
    print(
        "START PASS: canonical data recorded. An operator must now destroy "
        "the disposable client/runtime state, then execute verify."
    )


def expect_denied(token, path, *, method="GET", body=None, idempotency_key=None):
    base = os.environ["ACP_BASE_URL"].rstrip("/")
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if idempotency_key:
        headers["Idempotency-Key"] = idempotency_key
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(
        base + path, data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            raise RuntimeError(
                f"second user unexpectedly accessed {method} {path}: "
                f"HTTP {response.status}"
            )
    except urllib.error.HTTPError as exc:
        require(
            exc.code == 404,
            f"second-user isolation expected 404 for {method} {path}; got {exc.code}",
        )


def expect_isolated(token, state):
    project_id = state["project_id"]
    conversation_id = state["conversation_id"]
    run_id = state["initial_run_id"]

    _, projects = request("GET", "/v1/projects", token=token)
    require(
        all(item["id"] != project_id for item in projects["items"]),
        "second user enumerated private project",
    )
    _, conversations = request("GET", "/v1/conversations", token=token)
    require(
        all(item["id"] != conversation_id for item in conversations["items"]),
        "second user enumerated private conversation",
    )
    _, filtered = request(
        "GET", f"/v1/conversations?project_id={project_id}", token=token
    )
    require(
        not filtered["items"],
        "second user enumerated conversations by private project ID",
    )
    expect_denied(token, f"/v1/conversations/{conversation_id}")
    expect_denied(token, f"/v1/runs/{run_id}")
    expect_denied(
        token,
        f"/v1/conversations/{conversation_id}/messages",
        method="POST",
        body={
            "author_kind": "user",
            "content": {"text": "unauthorized append"},
            "source_channel": "api",
            "client_message_id": f"m4a-isolation-{uuid.uuid4()}",
        },
    )
    expect_denied(
        token,
        f"/v1/conversations/{conversation_id}/turns",
        method="POST",
        idempotency_key=str(uuid.uuid4()),
        body={
            "content": {"text": "unauthorized turn"},
            "source_channel": "api",
            "client_message_id": f"m4a-isolation-turn-{uuid.uuid4()}",
        },
    )


def cmd_verify(args):
    token = os.environ["ACP_BEARER_TOKEN"]
    second = os.getenv("ACP_SECOND_BEARER_TOKEN")
    require(
        second,
        "ACP_SECOND_BEARER_TOKEN is required for M4a acceptance; "
        "isolation cannot be skipped",
    )
    state = json.loads(args.state.read_text())
    marker = state["marker"]
    conversation_id = state["conversation_id"]

    _, before = request(
        "GET", f"/v1/conversations/{conversation_id}", token=token
    )
    assert_original(state, before, exact_count=True)
    _, initial_run = request(
        "GET", f"/v1/runs/{state['initial_run_id']}", token=token
    )
    require(initial_run["status"] == "succeeded", "initial run status did not persist")
    require(
        initial_run.get("task_id") == state["initial_task_id"]
        and initial_run.get("conversation_id") == conversation_id
        and initial_run.get("events"),
        "initial run lineage/events did not persist",
    )
    _, projects = request("GET", "/v1/projects", token=token)
    require(
        any(item["id"] == state["project_id"] for item in projects["items"]),
        "canonical project missing from owning subject's project list",
    )
    _, conversations = request(
        "GET", f"/v1/conversations?project_id={state['project_id']}", token=token
    )
    require(
        any(item["id"] == conversation_id for item in conversations["items"]),
        "canonical conversation missing from owning subject's list",
    )

    # Replaying the same request after runtime loss must not duplicate the task,
    # run or user message. This exercises PostgreSQL idempotency across processes.
    status, replay = request(
        "POST",
        f"/v1/conversations/{conversation_id}/turns",
        token=token,
        idempotency_key=state["idempotency_key"],
        body={
            "content": state["original_content"],
            "source_channel": "api",
            "client_message_id": state["client_message_id"],
        },
        expected=(200,),
    )
    require(
        status == 200
        and replay.get("message_id") == state["initial_message_id"]
        and replay.get("task_id") == state["initial_task_id"]
        and replay.get("run_id") == state["initial_run_id"],
        "replayed idempotency key created or referenced a different turn",
    )
    _, replay_detail = request(
        "GET", f"/v1/conversations/{conversation_id}", token=token
    )
    assert_original(state, replay_detail, exact_count=True)

    expect_isolated(second, state)
    _, isolated_detail = request(
        "GET", f"/v1/conversations/{conversation_id}", token=token
    )
    assert_original(state, isolated_detail, exact_count=True)

    _, turn = request(
        "POST",
        f"/v1/conversations/{conversation_id}/turns",
        token=token,
        idempotency_key=str(uuid.uuid4()),
        body={
            "content": {"text": "What marker did I give you earlier?"},
            "source_channel": "api",
            "client_message_id": f"m4a-verify-{uuid.uuid4()}",
        },
    )
    run = poll_run(turn["run_id"], token)
    _, after = request(
        "GET", f"/v1/conversations/{conversation_id}", token=token
    )
    assert_original(state, after)
    assistant = [
        content_text(item.get("content"))
        for item in messages(after)
        if item.get("author_kind") == "assistant"
        and item.get("run_id") == run["run_id"]
    ]
    require(
        len(assistant) == 1 and marker in assistant[0],
        "post-restart assistant failed to reconstruct marker from canonical context",
    )
    expect_denied(second, f"/v1/runs/{run['run_id']}")

    print(json.dumps(
        {
            "marker": marker,
            "project_id": state["project_id"],
            "conversation_id": conversation_id,
            "initial_task_id": state["initial_task_id"],
            "initial_run_id": state["initial_run_id"],
            "verification_run_id": run["run_id"],
            "canonical_transcript_preserved": True,
            "run_lineage_preserved": True,
            "idempotency_replay_preserved": True,
            "second_user_list_read_append_isolation": True,
            "model_reconstructed_marker": True,
        },
        indent=2,
    ))
    print(
        "API/POSTGRES CONFORMANCE PASS. This does NOT by itself close M4a: "
        "attach operator evidence of the actual Jupyter/client loss, "
        "personal-worker replacement/cache loss, ACP API restart, "
        "Argo CD health and PVC survival to issue #21."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--state",
        type=Path,
        required=True,
        help="Local state file containing only test marker and ACP UUIDs; no credentials.",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("start")
    sub.add_parser("verify")
    args = parser.parse_args()

    if not os.getenv("ACP_BASE_URL") or not os.getenv("ACP_BEARER_TOKEN"):
        parser.error("ACP_BASE_URL and ACP_BEARER_TOKEN are required")

    if args.command == "start":
        cmd_start(args)
    else:
        cmd_verify(args)


if __name__ == "__main__":
    main()
