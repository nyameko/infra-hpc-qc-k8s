#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - <<'PY'
from pathlib import Path
import yaml
root = Path("/mnt/data/infra-hpc-qc-k8s")
for p in root.joinpath("ansible").rglob("*.yml"):
    yaml.safe_load(p.read_text())
for p in root.joinpath("terraform/environments/personal").glob("*.yaml"):
    yaml.safe_load(p.read_text())
print("YAML parse checks passed")
PY

grep -R "REPLACE_WITH_EXACT" -n "$ROOT" >/dev/null && echo "NOTE: exact Kubernetes patch still needs to be selected."
