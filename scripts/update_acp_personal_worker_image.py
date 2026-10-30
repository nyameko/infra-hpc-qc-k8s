"""Advance only the ACP personal-worker image to the reviewed dev commit's published image.

The GitHub Actions caller first checks that BOTH commit-tagged ACP images exist in GHCR.
Only this Deployment's immutable-by-convention SHA tag is changed. No digests or
manual revision annotations, and no Kubernetes API access from Actions.
"""

import os
import re
from pathlib import Path

PATH = Path("argocd/resources/agent-control-plane-personal-worker/deployment.yaml")
IMAGE = "ghcr.io/nyameko/agent-control-plane-hermes"
sha = os.environ["ACP_DEV_SHA"]
if re.fullmatch(r"[0-9a-f]{40}", sha) is None:
    raise SystemExit("ACP_DEV_SHA must be a full lowercase Git SHA-1")

text = PATH.read_text()
pattern = re.compile(
    r"(?m)^(\s*image:\s*)" + re.escape(IMAGE) + r":sha-[0-9a-f]{40}(\s*)$"
)
matches = pattern.findall(text)
if len(matches) != 1:
    raise SystemExit("Expected exactly one personal-worker SHA-tagged image")
new_text = pattern.sub(
    lambda match: match.group(1) + IMAGE + ":sha-" + sha + match.group(2),
    text,
)
if new_text == text:
    print("Already tracking ACP dev image", sha)
else:
    PATH.write_text(new_text)
    print("Advanced personal-worker image to ACP dev commit", sha)
