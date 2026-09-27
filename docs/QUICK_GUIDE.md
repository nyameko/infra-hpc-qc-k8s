# Quick Guide

Command-first reference for the current platform.

## 1. OpenStack / Terraform

```bash
cd terraform/environments/private
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

Terraform owns OpenStack resources: networks, routers, ports, security groups, VMs, Cinder volumes and cloud-side network policy.

Current local resolver contract:

```text
management subnet DNS  → <EDGE_IP>
Kubernetes subnet DNS  → <EDGE_IP>
```

Pi-hole runs on `edge`.

## 2. Ansible

```bash
cd ansible
ansible-inventory -i inventories/private/hosts.yml --graph
ansible all -i inventories/private/hosts.yml -m ping
```

Typical host playbooks:

```bash
ansible-playbook -i inventories/private/hosts.yml playbooks/bootstrap.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/edge.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/api-lb.yml
```

Ansible owns host configuration and infrastructure services.

## 3. Kubernetes

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes.yml

kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw='/readyz?verbose'
```

## 4. Cilium

```bash
cilium status --wait
cilium connectivity test --debug
```

Advanced Hubble, kube-proxy replacement, ClusterMesh and deeper policy work remain deliberate follow-on exercises.

## 5. Argo CD

```bash
kubectl -n argocd get applications
```

Typical application path:

```text
argocd/applications/<app>.yml
        ↓
Argo CD
        ↓
Helm / repository resources
        ↓
Kubernetes
```

## 6. Prometheus / Grafana

```bash
kubectl -n monitoring get pods
kubectl -n argocd get applications
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

Query Prometheus directly:

```bash
kubectl -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=up'
```

Do not manually import Git-managed dashboards into Grafana.

## 7. Pi-hole / DNS

From a management VM:

```bash
cat /etc/resolv.conf
resolvectl status || true
getent hosts edge
getent hosts slurm-controller-01
```

Expected resolver:

```text
nameserver <EDGE_IP>
```

OpenStack may still add search suffixes such as `openstacklocal` or `novalocal`; that is separate from the resolver choice.

Kubernetes pods should use:

```text
pod → CoreDNS → Pi-hole → upstream
```

WireGuard clients should use `<VPN_GATEWAY_IP>` as DNS where supported.

## 8. Research storage

Storage server:

```text
storage-nfs-01  <STORAGE_IP>
```

Exports/mounts:

```text
/srv/home      → /home/research
/srv/datasets  → /datasets
/srv/staging   → /staging
```

Validate a login or compute node:

```bash
findmnt /home/research
findmnt /datasets
findmnt /staging
```

Validate the storage host:

```bash
findmnt /srv/home /srv/datasets /srv/staging
exportfs -v
```

See `docs/tutorials/m1-storage-nfs-xfs.md`.

## 9. Slurm RPM build

From `ansible/`:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/slurm-build-rpms.yml
```

M1 uses Slurm `25.11.8` built from checksum-pinned official SchedMD source.

## 10. Slurm deploy

Vaulted private variables must include the shared MUNGE key and Slurm accounting database password.

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/slurm.yml \
  --ask-vault-pass \
  -e @inventories/private/slurm-secrets.vault.yml
```

Canonical service identities:

```text
slurm  5000:5000
munge  5001:5001
```

Interactive callback range:

```text
SrunPortRange=60001-61000
```

The intended interactive path is:

```text
login1/login2
      ↓
   Slurm
      ↓
compute nodes
```

The controller is not intended as a normal user execution/login tier.

## 11. Slurm health and acceptance

From a login node:

```bash
scontrol ping
sinfo -N -l
squeue -a
scontrol show nodes
sacctmgr -nP show cluster format=Cluster
```

Expected M1 partitions:

```text
cpu-small  slurm-cpu-01,02  12 vCPU each
cpu-large  slurm-cpu-03,04  64 vCPU each
```

Small smoke test:

```bash
srun \
  --partition=cpu-small \
  --nodes=1 \
  --ntasks=1 \
  --time=00:01:00 \
  /usr/bin/hostname
```

Large smoke test:

```bash
srun \
  --partition=cpu-large \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=32 \
  --mem=128G \
  --time=00:01:00 \
  bash -lc 'hostname; nproc; free -h'
```

A healthy acceptance run returns task output and leaves nodes back in `IDLE`.

If allocation succeeds but task launch hangs, inspect fresh compute logs:

```bash
journalctl -u slurmd --since "-2 minutes" --no-pager
```

Useful failure signatures:

```text
Unexpected uid (...) != Slurm uid (...)
  → inconsistent numeric Slurm service identity

connect io: Connection timed out
Slurmd could not connect IO
  → compute node cannot reach the srun host callback port
```

See `docs/tutorials/slurm-service-identity-recovery.md` for UID/GID recovery.

## 12. Node Exporter / Slurm host observability

Validate locally:

```bash
systemctl is-active node_exporter
curl -fsS http://127.0.0.1:9100/metrics >/dev/null && echo OK
```

The Prometheus `slurm-hosts` job should scrape controller, login and compute nodes. Validate the live Prometheus targets rather than assuming a systemd-active exporter is reachable.

## 13. Edge health

```bash
sudo nft list ruleset
sudo wg show
systemctl is-active wazuh-manager
sudo ss -lntup
```

## 14. Wazuh & Suricata

For full deployment and evidence validation, follow:

- `docs/tutorials/wazuh-suricata-deployment.md`
- `docs/tutorials/wazuh-suricata-operational-drills.md`

Useful commands:

```bash
ansible-playbook -i inventories/private/hosts.yml playbooks/wazuh-agents.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/edge.yml --limit edge_nodes --tags suricata
```

Use fresh log windows when validating security after infrastructure changes; historical Slurm UID/MUNGE errors should not be mistaken for active incidents.

## 15. JupyterHub next

The next major execution path is:

```text
browser
  ↓
JupyterHub in Kubernetes
  ↓
Slurm allocation
  ↓
compute node
  ↓
jupyterhub-singleuser
  ↓
/home/research
```

Do not run user notebook compute directly in Kubernetes as a fallback.

## 16. Troubleshooting rule

Classify the failing layer before changing it:

```text
cloud
  ↓
security group / route / DNS
  ↓
VM / OS
  ↓
service identity / systemd / SELinux
  ↓
TCP / UDP / callback path
  ↓
scheduler / runtime
  ↓
Kubernetes / Cilium
  ↓
application
  ↓
observability
```

For Slurm specifically:

```text
allocation works but task does not
      ↓
check fresh slurmd/slurmstepd log
      ↓
auth/UID
      ↓
cgroup/task setup
      ↓
srun callback networking
      ↓
exec/user environment
```
