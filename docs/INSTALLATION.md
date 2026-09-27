# Installation and Operations Guide

A complete deployment and operational guide for `infra-hpc-qc-k8s`.

This document is deliberately more detailed than the root README. It explains what is being deployed, why each layer exists, validation gates, failure modes and the operational path from bootstrap to the research platform.

---

# 1. Build in layers

The platform is intentionally built in acceptance-gated layers:

```text
OpenStack
  ↓
Rocky Linux hosts
  ↓
Network / edge security
  ↓
Kubernetes API load-balancer
  ↓
Container runtime
  ↓
Kubernetes
  ↓
Cilium
  ↓
OpenStack CCM / Cinder CSI
  ↓
Argo CD
  ↓
Prometheus / Grafana
  ↓
Wazuh / Siccata
  ↓
Slurm
  ↓
Private ingress / DNS
  ↓
PostgreSQL
  ↓
JupyterHub
  ↓
Hermes / Heretic
  ↓
Astro
```

Every arrow is an acceptance gate. A successful command is not itself proof of system health.

# 2. Reference network topology

```text
Management: 10.50.0.0/24
Kubernetes: 10.51.0.0/24
WireGuard:  10.60.0.0/24
```

Current reference hosts:

```text
edge                 10.50.0.10
hermes host          10.50.0.11
slurm controller     10.50.0.12
login1               10.50.0.20
login2               10.50.0.21
slurm-cpu-01         10.50.0.30   12 vCPU / 24 GiB
slurm-cpu-02         10.50.0.31   12 vCPU / 24 GiB
slurm-cpu-03         10.50.0.32   64 vCPU / 256 GiB
slurm-cpu-04         10.50.0.33   64 vCPU / 256 GiB
storage-nfs-01       10.50.0.40
api-lb-01            10.51.0.100
k8s-cp-01            10.51.0.11
k8s-cp-02            10.51.0.12
k8s-cp-03            10.51.0.13
k8s-worker-01        10.51.0.21
k8s-worker-02        10.51.0.22
k8s-worker-03        10.51.0.23
```

The edge provides WireGuard, Pi-hole, nftables, Wazuh Manager and network-security telemetry. The Kubernetes API is fronted by HAProxy at `10.51.0.100:6443`.

Pi-hole at `10.50.0.10` is also the resolver advertised by Neutron DHCP to the management and Kubernetes subnets. This is intentionally an infrastructure service rather than a convenience-only ad blocker.

# 3. Security boundaries

OpenStack security groups and host firewalls are separate controls:

```text
OpenStack SG = what traffic may reach a VM?
nftables      = what traffic may the host accept/forward?
```

Kubernetes nodes do not have a host nftables/firewalld layer in this project unless explicitly added later. Do not apply edge firewall instructions to Kubernetes nodes.

Validate firewall configuration before loading it:

```bash
sudo nft -c -f /etc/nftables.conf
sudo nft list ruleset
```

Keep the recovery/console path available while changing host firewall policy.

# 4. Edge and WireGuard

WireGuard is the normal private administrative path:

```text
client 10.60.0.2
       ↓
edge 10.60.0.1
       ↓
10.50.0.0/24 + 10.51.0.0/24 + 10.60.0.0/24
```

Validate:

```bash
sudo wg show
ip addr show wg0
ip route
```

# 5. Pi-hole and DNS baseline

Pi-hole runs on the edge and is the current internal resolver for the local OpenStack fabric.

```text
management VM ─┐
Kubernetes node ├─→ Pi-hole 10.50.0.10 → upstream DNS
WireGuard client┘
```

Kubernetes pods should retain Kubernetes DNS semantics:

```text
pod → CoreDNS → node/upstream resolver → Pi-hole → upstream DNS
```

Do not point pods directly at Pi-hole and bypass CoreDNS service discovery.

Neutron subnet configuration advertises:

```text
10.50.0.10
```

as the DNS server for both local OpenStack subnets. Existing VMs may need a DHCP lease refresh before the new resolver appears.

Validate from a management VM:

```bash
cat /etc/resolv.conf
resolvectl status || true
getent hosts edge
getent hosts slurm-controller-01
```

A typical NetworkManager-generated resolver file may still contain OpenStack search domains such as:

```text
search openstacklocal novalocal
nameserver 10.50.0.10
```

That suffix behavior is separate from the resolver choice. The long-term internal naming taxonomy is tracked in issue #49.

WireGuard clients should use the edge's tunnel address as DNS:

```text
DNS = 10.60.0.1
```

where supported by the client manager. External A100/H200/third-party compute sites are not implicitly placed under this DNS authority.

# 6. HAProxy: Kubernetes API endpoint

The Kubernetes API has a stable endpoint:

```text
10.51.0.100:6443
```

Validate the HAProxy host:

```bash
ssh api-lb-01
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl is-active haproxy
sudo ss -lntp | grep 6443
```

HAProxy SELinux policy must be adjusted narrowly if required; do not disable SELinux globally.

# 7. Kubernetes bootstrap

Kubernetes consists of three control planes and three workers. kubeadm owns cluster formation; Cilium owns cluster networking.

Validate:

```bash
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
```

# 8. Cilium baseline

Cilium is intentionally deployed conservatively before advanced features are introduced.

Current baseline:

```text
CNI
VXLAN
service networking
network policy foundation
Prometheus metrics
```

Deferred exercises:

```text
Hubble
kube-proxy replacement
ClusterMesh
advanced eBPF routing
advanced policy design
```

Validate:

```bash
cilium status --wait
cilium connectivity test --debug
```

The validated baseline has passed the current connectivity suite. Treat skipped tests separately from failures and understand why they were skipped.

# 9. Persistent storage: Kubernetes and HPC

Kubernetes persistent storage uses OpenStack Cinder through Cinder CSI:

```text
PVC
 ↓
StorageClass
 ↓
Cinder CSI
 ↓
OpenStack Cinder volume
 ↓
PV
 ↓
Pod
```

The persistence test must survive Pod recreation.

The HPC/research plane is separate. M1 uses `storage-nfs-01` as a dedicated NFSv4 gateway over three Cinder SSD-backed XFS filesystems:

```text
/srv/home      512 GiB → /home/research
/srv/datasets    2 TiB → /datasets
/srv/staging   512 GiB → /staging
```

Quota policy:

```text
home      user accounting/enforcement
datasets  project accounting/enforcement
staging   user + project accounting/enforcement
```

The storage VM owns each Cinder block attachment. Login and compute hosts mount the NFS exports; they do not attach the same block device directly.

Validate on storage:

```bash
findmnt /srv/home /srv/datasets /srv/staging
xfs_quota -x -c 'state' /srv/home
xfs_quota -x -c 'state' /srv/datasets
xfs_quota -x -c 'state' /srv/staging
exportfs -v
```

Validate on login/compute nodes:

```bash
findmnt /home/research
findmnt /datasets
findmnt /staging
```

Slurm treats shared `/home/research` as a prerequisite. Scratch remains node-local and ephemeral.

See [tutorials/m1-storage-nfs-xfs.md](tutorials/m1-storage-nfs-xfs.md) for the full storage deployment and acceptance path.

# 10. Argo CD GitOps

Argo CD owns long-lived Kubernetes applications.

The canonical pattern is:

```text
argocd/applications/<app>.yml
          │
          ├── upstream Helm chart / vendor source
          ├── argocd/resources/<app>
          └── encrypted / sealed secrets
```

Use a flat child-Application directory where practical. Do not turn Ansible into a long-lived Kubernetes application installer.

Check application state with:

```bash
kubectl -n argocd get applications
```

Remember:

```text
Synced  = Git desired state applied
Healthy = resulting Kubernetes resources healthy
```

# 11. Prometheus and Grafana

Prometheus and Grafana are platform infrastructure because every later layer depends on operational visibility.

The current Prometheus application uses the prometheus-community Helm chart and repository-owned values. One important lesson from the deployment was that `extraScrapeConfigs` is a top-level chart value; placing it under `server` produced valid-looking YAML but did not render the scrape job.

The working HAProxy job is conceptually:

```yaml
extraScrapeConfigs: |
  - job_name: haproxy
    static_configs:
      - targets:
          - 10.51.0.100:8404
```

Validate the running configuration rather than trusting Git alone:

```bash
kubectl -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- http://127.0.0.1:9090/api/v1/status/config
```

And query actual targets directly.

## 11.1 Grafana GitOps dashboards

Dashboards live in:

```text
argocd/resources/grafana/dashboards/
```

The `grafana-dashboards` Argo Application deploys the ConfigMaps, which carry:

```text
grafana_dashboard=1
```

The Grafana sidecar consumes those ConfigMaps and provisions the dashboards.

Validate:

```bash
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

Do not manually import or maintain Git-managed dashboards in the Grafana UI.

## 11.2 Discovery jobs matter

Prometheus job names come from the scrape configuration, not from the product name.

Examples validated in this platform:

```text
HAProxy       → job="haproxy"
Cilium agent  → job="kubernetes-pods"
Cilium Envoy  → job="kubernetes-service-endpoints"
```

Therefore dashboard selectors must follow the live labels.

## 11.3 HAProxy dashboard validation

HAProxy exports server health as:

```promql
haproxy_server_status{state="UP"}
```

Backend aggregate health is available as:

```promql
haproxy_backend_agg_server_status{state="UP"}
```

Use the aggregate metric for a total server count and the per-server metric only when individual server dimensions are useful.

The current operational dashboard does not need an elaborate individual-backend-health chart if the aggregate availability and backend/frontend traffic panels are clearer.

# 12. Temporary GUI access

During bring-up, temporary access may use:

```text
kubectl port-forward
SSH local forwarding
```

This is a bootstrap technique, not the desired long-term architecture.

The final path will be:

```text
Cloudflare DNS / ACME
        ↓
Pi-hole private DNS where applicable
        ↓
HAProxy
        ↓
Traefik
        ↓
Kubernetes Service
```

Once this path is validated, remove normal-use GUI port-forwards and SSH tunnels.

# 13. Wazuh security plane

The existing edge Wazuh Manager is the security-plane anchor.

Current Manager state is intended to remain outside Kubernetes:

```text
edge
 └── Wazuh Manager
```

Kubernetes will add:

```text
Wazuh Indexer
Wazuh Dashboard
```

The Manager remains authoritative for agent communication and security event processing. The Indexer provides search/storage and the Dashboard provides Wazuh-native security analysis.

## 13.1 Wazuh agent networks

The current and future external compute nodes include additional Wazuh agents. The required manager ports are conceptually:

```text
1514/TCP  agent communication
1515/TCP  enrollment
55000/TCP Wazuh API / API-based enrollment
```

`1516/TCP` is a Wazuh Manager cluster port and is **not** required for ordinary agents. Keep it closed until a second Manager is intentionally introduced.

Open ports only from the networks that actually need them, in both OpenStack security groups and the edge nftables policy.

Future A100/H200 environments should join the same Manager via explicitly permitted network paths rather than introducing a second security architecture.

## 13.2 Security observability boundaries

```text
Wazuh
  → security events / host security / investigation

Siccata
  → IDS/IPS network events

Prometheus/Grafana
  → operational metrics / platform health / security telemetry
```

Grafana supplements, rather than replaces, the Wazuh Dashboard.

# 14. Slurm

Slurm remains outside Kubernetes and is authoritative for researcher compute scheduling.

## 14.1 Validated M1 topology

```text
slurm-controller-01
  ├── slurmctld
  ├── slurmdbd
  └── MariaDB / slurm_acct_db

login1 / login2
  └── supported user-facing submission tier

cpu-small
  ├── slurm-cpu-01  12 vCPU / RealMemory=23552 MiB
  └── slurm-cpu-02  12 vCPU / RealMemory=23552 MiB

cpu-large
  ├── slurm-cpu-03  64 vCPU / RealMemory=256192 MiB
  └── slurm-cpu-04  64 vCPU / RealMemory=256192 MiB
```

The controller is an infrastructure host. Normal researchers should submit through the login tier rather than logging into or launching interactive work from the controller.

## 14.2 Packages

M1 builds Slurm 25.11.8 from checksum-pinned official SchedMD source into Rocky Linux 9 RPMs:

```bash
cd ansible
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/slurm-build-rpms.yml
```

The same artifact set is staged to controller/login/compute nodes before role-specific packages are installed. Locally built M1 RPMs are unsigned but explicitly checksum-verified; issue #41 owns signed CI artifacts, SBOM/provenance and an internal Yum/DNF repository.

## 14.3 Secrets and accounting

Private Vault variables contain:

```yaml
slurm_munge_key_b64: "<base64 of the shared binary key>"
slurm_db_password: "<database password>"
```

Do not commit either secret.

Accounting topology:

```text
slurmctld → slurmdbd :6819 → MariaDB
```

The registered Slurm cluster is:

```text
quantum-cpu
```

## 14.4 Numeric service identities

The service accounts are pinned because Slurm/MUNGE authenticated RPCs carry numeric credentials:

```text
slurm  5000:5000
munge  5001:5001
```

A real M1 failure used the same account names but different numeric UIDs on the controller and compute nodes. That produced:

```text
cred/munge: Unexpected uid (...) != Slurm uid (...)
_verify_signature: failed decode
Malformed RPC
Header lengths are longer than data received
```

Do not diagnose old journal entries as current failures. Use fresh time windows after service restarts.

The one-time recovery path belongs in [tutorials/slurm-service-identity-recovery.md](tutorials/slurm-service-identity-recovery.md), not in normal deployment automation.

## 14.5 Interactive callback traffic

Interactive `srun` opens listening sockets on the machine where the client command runs. Compute-side `slurmstepd` must connect back to those sockets.

M1 constrains this with:

```text
SrunPortRange=60001-61000
```

Without a matching compute → login-node security-group rule, allocation succeeds but task launch fails with:

```text
connect io: Connection timed out
_fork_all_tasks: IO setup failed: Slurmd could not connect IO
```

The intended security boundary is:

```text
slurm-compute SG → TCP 60001-61000 → slurm-login SG
```

The controller does not need to remain a normal interactive `srun` endpoint after acceptance testing.

## 14.6 Deploy

From `ansible/`:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/slurm.yml \
  --ask-vault-pass \
  -e @inventories/private/slurm-secrets.vault.yml
```

The playbook validates package version, MUNGE material, shared home, declared CPU/memory resources, accounting and daemon health.

## 14.7 Validated execution

From `login1` or `login2`:

```bash
sinfo -N -l
squeue -a
scontrol show nodes
sacctmgr -nP show cluster format=Cluster
```

M1 has passed:

```bash
srun \
  --partition=cpu-small \
  --nodes=1 \
  --ntasks=1 \
  --time=00:01:00 \
  /usr/bin/hostname
```

with output from `slurm-cpu-01`, and:

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

with a 32-CPU allocation on `slurm-cpu-03`.

The next hardening gate is to formalize `sbatch`, `sacct`, cancellation, walltime, cgroup enforcement, two-node execution and MPI/PMIx acceptance. That work is tracked in issue #56.

See [tutorials/m1-slurm-cpu-fabric.md](tutorials/m1-slurm-cpu-fabric.md) for architecture/deployment detail and [tutorials/slurm-service-identity-recovery.md](tutorials/slurm-service-identity-recovery.md) for the incident-recovery sequence.

# 15. PostgreSQL

PostgreSQL is the platform/application data and identity store for services that need durable relational state.

It is not the authority for external provider credentials.

The first operational deployment should establish:

```text
PostgreSQL
  ↓
platform/user database
  ↓
JupyterHub / Hermes / application metadata
```

Backups and HA remain later hardening concerns.

# 16. JupyterHub

JupyterHub is the next major integration after M1 Slurm hardening.

The architectural rule is already fixed:

```text
browser
   ↓
JupyterHub in Kubernetes
   ↓
Slurm submission
   ↓
allocated compute node
   ↓
jupyterhub-singleuser
   ↓
shared /home/research
```

Kubernetes hosts the Hub/control service. User notebook servers and kernels must consume Slurm allocations; there is no silent Kubernetes fallback compute path.

Start with a deliberately small profile set, for example:

```text
development  → small cpu-small allocation
research     → larger bounded allocation
```

Before exposing additional profiles, prove:

- allocation and cancellation;
- wall-time expiry;
- CPU/memory cgroup limits;
- persistent shared home;
- Slurm accounting;
- notebook termination when the Slurm allocation ends.

Identity provisioning is not completed by manually creating research users. Quantum Platform will own the later approved-user → POSIX/storage/Slurm association flow.

# 17. Hermes / Heretic

Hermes is an orchestration layer, not an unrestricted administrator.

The architecture separates:

```text
federation / infrastructure Hermes
        ↓
research Hermes in Kubernetes
        ↓
explicit least-privilege capabilities
```

External chat interfaces such as Telegram and Discord are planned as **liaison interfaces** to Hermes. They are not direct privileged infrastructure channels.

The Hermes capability model distinguishes:

```text
read
propose
approve
apply
```

The default posture is read/report. Destructive or infrastructure-changing operations require explicit capability scope and human approval.

Heretic remains the controlled execution/research complement to Hermes.

# 18. Astro

Astro is the user/research portal and the first user-facing end-to-end application milestone.

The target application path is:

```text
DNS
 ↓
HAProxy
 ↓
Traefik
 ↓
Astro
 ↓
platform services / Hermes / APIs
```

# 19. DNS and Cloudflare

The private path should not require public exposure merely to resolve internal services.

Target model:

```text
Cloudflare
  → public DNS / ACME DNS-01

Pi-hole
  → private DNS overrides

HAProxy
  → private ingress VIP

Traefik
  → Kubernetes services
```

Cloudflare API credentials should be narrowly scoped and kept outside Git.

# 20. GPU/QPU accounting templates

Create schemas and dashboard interfaces early, but defer detailed accounting implementation until identity, Slurm and Hermes provide authoritative attribution.

Conceptual dimensions:

```text
user
project
job
resource
allocation
start/end time
runtime
consumption
```

GPU additions:

```text
GPU ID
GPU memory
GPU time
node
job
user
project
```

QPU additions:

```text
provider
backend
QPU time
shots
circuit executions
job
user
project
```

# 21. Final acceptance gates

## Infrastructure

```bash
openstack server list
openstack network list
openstack security group list
```

## Ansible

```bash
ansible-inventory -i inventories/private/hosts.yml --graph
ansible all -i inventories/private/hosts.yml -m ping
```

## Edge

```bash
sudo nft list ruleset
sudo wg show
systemctl is-active wazuh-manager
systemctl is-active haproxy
```

## Kubernetes

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw='/readyz?verbose'
```

## Cilium

```bash
cilium status --wait
cilium connectivity test --debug
```

## Storage

```bash
kubectl get storageclass
kubectl get csidrivers
```

## Prometheus/Grafana

```bash
kubectl -n argocd get applications
kubectl -n monitoring get pods
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

## Slurm

```bash
sinfo
squeue
scontrol show nodes
```

# 22. Troubleshooting method

Diagnose from the outside in:

```text
Cloud
  ↓
OpenStack SG / port / route
  ↓
VM / OS
  ↓
firewall / SELinux / systemd
  ↓
TCP / UDP / socket
  ↓
container runtime / CRI
  ↓
Kubernetes
  ↓
Cilium
  ↓
service
  ↓
application
  ↓
Prometheus metric
  ↓
Grafana query
```

The project deliberately preserves real incidents as teaching material. Examples include OpenStack security-group scoping, HAProxy SELinux policy, package provenance, CRI permissions, Cinder secret/config mismatches and dashboard queries that did not match the live metric schema.

# 23. Production hardening still required

Before treating the platform as a production multi-user research service, review:

- HA for single-instance services
- backup/restore tests
- credential rotation
- stronger secret management where justified
- certificate and key rotation
- Cilium policy defaults
- ingress/TLS hardening
- PostgreSQL backups/HA
- Cinder backup strategy
- Wazuh sizing and retention
- Prometheus/Grafana retention and persistence
- Slurm controller/database HA
- public DNS/Cloudflare policy
- disaster recovery
- account lifecycle and RBAC


# 24. Wazuh & Suricata — completed reference security sprint

The detailed, replayable sequence lives in [Wazuh & Suricata deployment](tutorials/wazuh-suricata-deployment.md); [operational drills](tutorials/wazuh-suricata-operational-drills.md) covers common failures and an evidence template. Read these alongside sections 3, 10, 11 and 13 above. The security path is **edge Wazuh Manager → alerts.json → staged and then TLS-enabled Filebeat → private Cinder-backed Wazuh Indexer → private Dashboard**; edge Suricata 8 emits EVE JSON into that Manager, not directly into Grafana.

At the 23 September 2026 acceptance checkpoint the Manager reported 14 Active identities (including its local identity); the benign Suricata SID 9900001 was correlated to Wazuh rule 86601 and a searchable alert in `wazuh-alerts-4.x-2026.09.23`. This is historical verification, not a current cluster-health or backup claim. Indexer availability, authentication, durable retention and restore must be checked individually. The `wazuh` Argo Application currently targets `main`; merging the tutorial into `dev` does not reconfigure that live application. Keep edge nftables separate from non-edge OpenStack security-group enforcement.
