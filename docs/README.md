# infra-hpc-qc-k8s — Documentation

> Infrastructure-as-code for a hybrid **HPC + Kubernetes + AI/ML + quantum-computing** platform.
>
> The documentation is intentionally layered: **README → QUICK GUIDE → INSTALLATION → TUTORIALS**.

## Documentation map

| Document | Purpose | Style |
|---|---|---|
| [QUICK_GUIDE.md](QUICK_GUIDE.md) | Get from an empty OpenStack project to a functioning platform | Commands first; minimal prose |
| [INSTALLATION.md](INSTALLATION.md) | Follow the complete deployment, understand every decision, and troubleshoot failures | Hand-holding; explanations; warnings; comparisons; validation |
| [tutorials/](tutorials/) | Learn the engineering concepts behind the deployment | Deep dives; experiments; incident-driven teaching |

The three root documents answer three different questions:

```text
README.md
   ↓
   What is this? How is it designed? Where do I go next?

QUICK_GUIDE.md
   ↓
   What commands do I run?

INSTALLATION.md
   ↓
   What am I doing, why am I doing it, and how do I know it worked?

TUTORIALS/
   ↓
   What should I learn from the system I just built?
```

---

## 1. What this project is

This repository builds a reproducible infrastructure environment using:

```text
OpenStack
   │
   ├── Terraform ─────────────── infrastructure lifecycle
   │
   └── Virtual machines
          │
          └── Ansible ────────── operating systems + infrastructure services
                    │
                    ├── Edge / security
                    ├── Slurm / HPC
                    └── Kubernetes prerequisites
                               │
                               └── kubeadm ── Kubernetes cluster
                                             │
                                             ├── Cilium
                                             ├── OpenStack CCM
                                             ├── Cinder CSI
                                             └── Argo CD
                                                    │
                                                    └── applications
```

The design deliberately separates ownership:

| Layer | Owner | Responsibility |
|---|---|---|
| Cloud | Terraform | Networks, ports, security groups, VMs, cloud resources |
| Host | Ansible | Rocky Linux, users, packages, services, hardening |
| Kubernetes bootstrap | kubeadm | Control-plane and worker formation |
| Kubernetes networking | Cilium | CNI, service networking, policy, observability |
| Kubernetes applications | Argo CD | GitOps deployment and reconciliation |
| Batch HPC | Slurm | Scheduler and scientific/HPC workloads |

This separation is one of the project's most important teaching principles: **do not make one tool own a layer that another tool is designed to manage.**

---

## 2. Current architecture

### 2.1 Network planes

```text
                         Internet
                            │
                       OpenStack router
                            │
              ┌─────────────┴─────────────┐
              │                           │
      Management network             Kubernetes network
        10.50.0.0/24                  10.51.0.0/24
              │                           │
      ┌───────┴────────┐          ┌───────┴─────────────┐
      │                │          │                     │
     edge        infrastructure   HAProxy VIP       K8s nodes
   10.50.0.10        VMs          .100:6443         .11-.23
      │
      ├── WireGuard
      ├── Pi-hole
      ├── nftables
      ├── Suricata
      └── Wazuh manager

                 WireGuard clients
                    10.60.0.0/24
                          │
                          └── edge
```

Canonical network variables are:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr: 10.51.0.0/24
vpn_cidr: 10.60.0.0/24
```

Avoid reintroducing alternate names such as `management_cidr` and `wireguard_cidr`.

### 2.2 Virtual machines

| Node | Address | Function |
|---|---:|---|
| `edge` | `10.50.0.10` | Bastion, WireGuard, Pi-hole, nftables, Suricata IDS, Wazuh manager/edge security |
| `hermes-orchestrator-01` | `10.50.0.11` | Personal/federation Hermes outside Kubernetes |
| `slurm-controller-01` | `10.50.0.12` | `slurmctld`, `slurmdbd`, initial MariaDB |
| `login1` | `10.50.0.20` | User login + Slurm client |
| `login2` | `10.50.0.21` | User login + Slurm client |
| `slurm-cpu-01` | `10.50.0.30` | 64-core Slurm compute |
| `slurm-cpu-02` | `10.50.0.31` | 64-core Slurm compute |
| `api-lb-01` | `10.51.0.100` | HAProxy Kubernetes API endpoint |
| `k8s-cp-01` | `10.51.0.11` | Kubernetes control plane |
| `k8s-cp-02` | `10.51.0.12` | Kubernetes control plane |
| `k8s-cp-03` | `10.51.0.13` | Kubernetes control plane |
| `k8s-worker-01` | `10.51.0.21` | Kubernetes worker |
| `k8s-worker-02` | `10.51.0.22` | Kubernetes worker |
| `k8s-worker-03` | `10.51.0.23` | Kubernetes worker |

The Kubernetes API endpoint is intentionally stable:

```text
10.51.0.100:6443
        │
      HAProxy
     /  |  \
   CP1 CP2 CP3
```

The load-balancer implementation can be replaced later without changing the endpoint consumed by Kubernetes clients.

---

## 3. Security model

Security is layered rather than delegated to a single control:

```text
Internet
   │
   ▼
OpenStack security groups
   │
   ▼
Host nftables
   │
   ▼
Service-specific controls
   │
   ├── WireGuard
   ├── SSH identities
   ├── Kubernetes API
   ├── Cilium NetworkPolicy
   └── application authentication
```

### SSH identities

`rocky` is retained as the image/bootstrap/recovery identity. `nyameko` is the normal administrative identity installed by Ansible.

The bootstrap path should not be disabled merely because the regular administrative path works. Recovery must be proven first.

### VPN

WireGuard provides the private administrative path:

```text
client 10.60.0.2/32
       │
       ▼
edge 10.60.0.1
       │
       ├── 10.50.0.0/24
       ├── 10.51.0.0/24
       └── 10.60.0.0/24
```

### Kubernetes API exposure

The intended access path is:

```text
WireGuard client
       │
       ▼
10.51.0.100:6443
       │
     HAProxy
       │
  ┌────┼────┐
 CP1  CP2  CP3
```

VPN clients should **not** receive a direct `vpn_cidr → control-plane:6443` bypass.

---

## 4. Kubernetes platform

The cluster is built as six nodes:

```text
                  HAProxy
              10.51.0.100:6443
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
      CP-01        CP-02        CP-03
        │            │            │
        └────────────┼────────────┘
                     │
              Cilium networking
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
    worker-01    worker-02    worker-03
```

The current deployment pins Kubernetes to the `v1.36` minor line and has reached the stage where Cilium connectivity testing passes.

### Cilium baseline

Cilium currently provides the cluster CNI and baseline service/network functionality. The initial configuration deliberately does **not** attempt to turn every advanced Cilium feature on at once.

Deferred exercises include:

- Hubble/advanced flow observability
- kube-proxy replacement
- advanced eBPF service routing
- ClusterMesh
- deeper Cilium policy design

That is intentional: establish a known-good baseline first, then change one dimension at a time.

### Cilium validation milestone

The current cluster has passed:

```text
cilium connectivity test
→ 82 tests
→ 780 actions
→ all successful
→ 55 tests skipped
→ 1 scenario skipped
```

This is a major platform acceptance milestone.

---

## 5. OpenStack storage and GitOps

After networking is stable:

```text
Kubernetes
   │
   ├── OpenStack Cloud Controller Manager
   │
   └── Cinder CSI
           │
           ▼
     PersistentVolume
           │
           ▼
          Cinder
```

Argo CD then becomes the normal Kubernetes application delivery path:

```text
Git
 │
 ▼
Argo CD
 │
 ▼
Kubernetes
```

Planned platform applications include:

```text
Wazuh indexer + dashboard
Prometheus + Grafana + Loki
Ingress + cert-manager
JupyterHub
PostgreSQL
Astro
Research Hermes
AI/ML services
Quantum-computing services
```

---

## 6. Kubernetes and Slurm are complementary

They are not competing schedulers for the same purpose.

```text
                 Compute platform
                       │
           ┌───────────┴───────────┐
           ▼                       ▼
      Kubernetes                 Slurm
           │                       │
 services / APIs /           MPI / batch / HPC /
 notebooks / portals         scientific workloads
```

Kubernetes provides the application platform. Slurm remains the HPC scheduler.

This separation also makes future federation possible: JupyterHub and research services can present a controlled interface while Slurm remains authoritative for HPC resources.

---

## 7. Hermes federation

Hermes is deliberately split across trust boundaries:

```text
                  Personal / Federation root
                           │
                           ▼
              hermes-orchestrator-01
                           │
               read/report by default
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
        Infrastructure             Research Hermes
                                     (Kubernetes)
```

The infrastructure Hermes should not become an unrestricted automation principal. Capabilities are intended to be explicit, auditable and least-privilege.

---

## 8. Application path: bare metal → application

The repository is ultimately teaching this progression:

```text
Physical / bare-metal infrastructure
             │
             ▼
       OpenStack cloud
             │
             ▼
        Rocky Linux VMs
             │
             ▼
        Host networking
             │
             ▼
      Kubernetes cluster
             │
             ▼
          Cilium
             │
             ▼
         Cinder CSI
             │
             ▼
         Argo CD
             │
             ▼
     Ingress / application
             │
             ▼
        Public service
```

A simple Astro application is planned as the first end-to-end public application milestone.

---

## 9. Deployment stages

```text
01  OpenStack authentication
02  Terraform
03  OpenStack networks / SGs / VMs
04  Rocky Linux bootstrap
05  SSH / time / users / base packages
06  Edge security + DNS + VPN
07  HAProxy Kubernetes API endpoint
08  containerd + Kubernetes prerequisites
09  kubeadm 3-control-plane cluster
10  Cilium
11  OpenStack CCM + Cinder CSI
12  Argo CD
13  Observability
14  Slurm
15  Wazuh platform services
16  JupyterHub
17  Astro
18  Research Hermes
19  AI/ML + quantum workloads
```

Every stage should have an explicit acceptance test before the next layer is trusted.

---

## 10. Teaching philosophy

This is not just a deployment repository. It is intended to be a practical infrastructure classroom.

The tutorials turn real implementation work into learning material:

1. architecture and design
2. networking and security
3. Terraform + Ansible deployment
4. Kubernetes platform engineering
5. OpenStack integration and storage
6. observability and operations
7. Slurm/HPC integration
8. GitOps and applications
9. Hermes, AI/ML and quantum-computing platform design

The troubleshooting history is part of the curriculum. A broken DNF repository, incorrect OpenStack security-group scope, SELinux denial, wrong container-runtime package, missing CRI permissions, and Cilium NodePort/health requirements are more useful to a student than a deployment document that pretends everything worked first time.

---

## 11. Repository conventions

### Secrets

Never commit credentials, private SSH keys, WireGuard private keys, cloud credentials, kubeadm bootstrap tokens or other sensitive material.

Use:

```text
Terraform/OpenStack → environment variables / clouds.yaml outside Git
Ansible             → private inventory + Vault/SOPS where required
WireGuard           → keys generated on the appropriate host/client
GitOps              → sealed/encrypted secret mechanism later
```

### Environment-specific values

Private values belong under the private inventory/environment. Public repository defaults should remain safe and reusable.

### Ownership

```text
Terraform → cloud
Ansible   → hosts
kubeadm   → cluster bootstrap
Cilium    → cluster networking
Argo CD   → applications
Slurm     → HPC scheduling
```

---

## 12. Start here

### First-time deployment

Read [INSTALLATION.md](INSTALLATION.md).

### Already know the architecture

Use [QUICK_GUIDE.md](QUICK_GUIDE.md).

### Want to understand the engineering

Start with [tutorials/01-architecture-and-design.md](tutorials/01-architecture-and-design.md) and progress through the tutorials in order.

### Current repository status

The most recent deployment work includes the Kubernetes API/load-balancer path, containerd/CRI prerequisites, automated multi-node kubeadm joins, Cilium networking, and the OpenStack security-group work required for Cilium node health and NodePort testing. The project history records these iterations explicitly.

---

## References

- [OpenStack Documentation](https://docs.openstack.org/)
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Cinder](https://docs.openstack.org/cinder/latest/)
- [Argo CD](https://argo-cd.readthedocs.io/)
- [Slurm](https://slurm.schedmd.com/)
- [Wazuh](https://documentation.wazuh.com/)
- [Suricata](https://suricata.io/documentation/)
- [WireGuard](https://www.wireguard.com/)
- [Pi-hole](https://docs.pi-hole.net/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [JupyterHub](https://jupyterhub.readthedocs.io/)
- [Astro](https://docs.astro.build/)
