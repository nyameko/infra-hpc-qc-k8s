# Installation & Testing Guide — `nyameko/infra-hpc-qc-k8s`

This is a phased runbook for deploying the repo end-to-end: 13 OpenStack VMs, base OS hardening, edge/security services, a Slurm cluster, and a kubeadm Kubernetes cluster.

**Before you start:** a prior audit of this repo (same-day, 2-commit snapshot as of 2026-08-28) found several bugs that block a clean run if you follow the README/Makefile literally. This guide includes the fix for each one, inline, at the phase where it first matters. They're also summarized here so you can patch everything up front if you prefer:

| # | Bug | Blocks | Fixed in |
|---|---|---|---|
| 1 | `providers.tf` duplicates `variable`/`provider` blocks already in `variables.tf`/`versions.tf` | `terraform init` | Phase 2 |
| 2 | `terraform.tfvars.example` uses stale variable names, missing 8 of 13 required vars | `terraform apply` | Phase 1 |
| 3 | `ansible.cfg` has no `roles_path`; roles live outside Ansible's default search path | every playbook | Phase 5 |
| 4 | `community.general` collection used but never declared as a dependency | bootstrap & k8s-prereqs playbooks | Phase 6 |
| 5 | Over-escaped regex in the swap-disable task destroys the original `/etc/fstab` line instead of commenting it out | data integrity on every host | Phase 6 |

Everything else in the repo (YAML, remaining HCL, shell scripts, inventory, join-token logic) checked out clean in static testing.

---

## Phase 0 — Local tooling & OpenStack credential verification

**Goal:** confirm your workstation and OpenStack account can actually do what the rest of this guide assumes, before touching Terraform.

### 0.1 Install local tooling

```bash
terraform version      # >= 1.9.0 (required_version in versions.tf)
ansible --version       # ansible-core, plus community.general (see Phase 6)
openstack --version
kubectl version --client
helm version
```

### 0.2 Configure OpenStack auth

Use a `clouds.yaml` (preferred) or `OS_*` environment variables. **Never** put credentials in a committed `terraform.tfvars` — the repo's `.gitignore` already excludes `*.tfvars`.

```bash
export OS_CLOUD=mycloud   # if using clouds.yaml
# or source an OpenRC file:
# source openrc.sh
```

### 0.3 Verify credentials actually work

```bash
# Depending on the OpenStack cloud.yaml files you downloaded from Sebowa 
openstack token issue

# Export the variables into your shell environment
# export OS_TOKEN=<id>
# export OS_AUTH_URL=<auth_url>
# export OS_PROJECT_ID=<project_id>

openstack quota show --compute

```

**Expected:** a valid token response and quota table. If this fails, nothing downstream will work — stop here and fix auth first.

#### Or better yet, add the temporary token=<id> to clouds.yaml

Comment out or remove username, project_name and user_domain_name, and make sure to add project_domain_name and auth_type.

```yaml
clouds:
  openstack:
    auth:
      auth_url: <url>
      token: <id>
      #username: "nlisa"
      project_id: <id>
      # project_name: "QC Simulator"
      # user_domain_name: "Default"
      project_domain_name: "Default"
    region_name: "RegionOne"
    interface: "public"
    identity_api_version: 3
    auth_type: v3token

```

### 0.4 Verify every resource the Terraform code references by name actually exists

The Terraform in this repo **does not create** an image, a keypair, or the external network — it only references them by name/ID. If any of these are missing, `terraform apply` will fail partway through (after some resources are already created).

```bash
# You may need to explicity 
export OS_CLIENT_CONFIG_FILE="$HOME/.config/openstack/clouds.yaml"
openstack --os-cloud infra-hpc-qc-debug server list

# External/public network (var.external_network_name)
openstack network list --external

# A Rocky Linux 9 image — the Ansible roles use `dnf`, so the image must be
# RHEL-family. docs/versions.md and docs/slurm.md both assume Rocky 9.
openstack image list | grep -i rocky

# SSH keypair matching what you'll set as ssh_key_name — create one if needed
openstack keypair list

# Optionally create the keypair if it doesn't yet exist, using an existing local ssh key
# openstack keypair create --public-key ~/.ssh/id_ed25519_csir.pub nyameko-admin

# Flavors — you need one flavor that exposes EXACTLY 64 vCPUs.
# The slurm_compute Ansible role hard-asserts `nproc == 64` and will fail
# the whole playbook run on that host if the flavor doesn't match exactly.
# optionall -c RAM -c DISK
openstack flavor list -c Name -c VCPUs
```

**Testing checklist for Phase 0:**
- [ ] `openstack token issue` succeeds
- [ ] External network exists and its name is noted
- [ ] A Rocky 9 (or equivalent dnf-based) image exists and its ID is noted
- [ ] An SSH keypair exists in OpenStack (not just locally) and its name is noted
- [ ] A flavor with **exactly** 64 vCPUs exists for the two Slurm compute nodes
- [ ] You have enough quota for 13 instances + 1 Api_Lb load balancer + 2 networks + 1 router + 1 floating IP

TODO: Verify NUMA domain and CPU topology and pinning options for 64 VCPU Virtual Compute Nodes
```bash
hw:cpu_policy=dedicated
hw:numa_nodes
hw:numa_cpus.N
hw:num_mem.N
```
Not too worried about other nodes which can have shared CPU policy

Not permitted to check hypersisor config
```bash
$ openstack hypervisor list
```
---

## Phase 1 — Repository preparation & tfvars

```bash
git clone https://github.com/nyameko/infra-hpc-qc-k8s.git
cd infra-hpc-qc-k8s
```

### 1.1 Build a *correct* `terraform.tfvars`

⚠️ Do not blindly copy `terraform/environments/template/terraform.tfvars` — as shipped! Make sure to edit accordingly.

```bash
cp terraform/environments/template/ terraform/environments/private/

cat > terraform/environments/private/terraform.tfvars <<'EOF'
openstack_cloud          = "mycloud"
openstack_region         = "RegionOne"
external_network_name    = "public"              # from Phase 0.4
image_id                 = "REPLACE-WITH-ROCKY9-IMAGE-ID"
ssh_key_name             = "nyameko-admin"        # from Phase 0.4
bootstrap_ssh_cidr       = "YOUR.PUBLIC.IP.ADDR/32"

edge_flavor              = "REPLACE-ME"
hermes_flavor            = "REPLACE-ME"
slurm_controller_flavor  = "REPLACE-ME"
login_flavor             = "REPLACE-ME"
compute_12c_flavor       = "REPLACE-ME"           # must expose exactly 64 vCPUs
k8s_control_plane_flavo  = "REPLACE-ME"
k8s_worker_flavor        = "REPLACE-ME"
EOF
```

**Testing:** confirm the file has exactly the 13 keys `variables.tf` declares, no more, no less:

```bash
grep -oE '^variable "[a-z_0-9]+"' terraform/environments/private/variables.tf | wc -l   # should print 11
grep -c "^variable" terraform/environments/private/providers.tf                          # should print 2 (before Phase 2 fix)
grep -oE '^[a-z_0-9]+' terraform/environments/private/terraform.tfvars | wc -l           # should print 13
```
(11 in `variables.tf` + 2 in `providers.tf` = 13 required, matching Phase 2's fix.)

---

## Phase 2 — `terraform init`

### 2.1 Apply the required pre-flight patch

As committed, `providers.tf` redeclares `variable "openstack_cloud"`, `variable "openstack_region"`, and `provider "openstack"` — all three already exist in `variables.tf` / `versions.tf`. Terraform refuses to load a module with duplicate block names, so `init` fails immediately without this fix:

```bash
rm terraform/environments/private/providers.tf
```

### 2.2 Run init

```bash
make init
# equivalent to: terraform -chdir=terraform/environments/private init
```

**Testing:**
```bash
terraform -chdir=terraform/environments/private validate
```
**Expected:** `Success! The configuration is valid.` If you see `Duplicate provider configuration` or `Duplicate variable declaration`, Phase 2.1 wasn't applied (or wasn't applied to the right file).

---

## Phase 3 — `terraform plan`

```bash
make plan
```

**Testing — verify the plan matches the documented topology before applying anything:**

```bash
terraform -chdir=terraform/environments/private plan -out=tfplan
terraform -chdir=terraform/environments/private show -json tfplan | \
  jq -r '.resource_changes[] | select(.type=="openstack_compute_instance_v2") | .change.after.name' | sort
```
**Expected output — exactly these 13 names:**
```
edge
hermes-orchestrator-01
k8s-cp-01
k8s-cp-02
k8s-cp-03
k8s-worker-01
k8s-worker-02
k8s-worker-03
login1
login2
slurm-controller-01
slurm-cpu-01
slurm-cpu-02
```

Also confirm the load balancer and floating IP are planned:
```bash
terraform -chdir=terraform/environments/private show -json tfplan | \
  jq -r '.resource_changes[] | select(.type=="openstack_lb_loadbalancer_v2" or .type=="openstack_networking_floatingip_v2") | .type'
```
**Expected:** both `openstack_lb_loadbalancer_v2` and `openstack_networking_floatingip_v2` appear.

**Note the known no-op logic bug (non-blocking, informational):** `terraform/modules/security/main.tf`'s `internal_all` rule has a ternary — `each.value == "edge" ? var.mgmt_cidr : var.mgmt_cidr` — that evaluates to the same CIDR either way. This doesn't break `plan`/`apply`, but if you expected per-group CIDR scoping on that rule, it isn't happening. Safe to proceed; just don't assume that rule is differentiated by group.

---

## Phase 4 — `terraform apply` & infrastructure verification

```bash
make apply
```

**Testing — confirm the infrastructure actually came up:**

```bash
# 1. Resource count
terraform -chdir=terraform/environments/private state list | grep openstack_compute_instance_v2 | wc -l
# Expected: 13

# 2. Outputs
terraform -chdir=terraform/environments/private output
# Expected: edge_floating_ip, k8s_api_vip (10.51.0.100), node_ips (map of all 13 fixed IPs)

# 3. Reachability — the repo ships a script for exactly this
chmod +x scripts/check_initial_hosts.sh
./scripts/check_initial_hosts.sh
```
**Expected:** `SSH-OPEN` for all 13 addresses. Note this script checks the *management-network* fixed IPs directly — it assumes you're running it from somewhere with L3 reachability to `10.50.0.0/24` / `10.51.0.0/24` (e.g., already on the OpenStack tenant network, or via an existing VPN/jump host). If you're running it from the open internet, only `edge`'s floating IP will be reachable at this stage — that's expected, since WireGuard (the intended path into `10.50.0.0/24`) isn't configured until Phase 7.

```bash
# 4. Confirm the K8s API load balancer VIP is what was requested
terraform -chdir=terraform/environments/private output k8s_api_vip
# Expected: 10.51.0.100
```

---

## Phase 5 — Ansible connectivity check

Once the infrastructure has been provisioned by Terraform, connect to the edge node using SSH. First verify your SSH Configurations for connectivity to the cluster:
```bash
Host edge
    HostName <YOUR PUBLIC IP>
    User <your-image-user>
    IdentityFile ~/.ssh/id25591_admin
    IdentitiesOnly yes

Host 10.51.0.*
    User <your-image-user>
    IdentityFile ~/.ssh/id25591_admin
    IdentitiesOnly yes
    ProxyJump edge

Host 10.50.0.*
    User <your-image-user>
    IdentityFile ~/.ssh/id25591_admin
    IdentitiesOnly yes
    ProxyJump edge

```

### 5.1 Apply the required pre-flight patch

As committed, roles live in `ansible/roles/` but playbooks live in `ansible/playbooks/`, and `ansible.cfg` has no `roles_path`. Ansible's default search path is `<playbook_dir>/roles`, which doesn't exist here — **every playbook fails with `role not found`** without this fix:

```bash
cd ansible
cat >> ansible.cfg <<'EOF'
roles_path = roles
EOF
```

### 5.2 Confirm your SSH bootstrap key matches what the VMs expect

The `cloud-init-edge.yaml` / `cloud-init-node.yaml` files contain a placeholder `REPLACE_WITH_BOOTSTRAP_PUBLIC_KEY` — **but note these cloud-init files are not actually wired into any Terraform resource** (`user_data` is never populated in `environments/private/main.tf`'s node definitions). If you haven't separately arranged for the `ansible` user and its authorized key to exist on each VM (via the image itself, a manually-applied cloud-init, or the `key_pair`/`image_id` you chose in Phase 0), Ansible connectivity in this step will fail. Confirm your base image already provisions an `ansible` user, or adapt `main.tf` to pass `user_data` before proceeding.

### 5.3 Test connectivity

```bash
make ansible-ping
# equivalent to: ansible all -i inventories/private/hosts.yml -m ping
```
**Expected:** `SUCCESS` (pong) from all 13 hosts.

### 5.4 Syntax-check every playbook before running anything destructive

```bash
for pb in playbooks/*.yml; do
  ansible-playbook -i inventories/private/hosts.yml "$pb" --syntax-check
done
```
**Expected:** all pass (aside from the collection error fixed in Phase 6 — `bootstrap.yml` and `kubernetes-prereqs.yml` will still fail syntax-check until then).

---

## Phase 6 — Base OS bootstrap (`common`, `ssh`, `wazuh_agent`)

### 6.1 Install the missing collection dependency

`common` uses `community.general.timezone` and `kubernetes_prereqs` (Phase 10) uses `community.general.modprobe`. No `requirements.yml` exists in the repo to declare this — add one:

```bash
cat > requirements.yml <<'EOF'
---
collections:
  - name: community.general
EOF
ansible-galaxy collection install -r requirements.yml
```

### 6.2 Fix the swap-disable data-corruption bug

In `roles/common/tasks/main.yml`, the `Remove persistent swap entries` task is over-escaped:

```yaml
# as committed — BROKEN: replaces the whole matched fstab line with the
# literal text "# \1", destroying the original entry instead of
# commenting it out with its content preserved
- name: Remove persistent swap entries
  ansible.builtin.replace:
    path: /etc/fstab
    regexp: '^([^#].*\sswap\s+.*)$'
    replace: '# \\\\1'
```

Fix:
```bash
sed -i "s/replace: '# \\\\\\\\1'/replace: '# \\\\1'/" roles/common/tasks/main.yml
grep -n "replace:" roles/common/tasks/main.yml   # confirm it now reads:  replace: '# \1'
```

### 6.3 Run bootstrap

```bash
make bootstrap
```

**Testing:**
```bash
# Re-run with --check to confirm idempotency (second run should show 0 changes)
ansible-playbook -i inventories/private/hosts.yml playbooks/bootstrap.yml --check --diff

# Spot-check the fstab fix actually preserved swap lines correctly on one host
ansible all -i inventories/private/hosts.yml -m command -a "grep -i swap /etc/fstab" -b
# Expected: swap lines now start with '# ' followed by the ORIGINAL entry —
# not the literal string "\1".

# Confirm timezone applied
ansible all -i inventories/private/hosts.yml -m command -a "timedatectl show -p Timezone --value"
# Expected: Africa/Johannesburg (from ansible/group_vars/all.yml)
```

TODO: Document addition of sudo user after bootstrap
i.e. in `ansible/inventories/private/group_vars/all.yml` add
```yaml
admin_user_name: nyameko
admin_user_shell: /bin/bash
admin_ssh_public_key: "ssh-ed25519 AAAA..."
```


---

## Phase 7 — Edge node configuration

```bash
make edge
```
Applies `edge`, `wireguard`, `pihole`, `suricata` to `edge` only.

**Known limitations to test for, not against:** these roles are intentionally partial in this snapshot —
- `wireguard` only creates `/etc/wireguard` and drops a **static example** file (`wg0.conf.example`); it never renders the role's own `wg0.conf.j2` template, so no live WireGuard interface comes up from this alone.
- `pihole` only writes a documentation stub to `/etc/nyameko-pihole.md`; Pi-hole itself is not installed.
- `suricata` is installed but **deliberately left stopped** (self-documented in the task name).

**Testing:**
```bash
ansible edge -i inventories/private/hosts.yml -m command -a "systemctl is-enabled nftables" -b
# Expected: enabled

ansible edge -i inventories/private/hosts.yml -m command -a "rpm -q suricata" -b
# Expected: package present

ansible edge -i inventories/private/hosts.yml -m command -a "systemctl is-active suricata" -b
# Expected: inactive (intentional — do not treat this as a failure)
```
If you need a working WireGuard tunnel at this stage (recall Phase 4's reachability test depends on it for anything beyond `edge`), you'll need to either hand-roll `wg0.conf` from the existing template/variables or extend the role — this repo doesn't do it yet.

---

## Phase 8 — Hermes orchestrator configuration

```bash
make hermes
```
Applies `hermes_orchestrator` to `hermes-orchestrator-01` only — installs dependencies, creates the `hermes` system user/directories, and drops the federation security policy doc.

**Testing:**
```bash
ansible hermes_orchestrator -i inventories/private/hosts.yml -m command -a "id hermes" -b
# Expected: uid/gid for 'hermes' exists, home dir present

ansible hermes_orchestrator -i inventories/private/hosts.yml -m command -a "cat /opt/hermes/SECURITY.md" -b
# Expected: read-only-by-default policy text
```
This role only lays down the host scaffold — it does not install or start any actual Hermes agent binary/service (none exists in this repo yet).

---

## Phase 9 — Slurm cluster configuration

```bash
make slurm
```
Runs `slurm_controller` → `slurm_login` → `slurm_compute` against their respective inventory groups.

⚠️ **This step will hard-fail on the compute nodes if you didn't get flavor sizing exactly right in Phase 0/1** — `slurm_compute`'s `Verify 64-core provisioning` task asserts `nproc == 64` and aborts the play on any host where that's false.

**Testing:**
```bash
# Confirm the assertion actually passed (not just that the play didn't error elsewhere)
ansible slurm_compute -i inventories/private/hosts.yml -m command -a "nproc" -b
# Expected: 64 on both slurm-cpu-01 and slurm-cpu-02

ansible slurm_controller -i inventories/private/hosts.yml -m command -a "systemctl is-enabled mariadb" -b
# Expected: enabled

ansible slurm_controller -i inventories/private/hosts.yml -m command -a "cat /etc/slurm/slurm.conf" -b
# Expected: rendered slurm.conf with ClusterName=nyameko, both compute nodes listed with CPUs=64

ansible slurm_login -i inventories/private/hosts.yml -m command -a "cat /etc/slurm/login-node" -b
# Expected: marker file present
```
Note: this phase intentionally stops short of installing/enabling `slurmctld`/`slurmdbd`/`slurmd` daemons themselves — the controller role ends on a `debug` message noting the pinned Slurm/OpenHPC build still needs to be selected per `docs/versions.md`. Don't expect `squeue`/`sinfo` to work yet after this phase.

---

## Phase 10 — Kubernetes prerequisites

```bash
make k8s-prereqs
```
Runs `containerd` + `kubernetes_prereqs` against `control_plane` and `workers` groups. (Requires the `community.general` fix from Phase 6.1 — this is the second of the two playbooks that needs it.)

**Testing:**
```bash
ansible control_plane:workers -i inventories/private/hosts.yml -m command -a "systemctl is-active containerd" -b
# Expected: active

ansible control_plane:workers -i inventories/private/hosts.yml -m command -a "grep SystemdCgroup /etc/containerd/config.toml" -b
# Expected: SystemdCgroup = true

ansible control_plane:workers -i inventories/private/hosts.yml -m shell -a "lsmod | grep -E 'overlay|br_netfilter'" -b
# Expected: both modules loaded

ansible control_plane:workers -i inventories/private/hosts.yml -m command -a "sysctl net.ipv4.ip_forward" -b
# Expected: net.ipv4.ip_forward = 1

ansible control_plane:workers -i inventories/private/hosts.yml -m command -a "rpm -q kubelet kubeadm kubectl" -b
# Expected: all three packages present
```

---

## Phase 11 — Kubernetes cluster bootstrap

### 11.1 Set the exact Kubernetes patch version first

`group_vars/all.yml` ships `kubernetes_exact_version: "REPLACE_WITH_EXACT_1.36.x"` as a deliberate placeholder — `docs/versions.md` explicitly says to pick the current supported 1.36.x patch immediately before deployment rather than hard-coding an old one. Look up the current patch and set it:

```bash
$EDITOR group_vars/all.yml   # set kubernetes_exact_version, e.g. "1.36.2"
```

### 11.2 Run the bootstrap

```bash
make k8s-init
```
This runs `kube_control_plane` on `control_plane[0]` (kubeadm init, upload-certs, generates short-lived join tokens held only in Ansible facts), then `kube_join_control_plane` on the remaining two control-plane nodes, then `kube_worker` on all three workers — all in a single playbook run so the 30-minute join-token TTL doesn't expire between steps.

**Testing:**
```bash
# From cp-01 (or copy its /home/ansible/.kube/config locally):
ansible control_plane[0] -i inventories/private/hosts.yml -m command -a "kubectl get nodes -o wide" -b --become-user=ansible

# Expected: all 6 nodes (3 control-plane + 3 workers) listed.
# Nodes will show STATUS = NotReady until a CNI is installed — see Phase 13, this is expected.

ansible control_plane -i inventories/private/hosts.yml -m command -a "systemctl is-active kubelet" -b
# Expected: active on all 3

# Confirm the API is reachable via the Api_Lb VIP from Phase 3/4, not just node-local
curl -sk https://10.51.0.100:6443/healthz
# Expected: "ok" (may need --cacert if you want a non-insecure check)
```

### 11.3 Re-joining a node later (separate from initial bootstrap)

If you need to add/rejoin a node after the fact (join tokens from 11.2 have long since expired), use the standalone playbook instead of re-running `k8s-init`:

```bash
ansible-playbook -i inventories/private/hosts.yml playbooks/join-cluster.yml
```

---

## Phase 12 — End-to-end cluster validation

Run this as a final smoke test once Phases 2–11 are complete.

```bash
# 1. All 13 hosts reachable and ping-responsive
make ansible-ping

# 2. All 6 K8s nodes registered
kubectl get nodes

# 3. K8s API VIP load-balancing across all 3 control planes (kill one CP's kubelet, confirm API stays reachable via VIP)
ansible k8s-cp-01 -i inventories/private/hosts.yml -m systemd -a "name=kubelet state=stopped" -b
curl -sk https://10.51.0.100:6443/healthz   # should still succeed via cp-02/cp-03
ansible k8s-cp-01 -i inventories/private/hosts.yml -m systemd -a "name=kubelet state=started" -b

# 4. Slurm compute nodes report correct CPU count
ansible slurm_compute -i inventories/private/hosts.yml -m command -a "nproc" -b

# 5. No secrets were committed anywhere along the way
git -C . log --all -p | grep -iE "BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|password\s*=|api[_-]?key\s*="
# Expected: no output
```

---

## Phase 13 — Not yet implemented in this repo (informational only)

The README's deployment order lists these as steps 4–7, but as of this snapshot **none of them have corresponding Terraform/Ansible code yet** — don't expect a `make` target:

- Cilium CNI (this is why `kubectl get nodes` shows `NotReady` at the end of Phase 11)
- OpenStack Cloud Controller Manager + Cinder/shared-storage CSI
- Argo CD
- Platform services: ingress, cert-manager, Prometheus/Grafana/Loki, Wazuh **manager** (only the agent side is configured — no role in this repo stands up a Wazuh manager, despite `wazuh_manager_address` in `group_vars/all.yml` pointing at `slurm-controller-01`), JupyterHub, Ollama, llama.cpp
- Research Hermes deployed inside Kubernetes (`hermes-orchestrator-01` from Phase 8 is the private/federation Hermes only)

Treat everything through Phase 12 as validated by this guide; treat Phase 13 as a roadmap, not something you can test yet.
