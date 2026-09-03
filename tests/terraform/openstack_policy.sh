#!/usr/bin/env bash
set -euo pipefail

# Preliminary provider-aware security contract checks.
#
# Usage:
#   EXPECTED_MANAGEMENT_CIDR=10.50.0.0/24 \
#   EXPECTED_K8S_CIDR=10.51.0.0/24 \
#   ./tests/terraform/openstack_policy.sh

: "${OS_CLOUD:?Set OS_CLOUD to the reference OpenStack cloud}"
: "${EXPECTED_MANAGEMENT_CIDR:?Set EXPECTED_MANAGEMENT_CIDR}"
: "${EXPECTED_K8S_CIDR:?Set EXPECTED_K8S_CIDR}"

command -v openstack >/dev/null || {
  echo "openstack CLI is required"
  exit 1
}

echo "Checking OpenStack security-group policy..."
openstack security group list --long >/dev/null

echo "Policy test skeleton passed basic OpenStack access validation."
echo "TODO: assert explicit ingress/egress contracts from Terraform module outputs."
