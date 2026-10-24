# ACE federation nftables review and operator acceptance

This is a **review-only** change. Do not install or activate the ACE
default-drop policy as part of the M4a inference playbook. Terraform owns
OpenStack security groups; Ansible owns host-level nftables.

## Confirmed findings

- The Sebowa Wazuh Manager listens on TCP 1514 and 1515.
- Traffic from the ACE A100 reaches the Sebowa edge across wg-fabric.
- A temporary Sebowa nftables input exception for ACE sources made both
  Wazuh TCP ports reachable.
- The NVIDIA A100 PCIe 80GB became usable after manually building and
  installing the open DKMS module for the running Rocky 9 kernel.

## Sebowa nftables persistence

The existing `edge` role renders `roles/edge/templates/edge.nft.j2`.
It now accepts an **optional** protected inventory list:

```yaml
edge_fabric_wazuh_cidrs:
  - <ACE_PRIVATE_SUBNET>
  - <ACE_EDGE_FABRIC_PEER_IP>/32
```

The rule permits only TCP 1514/1515 arriving on `wg-fabric`.
It does **not** grant federated hosts access to Wazuh API TCP 55000.

Check Sebowa OpenStack edge security group *separately*: its
`federated_site_cidrs` can include the ACE private subnet and the
ACE edge tunnel peer /32 when both source classes are authorized.
Review Terraform plans; do not replace any security group or host.

Validate before applying:

1. Save the active nftables ruleset, host access details and VPN keys
   outside the public repository.
2. Render the updated template with the protected Sebowa inventory.
3. Run `nft -c -f <rendered-file>`; keep a recovery console and rollback.
4. Apply in a maintenance window, separately from ACE GPU provisioning.
5. Verify TCP 1514/1515, enrollment and `agent_control -l` registration.

**Warning:** The two manually inserted nftables rules currently live only
in the running ruleset. Restarting the Sebowa nftables service before the
Git-managed replacement is deployed will remove them.

## ACE nftables role: review-only

`ansible/roles/ace_edge_nftables` is deliberately not included in
`playbooks/ace-inference.yml`, and it does not enable/restart the nftables
service. It writes the candidate rules and persistence entrypoint only.

Before an authorized future activation, set in protected ACE host_vars:

```yaml
ace_nft_admin_cidrs: ["<AUTHORIZED_ADMIN_PUBLIC_CIDR>"]
ace_nft_fabric_peer_public_cidrs: ["<SEBOWA_PUBLIC_ENDPOINT_CIDR>"]
ace_nft_local_cidr: "<ACE_PRIVATE_SUBNET>"
ace_nft_remote_cidrs: ["<SEBOWA_MANAGEMENT_SUBNET>", "<SEBOWA_K8S_SUBNET>"]
ace_nft_fabric_peer_cidr: "<SEBOWA_FABRIC_PEER_IP>/32"
```

Review the live ACE edge interface name. The proposed policy uses
an explicit interface, permits established traffic, SSH from trusted
management/administration sources, the trusted site-to-site UDP peer,
and routed traffic to/from the private ACE network. No masquerading.

**Operational caveat:** The candidate flushes the complete nftables
ruleset and replaces it with its own default-drop policy. It is therefore
unsafe to activate without a complete inventory of pre-existing rules,
recovery access and a timed rollback. Run the role only after that review,
and activate the service separately and deliberately.

## NVIDIA open DKMS

The NVIDIA role now installs EPEL/CRB prerequisites, tests
`modinfo nvidia`, and only builds/installs NVIDIA's registered DKMS
source when the module is missing for the running kernel. Review and test
kernel upgrades separately before declaring this path production-ready.

## M4a gate

Do not treat mere TCP reachability as Wazuh enrollment. Verify agent key
presence without printing secrets, and check agent registration on the
Sebowa manager. Keep the inference path separate:

NVIDIA -> CDI -> 1 TB /srv/models -> DCGM -> vLLM -> Qwen3.5-27B
-> LiteLLM -> ACP -> destructive ACP-PERSIST recovery acceptance.
