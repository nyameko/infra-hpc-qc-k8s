#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK="${ANSIBLE_TEST_PLAYBOOK:-ansible/playbooks/argo_cd.yml}"
INVENTORY="${ANSIBLE_TEST_INVENTORY:-ansible/inventories/private/hosts.yml}"

[[ -f "$PLAYBOOK" ]] || { echo "Missing playbook: $PLAYBOOK"; exit 1; }
[[ -f "$INVENTORY" ]] || { echo "Missing inventory: $INVENTORY"; exit 1; }

echo "Ansible convergence test: $PLAYBOOK"

run_playbook() {
  ansible-playbook -i "$INVENTORY" "$PLAYBOOK" "$@"
}

run_playbook
echo "First application completed."

second_run="$(mktemp)"
trap 'rm -f "$second_run"' EXIT

run_playbook | tee "$second_run"

if grep -Eq 'changed=[1-9][0-9]*' "$second_run"; then
  echo "WARNING: second run reported changes."
  echo "This is the convergence signal to investigate; the preliminary test does not fail yet."
else
  echo "Second run reported no changes."
fi
