#!/usr/bin/env python3
"""Prepare reviewed deployment values in Git. Does not contact or change a cluster."""

import argparse
import ipaddress
import re
from pathlib import Path
from urllib.parse import urlsplit

import yaml


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in [
        "api-digest",
        "hermes-digest",
        "platform-digest",
        "model",
        "model-base-url",
    ]:
        parser.add_argument("--" + name, required=True)
    peers = parser.add_mutually_exclusive_group(required=True)
    peers.add_argument("--model-cidr")
    peers.add_argument("--model-namespace")
    parser.add_argument(
        "--model-app", help="app.kubernetes.io/name for a Kubernetes model server"
    )
    parser.add_argument(
        "--model-port", type=int, required=True, help="Destination pod/VM TCP port"
    )
    args = parser.parse_args()
    for value in [args.api_digest, args.hermes_digest, args.platform_digest]:
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", value):
            parser.error("Use image digests returned by the successful image builds")
    url = urlsplit(args.model_base_url)
    if (
        url.scheme not in {"http", "https"}
        or not url.hostname
        or url.username
        or url.password
        or url.query
        or url.fragment
        or not 1 <= args.model_port <= 65535
    ):
        parser.error(
            "Supply a credential-free HTTP(S) model base URL and valid destination port"
        )
    if args.model_cidr:
        address = ipaddress.ip_network(args.model_cidr, strict=True)
        if address.prefixlen != address.max_prefixlen:
            parser.error("Use a single model host (/32 or /128), not a whole subnet")
        peer = {"ipBlock": {"cidr": str(address)}}
    else:
        if not args.model_app:
            parser.error("--model-app is required with --model-namespace")
        peer = {
            "namespaceSelector": {
                "matchLabels": {"kubernetes.io/metadata.name": args.model_namespace}
            },
            "podSelector": {"matchLabels": {"app.kubernetes.io/name": args.model_app}},
        }
    root = Path(__file__).resolve().parents[1] / "argocd"
    acp = root / "resources/agent-control-plane"
    config = yaml.safe_load((acp / "configmap.yaml").read_text())
    config["data"].update(
        ACP_MODEL=args.model, ACP_MODEL_BASE_URL=args.model_base_url.rstrip("/")
    )
    kustomization = yaml.safe_load((acp / "kustomization.yaml").read_text())
    for image, digest in zip(
        kustomization["images"], [args.api_digest, args.hermes_digest], strict=True
    ):
        image.pop("newTag", None)
        image["digest"] = digest
    policies = list(yaml.safe_load_all((acp / "networkpolicy.yaml").read_text()))
    for policy in policies:
        if policy["metadata"]["name"] == "acp-model-egress":
            policy["spec"]["egress"] = [
                {"to": [peer], "ports": [{"protocol": "TCP", "port": args.model_port}]}
            ]
    platform_path = root / "resources/quantum-platform/kustomization.yaml"
    platform = yaml.safe_load(platform_path.read_text())
    component = "../../components/quantum-platform-agent-admin"
    if component not in platform.setdefault("components", []):
        platform["components"].append(component)
    for image in platform["images"]:
        if image["name"] == "quantum-platform-user-api":
            image.pop("newTag", None)
            image["digest"] = args.platform_digest
    for path, value in [
        (acp / "configmap.yaml", config),
        (acp / "kustomization.yaml", kustomization),
        (platform_path, platform),
    ]:
        path.write_text(yaml.safe_dump(value, sort_keys=False))
    (acp / "networkpolicy.yaml").write_text(
        yaml.safe_dump_all(policies, sort_keys=False)
    )
    print(
        "Prepared model access, immutable images and private administrator integration. Review git diff."
    )


if __name__ == "__main__":
    main()
