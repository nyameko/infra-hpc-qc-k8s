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


def cmd_start(args):
    token = os.environ["ACP_BEARER_TOKEN"]
    marker = f"ACP-PERSIST-{uuid.uuid4().hex[:8].upper()}"

    _, project = request(
        "POST",
        "/v1/projects",
        token=token,
        body={"title": "M4 Persistence Test"},
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
        idempotency_key=uuid.uuid4(),
        body={
            "content": {"text": f"Remember this marker: {marker}"},
            "source_channel": "api",
            "client_message_id": f"m4a-start-{uuid.uuid4()}",
        },
    )
    run = poll_run(turn["run_id"], token)
    _, detail = request(
        "GET",
        f"/v1/conversations/{conversation['id']}",
        token=token,
    )

    if not any(marker in content_text(item.get("content")) for item in messages(detail)):
        raise RuntimeError("marker user message is absent from canonical conversation")

    state = {
        "marker": marker,
        "project_id": project["id"],
        "conversation_id": conversation["id"],
        "initial_run_id": run["run_id"],
    }
    args.state.write_text(json.dumps(state, indent=2) + "\n")
    print(json.dumps(state, indent=2))
    print("START PASS: canonical state created. Restart disposable components, then run verify.")


def expect_hidden(token, conversation_id, run_id):
    base = os.environ["ACP_BASE_URL"].rstrip("/")
    for path in [
        f"/v1/conversations/{conversation_id}",
        f"/v1/runs/{run_id}",
    ]:
        req = urllib.request.Request(
            base + path,
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
            method="GET",
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                raise RuntimeError(
                    f"second user unexpectedly read {path}: HTTP {response.status}"
                )
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                payload = exc.read().decode(errors="replace")
                raise RuntimeError(
                    f"second-user isolation expected 404 for {path}; got {exc.code}: {payload}"
                ) from exc


def cmd_verify(args):
    token = os.environ["ACP_BEARER_TOKEN"]
    state = json.loads(args.state.read_text())
    marker = state["marker"]
    conversation_id = state["conversation_id"]

    _, before = request(
        "GET",
        f"/v1/conversations/{conversation_id}",
        token=token,
    )
    if not any(marker in content_text(item.get("content")) for item in messages(before)):
        raise RuntimeError("canonical marker disappeared after restart")

    _, turn = request(
        "POST",
        f"/v1/conversations/{conversation_id}/turns",
        token=token,
        idempotency_key=uuid.uuid4(),
        body={
            "content": {"text": "What marker did I give you earlier?"},
            "source_channel": "api",
            "client_message_id": f"m4a-verify-{uuid.uuid4()}",
        },
    )
    run = poll_run(turn["run_id"], token)
    _, after = request(
        "GET",
        f"/v1/conversations/{conversation_id}",
        token=token,
    )
    assistant = [
        content_text(item.get("content"))
        for item in messages(after)
        if item.get("author_kind") == "assistant"
    ]
    if not assistant or marker not in assistant[-1]:
        raise RuntimeError(
            "post-restart assistant response did not recover the canonical marker"
        )

    second = os.getenv("ACP_SECOND_BEARER_TOKEN")
    if second:
        expect_hidden(second, conversation_id, run["run_id"])

    print(
        json.dumps(
            {
                **state,
                "verification_run_id": run["run_id"],
                "assistant_response": assistant[-1],
                "second_user_isolation": bool(second),
            },
            indent=2,
        )
    )
    print("VERIFY PASS: ACP PostgreSQL remained authoritative across runtime restart.")


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
