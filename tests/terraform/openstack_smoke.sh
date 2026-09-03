#!/usr/bin/env bash
set -euo pipefail

: "${OS_CLOUD:?Set OS_CLOUD to the reference OpenStack cloud}"

command -v openstack >/dev/null || {
  echo "openstack CLI is required"
  exit 1
}

echo "OpenStack infrastructure smoke test"

openstack network list >/dev/null
openstack subnet list >/dev/null
openstack server list >/dev/null
openstack security group list >/dev/null

echo "OpenStack API is reachable and core infrastructure resources are queryable."

# Future assertions:
#   - expected network/subnet names and CIDRs
#   - expected VM names and ACTIVE state
#   - API LB address 10.51.0.100
#   - management/Kubernetes/VPN topology
#   - expected security groups and ports
