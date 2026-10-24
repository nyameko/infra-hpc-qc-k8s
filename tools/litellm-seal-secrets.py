#!/usr/bin/env python3
"""Generate strictly scoped SealedSecret YAML without writing plaintext secret files.

Requires the trusted site certificate (not a live cluster connection) and kubeseal
installed on the operator's workstation. No kubectl or yamllint required.
Review the certificate source/fingerprint via the cluster operator first.
"""
import argparse
import getpass
import ipaddress
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import quote, urlsplit


def sealed(cert, namespace, secret_name, fields):
    encrypted = {}
    for field, value in fields.items():
        process = subprocess.run(
            ["kubeseal", "--raw", "--scope", "strict", "--name", secret_name,
             "--namespace", namespace, "--cert", str(cert)],
            input=value.encode(), capture_output=True, check=True,
        )
        encrypted[field] = process.stdout.decode().strip()
    return {
        "apiVersion": "bitnami.com/v1alpha1",
        "kind": "SealedSecret",
        "metadata": {"name": secret_name, "namespace": namespace},
        "spec": {
            "encryptedData": encrypted,
            "template": {"metadata": {"name": secret_name, "namespace": namespace},
                         "type": "Opaque"},
        },
    }


def write_sealed(directory, name, manifest):
    path = directory / f"{name}-sealed.yaml"
    with path.open("x", encoding="utf-8") as file:
        # JSON is also valid YAML. No plaintext secret material is serialized.
        json.dump(manifest, file, indent=2)
        file.write("\n")
    path.chmod(0o600)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cert", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--ace-base-url", required=True,
                        help="Approved private A100 vLLM URL ending in /v1")
    args = parser.parse_args()
    if not args.cert.is_file():
        parser.error("Verified SealedSecrets controller certificate not found")
    uri = urlsplit(args.ace_base_url)
    if uri.scheme != "http" or uri.path.rstrip("/") != "/v1" or not uri.hostname:
        parser.error("Expected verified private http://IP:8000/v1 URL")
    try:
        address = ipaddress.ip_address(uri.hostname)
        if not address.is_private or uri.port != 8000:
            raise ValueError("not private A100 address/port")
    except ValueError:
        parser.error("A100 base URL must contain the confirmed private IPv4/IPv6 on port 8000")
    if not args.output_dir.is_dir():
        parser.error("Output directory must already exist; do not create it under a public checkout without care")
    namespace = "litellm"
    print("Read the following existing/generated values from your encrypted credential vault.")
    owner_password = getpass.getpass("LiteLLM PostgreSQL owner password: ")
    password = getpass.getpass("LiteLLM PostgreSQL application password: ")
    master = getpass.getpass("LiteLLM gateway master key (sk-...): ")
    salt = getpass.getpass("LiteLLM stable salt key: ")
    ace_key = getpass.getpass("Existing A100 vLLM protected bearer key: ")
    if not all((owner_password, password, master, salt, ace_key)) or not master.startswith("sk-"):
        parser.error("All passwords and keys must be supplied from a securely backed-up vault")
    host = "litellm-postgres.litellm.svc.cluster.local"
    db_url = f"postgresql://litellm_app:{quote(password, safe='')}@{host}:5432/litellm?schema=public"
    resources = {
        "litellm-db-owner": {"POSTGRES_PASSWORD": owner_password},
        "litellm-db-app": {"LITELLM_DB_APP_PASSWORD": password, "DATABASE_URL": db_url},
        "litellm-credentials": {
            "LITELLM_MASTER_KEY": master, "LITELLM_SALT_KEY": salt,
            "ACE_VLLM_API_KEY": ace_key, "ACE_VLLM_BASE_URL": args.ace_base_url,
        },
    }
    for name, fields in resources.items():
        # Creates each file only if absent; never overwrite an existing SealedSecret.
        path = write_sealed(args.output_dir, name, sealed(args.cert, namespace, name, fields))
        print(f"Wrote encrypted manifest: {path}")
    print("Encrypted manifest generation complete. Keep the source credentials in "
          "the encrypted vault; preserve the master key and salt through upgrades.")


if __name__ == "__main__":
    main()
