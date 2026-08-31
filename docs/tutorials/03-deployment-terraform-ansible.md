# 3. Deployment: Terraform & Ansible

## 3.1 Local tooling

Verify before touching OpenStack:

```bash
terraform version
ansible --version
openstack --version
kubectl version --client
helm version
```

On an Arch workstation, the toolchain installs with:

```bash
sudo pacman -Syu ansible terraform python-openstackclient
```

**Further reading:** [Terraform install docs](https://developer.hashicorp.com/terraform/install) ·
[Ansible install docs](https://docs.ansible.com/ansible/latest/installation_guide/index.html) ·
[python-openstackclient](https://docs.openstack.org/python-openstackclient/latest/).

## 3.2 OpenStack authentication

Use `clouds.yaml` or environment variables. **Never** put credentials in a `terraform.tfvars` that gets
committed to Git — see `docs/08` §8.1 for the full never-commit list.

Verify access once configured:

```bash
openstack token issue
openstack network list
openstack image list
openstack flavor list
```

**Further reading:** [OpenStack authentication (`clouds.yaml`)](https://docs.openstack.org/python-openstackclient/latest/configuration/index.html) · [OpenStack API docs](https://docs.openstack.org/).

## 3.3 Terraform layer

Repository layout (as committed today):

```text
terraform/
├── environments/personal/
│   ├── main.tf, outputs.tf, providers.tf, variables.tf, versions.tf
│   ├── terraform.tfvars.example
│   └── cloud-init-edge.yaml, cloud-init-node.yaml
└── modules/
    ├── network/
    ├── compute/
    ├── api_lb/
    └── security/
```

Workflow:

```bash
cd terraform/environments/personal
terraform init
terraform validate
terraform plan
terraform apply
```

...or via the Makefile, which wraps the same commands with `-chdir=terraform/environments/personal`:

```bash
make init
make validate
make plan
make apply
```

Expected result: **13 VMs, plus the Kubernetes API load balancer.**

> ⚠ **Gap.** That load balancer is provisioned by the `api_lb` module — a real Terraform module, matching
> an `api_lb_type` variable described in `docs/08` §8.2 — but it is not listed as a row in the VM topology
> table (`docs/01` §1.3), and the repository's committed root `README.md` describes it as an *Octavia* load
> balancer rather than the HAProxy VM the module name and variable imply. Resolve this before teaching it:
> decide whether `api_lb` provisions an HAProxy VM (matches the module/variable naming) or calls Octavia
> (matches the committed README's wording), update whichever document is wrong, and add the resulting node
> to the VM topology table with an IP. `docs/09` recommendation #2 has the full reasoning.

**Further reading:** [Terraform OpenStack provider
docs](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs) ·
[Terraform style guide](https://developer.hashicorp.com/terraform/language/style) ·
[HashiCorp: Terraform module composition](https://developer.hashicorp.com/terraform/language/modules/develop/composition).

## 3.4 Ansible layer

Repository layout (as committed today):

```text
ansible/
├── ansible.cfg
├── group_vars/all.yml
├── inventories/personal/hosts.yml
├── playbooks/
│   ├── bootstrap.yml
│   ├── join-cluster.yml
│   └── kubernetes.yml
└── roles/
    ├── common/
    ├── containerd/
    ├── edge/
    ├── kube_control_plane/
    ├── kube_join_control_plane/
    ├── kube_worker/
    ├── kubernetes_prereqs/
    ├── pihole/
    ├── ssh/
    ├── suricata/
    ├── wazuh_agent/
    └── wireguard/
```

Core commands:

```bash
ansible-inventory -i ansible/inventories/personal/hosts.yml --graph
ansible all -i ansible/inventories/personal/hosts.yml -m ping
ansible-playbook -i ansible/inventories/personal/hosts.yml ansible/playbooks/bootstrap.yml
```

...or via the Makefile:

```bash
make ansible-ping
make bootstrap
```

> ⚠ **Gap.** The Makefile also defines `edge`, `slurm`, `hermes`, and `k8s-prereqs` targets, pointing at
> `ansible/playbooks/edge.yml`, `slurm.yml`, `hermes.yml`, and `kubernetes-prereqs.yml` respectively — and
> the older quick-start guide additionally references `ansible/playbooks/api-lb.yml`, which has no Makefile
> target at all. None of those five playbook files, nor `roles/slurm/` or `roles/hermes/`, appear in the
> repository's current file listing. This is expected for a POC/teaching repo at this stage — it is not a
> broken deployment, it's an *incomplete* one — but it should be tracked explicitly rather than discovered
> by a confused student running `make hermes` on day one. `docs/09` proposes a `STATUS.md` for exactly this,
> and `COURSE_OUTLINE.md` Module 10 turns "write the missing role" into the capstone lab.

**Further reading:** [Ansible best practices
guide](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html) ·
[Ansible roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html).

## 3.5 Variable naming model

Canonical names (repeat from `docs/02` §2.2, since this is where they're enforced):

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr:  10.51.0.0/24
vpn_cidr:  10.60.0.0/24
```

Use the same logical names in Terraform and Ansible wherever the underlying concept is the same — this is
what avoids a translation table (and the drift it inevitably produces) between the two layers.

Diagnose what Ansible actually resolves for a host:

```bash
ansible-inventory -i ansible/inventories/personal/hosts.yml --host edge
```

Search for naming drift across the codebase:

```bash
rg -n 'management_cidr|wireguard_cidr|mgmt_cidr|vpn_cidr|k8s_cidr' ansible/
```

Target state: `management_cidr` and `wireguard_cidr` return **zero** matches; `mgmt_cidr`, `vpn_cidr`, and
`k8s_cidr` are the only names present.

Normal `group_vars/*.yml` edits do not require a cache flush. `--flush-cache` only matters if fact/inventory
caching is actually configured:

```bash
ansible-playbook -i ansible/inventories/personal/hosts.yml ansible/playbooks/bootstrap.yml --flush-cache
```

`ansible-inventory` is the authoritative diagnostic — trust it over reading YAML files by eye when the two
disagree.

## 3.6 Bootstrap sequence

1. **Verify local tooling** (§3.1).
2. **Configure OpenStack** auth via `clouds.yaml`/env vars (§3.2).
3. **Select environment values**:
   ```bash
   cp terraform/environments/personal/example.tfvars terraform/environments/personal/terraform.tfvars
   $EDITOR terraform/environments/personal/terraform.tfvars
   ```
4. **Provision OpenStack**: `make init && make validate && make plan && make apply` → 13 VMs + API LB.
5. **Validate SSH**: `make ansible-ping`.
6. **Base OS**: `make bootstrap`.
7. **Edge, Hermes, Slurm host prep**: `make edge && make hermes && make slurm`.
8. **Kubernetes prerequisites**: `make k8s-prereqs`.
9. **Kubernetes bootstrap**: `make k8s-init`.

Do not deploy Argo CD or applications until all six Kubernetes nodes report `Ready` — see `docs/04` §4.1 for
the validation command.

## 3.7 Time synchronisation

All hosts run `Africa/Johannesburg` as their local timezone; chrony synchronises the actual clock
underneath it — these are two different concerns and both need checking:

```bash
ansible all -m command -a 'timedatectl show -p Timezone --value'
ansible all -m command -a 'chronyc tracking'
```

A healthy node reports `Leap status : Normal`.

**Further reading:** [chrony documentation](https://chrony-project.org/documentation.html).

## 3.8 Validation philosophy

Every phase gets a verification step — a successful `apply` or `ansible-playbook` run is evidence the
*command* succeeded, not proof the *service* works:

```bash
terraform validate
terraform plan
ansible all -m ping
chronyc tracking
timedatectl
wg show
nft list ruleset
systemctl status haproxy
kubectl get nodes
cilium status
kubectl get storageclass
```

## 3.9 Recommended Makefile hygiene

- Add a `make filelist` target that runs `git ls-files > FILELIST.txt`, and run it in CI or as a pre-commit
  hook. `FILELIST.txt` is currently hand-maintained and already lags the Makefile's own targets (§3.4) —
  automating it removes an entire category of drift.
- Add a `make api-lb` target (or fold API-LB configuration into `make edge`) so every playbook referenced in
  the docs has a corresponding, discoverable Makefile entry.
- `make fmt` (running `terraform fmt -recursive`) already exists — consider a matching `make lint` that runs
  `ansible-lint` and `tflint`, so style issues surface before a workshop, not during one.

**Further reading:** [`git ls-files`](https://git-scm.com/docs/git-ls-files) · [pre-commit
framework](https://pre-commit.com/) · [ansible-lint](https://ansible.readthedocs.io/projects/lint/) ·
[tflint](https://github.com/terraform-linters/tflint).
