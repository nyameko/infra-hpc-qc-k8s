#!/usr/bin/env bash
set -euo pipefail

TARGET="${ANSIBLE_FUNCTIONAL_TARGET:-k8s-cp-01}"

command -v ansible >/dev/null || {
  echo "ansible is required"
  exit 1
}

echo "Running preliminary functional checks against ${TARGET}"

ansible -i "${ANSIBLE_FUNCTIONAL_INVENTORY:-ansible/inventories/private/hosts.yml}" "$TARGET" -m ping

# Add service/host contract checks here as each role becomes stable.
# Examples:
#   ansible "$TARGET" -m command -a 'systemctl is-active containerd'
#   ansible "$TARGET" -m command -a 'systemctl is-active kubelet'
#   ansible "$TARGET" -m command -a 'getenforce'

echo "Preliminary Ansible functional checks passed."
