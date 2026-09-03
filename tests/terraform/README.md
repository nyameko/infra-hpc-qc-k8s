# Terraform / OpenStack tests

These tests deliberately separate **policy/security validation** from **infrastructure validation**.

## Policy / security

The first CI layer is static IaC analysis. The workflow currently uses Checkov as a preliminary guard.

This will grow into provider-aware assertions such as:

- SSH exposure is restricted to the management/VPN trust boundary.
- Kubernetes API access is restricted to the intended network.
- etcd and kubelet ports are not publicly exposed.
- Cilium VXLAN/health/NodePort rules are scoped to the Kubernetes network.
- security groups do not accidentally permit unrestricted administrative access.
- public floating IPs exist only where explicitly intended.
- provider credentials never appear in Terraform configuration or plan artifacts.

These are **security contracts**, not tests of whether a VM happens to be running.

## Infrastructure tests

Provider-backed tests should execute against the reference OpenStack environment and verify:

- expected networks/subnets exist;
- expected ports and security groups exist;
- required instances exist;
- expected addresses are assigned;
- Kubernetes API endpoint is reachable;
- instances are in the expected OpenStack state;
- the deployed topology matches the declared topology.

The first executable smoke-test entry point is `tests/terraform/openstack_smoke.sh`.

Do not make these tests depend on a developer laptop being permanently online. They are suitable for a protected/self-hosted integration runner when we enable provider-backed CI.
