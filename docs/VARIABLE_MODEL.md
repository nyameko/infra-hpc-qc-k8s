# Variable Model

## Canonical network names

Use:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr: 10.51.0.0/24
vpn_cidr: 10.60.0.0/24
```

Do not maintain parallel names such as:

```text
management_cidr
wireguard_cidr
```

## Terraform and Ansible

Use the same logical names in both layers where the concept is the same.

This avoids translation and naming drift.

## Private values

Environment-specific values belong in the private inventory.

Examples:

```text
admin SSH public key
WireGuard peer public keys
WireGuard PSKs
Pi-hole credentials
Wazuh credentials
```

Private material should not be committed.

## Diagnostics

Inspect final host variables:

```bash
ansible-inventory   -i inventories/private/hosts.yml   --host edge
```

Search for variable-name drift:

```bash
rg -n 'management_cidr|wireguard_cidr|mgmt_cidr|vpn_cidr|k8s_cidr' ansible/
```

Remember that normal YAML variable changes do not require flushing a cache. `--flush-cache` is only relevant when an actual fact/inventory cache is configured.
