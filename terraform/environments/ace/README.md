# ACE federated GPU site

This environment is a sanitized template for the ACE OpenStack GPU site.

Do not commit live ACE project IDs, authoritative CIDRs, fixed IPs, floating IPs,
WireGuard keys, OpenStack credentials or Terraform state.

Copy this directory to an ignored private environment, for example:

```text
terraform/environments/private/ace/
```

The first M4a deployment creates:

- `ace-edge-01`: medium edge/gateway VM;
- `ace-gpu-a100-01`: dedicated A100 inference node;
- one private ACE subnet/router;
- a reused floating IP on `ace-edge-01`;
- an attached Cinder model-cache volume on the GPU node;
- security rules for SSH/WireGuard and private model/metrics access;
- static Neutron routes for remote platform CIDRs via `ace-edge-01`.

The public module does not assume authoritative production addresses.
