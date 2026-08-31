# 8. Secrets, Variables & Version Policy

## 8.1 Secrets policy

Preferred progression, in order of adoption:

1. **Ansible Vault** for bootstrap secrets.
2. **SOPS + age** for GitOps-managed encrypted Kubernetes secrets.
3. A dedicated secrets manager once the platform is mature enough to justify the operational overhead.

**Never commit any of the following to Git**, under any circumstance:

- OpenStack passwords / application credentials
- Terraform state
- SSH private keys
- WireGuard private keys
- Wazuh credentials
- TLS private keys
- Kubernetes admin kubeconfig
- kubeadm join tokens / certificate keys
- Hermes memory/soul state (`docs/06` §6.8)

**Further reading:** [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) ·
[SOPS](https://github.com/getsops/sops) · [age](https://github.com/FiloSottile/age) · [HashiCorp
Vault](https://developer.hashicorp.com/vault/docs) (the natural "dedicated secrets manager" landing point
referenced in step 3) · [gitleaks](https://github.com/gitleaks/gitleaks) or
[detect-secrets](https://github.com/Yelp/detect-secrets) for pre-commit secret scanning — worth adding now
rather than after the first accidental commit.

## 8.2 Canonical variable model

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr:  10.51.0.0/24
vpn_cidr:  10.60.0.0/24
```

- Use the **same logical names** in Terraform and Ansible wherever the concept is the same — this is what
  avoids a mental translation table (and the drift it produces) between the two layers.
- Do not maintain parallel names such as `management_cidr` or `wireguard_cidr`.
- Environment-specific private values (admin SSH public key, WireGuard peer public keys, WireGuard PSKs,
  Pi-hole credentials, Wazuh credentials) belong in the private inventory, not in shared/committed
  `group_vars`.

Diagnostics:

```bash
ansible-inventory -i ansible/inventories/personal/hosts.yml --host edge
rg -n 'management_cidr|wireguard_cidr|mgmt_cidr|vpn_cidr|k8s_cidr' ansible/
```

Normal YAML variable edits never require a cache flush; `--flush-cache` is only relevant when an actual
fact/inventory cache is configured. `ansible-inventory` output is authoritative over reading YAML by eye.

## 8.3 Version pinning policy

The general rule, stated so it doesn't go stale as this course reruns year over year: **pin an exact,
reviewed version at the point each phase actually begins — don't hard-code a version merely because it was
current when the repository (or this course) started.** Pick the newest minor release that already has at
least one patch release behind it and comfortable runway before its own end-of-life, rather than chasing
the very newest release on day one of a teaching deployment.

Snapshot as of this pack's review date (31 August 2026) — treat these as an example of applying the rule
above, not as the rule itself:

| Component | Current stable (31 Aug 2026) | Notes |
|---|---|---|
| Kubernetes | 1.37.0 (released 26 Aug 2026); 1.36.2, 1.35.6, 1.34.9 also within their support windows | Kubernetes runs an N-2 support policy, giving each minor roughly 14 months total including a 2-month upgrade window; 1.36.x is the more conservative pick for a course that will still be running mid-2027 |
| Cilium | 1.20.0/1.20.1 | The Cilium community maintains stable minor releases for the three most recent minor versions; matches the original `versions.md` guidance to "pin an exact reviewed 1.20.x version" |
| Argo CD | 3.5.x (3.5.2 as of late Aug 2026) | Only the three most recent minor versions are eligible for patch releases, and a new minor ships roughly every three months, so re-check this table before every new course run |
| Slurm / OpenHPC | No fixed pin | Pin after the target Rocky 9 repositories are confirmed, per the original guidance — this one is correctly left open in the source docs |

Upgrades happen as reviewed Git changes, never as automatic floating upgrades — this applies to every
component in the table, not just the ones with an explicit pin today.

**Further reading:** [Kubernetes release policy](https://kubernetes.io/releases/) · [Cilium
releases](https://github.com/cilium/cilium/releases) · [Argo CD release
policy](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/) ·
[endoflife.date](https://endoflife.date/) as a fast way to check support windows across many projects at
once before a course run.
