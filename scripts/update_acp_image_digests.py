"""Promote only paired, published ACP image digests into reviewed infra manifests.

Called after the upstream ACP main CI and image publication have completed.
Never updates Git refs, clusters, secrets or the migration approval ceiling.
"""

import argparse
import re
from pathlib import Path

BASE = Path("argocd/resources")
API_IMAGE = "ghcr.io/nyameko/agent-control-plane"
HERMES_IMAGE = "ghcr.io/nyameko/agent-control-plane-hermes"
HEX_DIGEST = re.compile(r"sha256:[0-9a-f]{64}\Z")


def valid_digest(value: str) -> str:
    if not HEX_DIGEST.fullmatch(value):
        raise ValueError("Expected immutable sha256:<64 lowercase hex> image digest")
    return value


def rewrite_kustomization(content: str, api: str, hermes: str) -> str:
    for alias, name, digest in (
        ("agent-control-plane-api", API_IMAGE, api),
        ("agent-control-plane-hermes", HERMES_IMAGE, hermes),
    ):
        expression = (
            r"(?m)(^-[ ]name: " + re.escape(alias)
            + r"\n[ ]+newName: " + re.escape(name)
            + r"\n[ ]+digest: )sha256:[0-9a-f]{64}(?=[ \t]*$)"
        )
        content, count = re.subn(expression, lambda m: m.group(1) + digest, content)
        if count != 1:
            raise ValueError(f"Expected exactly one pinned {alias} entry, got {count}")
    return content


def rewrite_worker(content: str, digest: str) -> str:
    expression = (
        r"(?m)^([ \t]*image:[ \t]*)" + re.escape(HERMES_IMAGE)
        + r"@sha256:[0-9a-f]{64}(?=[ \t]*$)"
    )
    content, count = re.subn(
        expression, lambda m: m.group(1) + HERMES_IMAGE + "@" + digest, content
    )
    if count != 2:
        raise ValueError(
            "Expected exactly two pinned Hermes references (worker and init check); "
            f"got {count}"
        )
    return content


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-digest", required=True)
    parser.add_argument("--hermes-digest", required=True)
    args = parser.parse_args()
    api = valid_digest(args.api_digest)
    hermes = valid_digest(args.hermes_digest)

    primary = BASE / "agent-control-plane/kustomization.yaml"
    worker = BASE / "agent-control-plane-personal-worker/deployment.yaml"
    # Validate BOTH complete updates before writing EITHER file.
    current_primary, current_worker = primary.read_text(), worker.read_text()
    new_primary = rewrite_kustomization(current_primary, api, hermes)
    new_worker = rewrite_worker(current_worker, hermes)
    if new_primary != current_primary:
        primary.write_text(new_primary)
    if new_worker != current_worker:
        worker.write_text(new_worker)
    print("Paired ACP API + Hermes digests pinned; no deployment performed")


if __name__ == "__main__":
    main()
