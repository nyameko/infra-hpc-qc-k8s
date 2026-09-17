#!/usr/bin/env python3
"""Check kubectl kustomize output before first sync. No cluster mutations."""

import argparse
import re
from pathlib import Path

import yaml

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("manifest", type=Path)
args = parser.parse_args()
docs = list(yaml.safe_load_all(args.manifest.read_text()))
errors = []
for item in docs:
    if item["kind"] in {"Deployment", "StatefulSet", "Job"}:
        spec = item["spec"]["template"]["spec"]
        if spec.get("automountServiceAccountToken") is not False:
            errors.append("Service account token must not be mounted")
        for container in spec["containers"]:
            image = container["image"]
            if "agent-control-plane" in image and not re.search(
                r"@sha256:[0-9a-f]{64}$", image
            ):
                errors.append("ACP images must be pinned to successful build digests")
    if item["kind"] == "ConfigMap" and item["metadata"]["name"] == "acp-config":
        if not item["data"].get("ACP_MODEL") or not item["data"].get(
            "ACP_MODEL_BASE_URL"
        ):
            errors.append("Configure the model endpoint and deployed model name")
    if (
        item["kind"] == "NetworkPolicy"
        and item["metadata"]["name"] == "acp-model-egress"
    ):
        if not item["spec"].get("egress"):
            errors.append("Configure a narrow network rule for the model endpoint")
    if item["kind"] in {"Ingress", "ClusterRoleBinding", "RoleBinding"}:
        errors.append("Phase 1 must not expose ingress or Kubernetes credentials")
if errors:
    raise SystemExit("\n".join(sorted(set(errors))))
print(
    "Static deployment gates passed; verify sealed secrets, cluster access and live endpoints next."
)
