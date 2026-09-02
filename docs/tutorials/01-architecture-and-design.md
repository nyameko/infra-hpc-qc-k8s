# Tutorial 1 — Architecture and Design

## 1. Purpose

`infra-hpc-qc-k8s` is a teaching-oriented infrastructure-as-code project for building a hybrid research platform spanning OpenStack, Rocky Linux, Kubernetes, HPC/Slurm, AI/ML, security, and quantum-computing workloads.

This first environment is the personal/admin federation environment. It exists to prove the automation and architecture before the design is cloned into higher-stakes research and deliberately isolated Purple Team environments.

The project is intentionally built so that a learner can answer two questions at every layer:

1. **What owns this resource?**
2. **What is the smallest interface required between layers?**

Those questions are more important than any individual command.

---

## 2. Separation of concerns

The architecture has four primary control layers:

```text
Terraform
    │
    ▼
OpenStack infrastructure

Ansible
    │
    ▼
Operating systems + infrastructure services

kubeadm
    │
    ▼
Kubernetes cluster bootstrap

Argo CD
    │
    ▼
Kubernetes application lifecycle
```

| Layer | Owns | Does not own |
|---|---|---|
| Terraform | networks, routers, ports, security groups, floating IPs, VMs, cloud infrastructure | OS packages and service configuration |
| Ansible | OS configuration, users, SSH, time, firewalls, WireGuard, Pi-hole, Wazuh, Suricata, Slurm, Kubernetes host prerequisites and bootstrap orchestration | normal Kubernetes application delivery |
| kubeadm | Kubernetes initialization and node joins | OpenStack or OS provisioning |
| Argo CD | applications inside Kubernetes | OpenStack or host configuration |

A practical rule follows from this:

> If Terraform needs `remote-exec` or `local-exec` to configure a service, the boundary is probably wrong. If Ansible starts deploying long-lived Kubernetes applications with `kubectl apply`, the boundary is probably wrong.

The repository's original architecture tutorial already states this as a load-bearing design rule. citeturn409697view0

---

## 3. Current environment topology

The current OpenStack environment contains:

| VM | IP | Purpose |
|---|---:|---|
| `edge` | `10.50.0.10` | WireGuard, Pi-hole, nftables, Wazuh manager, Suricata, bastion |
| `hermes-orchestrator-01` | `10.50.0.11` | isolated infrastructure Hermes, read/report first |
| `slurm-controller-01` | `10.50.0.12` | Slurm controller/accounting services |
| `login1` | `10.50.0.20` | Slurm login |
| `login2` | `10.50.0.21` | Slurm login |
| `slurm-cpu-01` | `10.50.0.30` | Slurm compute |
| `slurm-cpu-02` | `10.50.0.31` | Slurm compute |
| `api-lb-01` | `10.51.0.100` | HAProxy Kubernetes API load balancer |
| `k8s-cp-01` | `10.51.0.11` | Kubernetes control plane |
| `k8s-cp-02` | `10.51.0.12` | Kubernetes control plane |
| `k8s-cp-03` | `10.51.0.13` | Kubernetes control plane |
| `k8s-worker-01` | `10.51.0.21` | Kubernetes worker |
| `k8s-worker-02` | `10.51.0.22` | Kubernetes worker |
| `k8s-worker-03` | `10.51.0.23` | Kubernetes worker |

The Kubernetes control endpoint is:

```text
10.51.0.100:6443
```

The API endpoint is intentionally independent of any individual control plane.

---

## 4. Network segmentation

The canonical network variables are:

```yaml
mgmt_cidr: 10.50.0.0/24
k8s_cidr:  10.51.0.0/24
vpn_cidr:  10.60.0.0/24
```

The project previously suffered from naming drift (`management_cidr`, `wireguard_cidr`, etc.). That was corrected so Terraform, Ansible, and documentation use the same vocabulary.

The current network roles are:

```text
10.50.0.0/24   Management
10.51.0.0/24   Kubernetes + API LB
10.60.0.0/24   WireGuard administration
```

The three networks are not one flat subnet because a failure or compromise in one plane should not automatically collapse every other plane.

---

## 5. Kubernetes HA architecture

The Kubernetes cluster uses three control planes and three workers.

```text
                         VPN / clients
                              │
                              ▼
                     10.51.0.100:6443
                            HAProxy
                       /       |       \
                      ▼        ▼        ▼
                   CP1 .11   CP2 .12   CP3 .13
                      │        │        │
                      └────────┼────────┘
                               │
                            stacked
                              etcd
                               │
                ┌──────────────┼──────────────┐
                ▼              ▼              ▼
             W1 .21         W2 .22         W3 .23
```

This is stacked-etcd HA: each control-plane node also hosts an etcd member.

HAProxy was chosen because Octavia was not exposed in the OpenStack service catalog at deployment time. The design intentionally keeps an abstraction around the API load balancer so Octavia can replace HAProxy later without changing the Kubernetes endpoint.

---

## 6. Why HAProxy comes before kubeadm

HAProxy is infrastructure, not an application backend.

It can therefore be deployed before Kubernetes:

```text
HAProxy starts
    ↓
backend checks fail
    ↓
kubeadm creates API servers
    ↓
backend checks become healthy
```

This exact behavior was observed during deployment. Before kubeadm, HAProxy reported `cp1`, `cp2`, and `cp3` down. After all three control planes came online, HAProxy reported all three up.

That is correct behavior, not a race condition.

---

## 7. Security layers

The infrastructure uses multiple independent security boundaries:

```text
Internet
   │
   ▼
OpenStack security groups
   │
   ▼
VM host firewall (nftables)
   │
   ▼
WireGuard / service boundaries
   │
   ▼
Cilium
   │
   ▼
Kubernetes workloads
```

Each layer has a different scope:

- **OpenStack SG:** which VM/port may receive traffic.
- **nftables:** what the Linux host accepts or forwards.
- **WireGuard:** which administrative peers can enter the private routed network.
- **Cilium:** workload connectivity and network policy.
- **Kubernetes RBAC:** who can call the API and which resources they can manipulate.
- **Slurm accounting/QOS:** which user/job can consume HPC resources.

No layer is a substitute for the others.

---

## 8. Identity model

Two SSH identities are used deliberately:

```text
rocky
  ↓
OpenStack bootstrap / recovery

nyameko
  ↓
normal administration
```

Ansible creates `nyameko`, installs the administrative public key, and grants passwordless sudo.

Normal private-node SSH uses `ProxyJump` through `edge`.

This also supports the eventual hardening step where public bootstrap SSH is removed once WireGuard and recovery access are fully proven.

---

## 9. Edge architecture

`edge` is a deliberately multifunctional but bounded infrastructure node:

```text
edge
├── WireGuard
├── Pi-hole
├── nftables
├── Wazuh manager
└── Suricata IDS
```

Pi-hole is infrastructure DNS. The intended path is:

```text
VM / Pod
   ↓
CoreDNS
   ↓
10.50.0.10:53
   ↓
Pi-hole
   ↓
upstream DNS
```

Wazuh is staged: the manager runs on edge first, while the indexer and dashboard will later run in Kubernetes.

Suricata begins in IDS mode instead of inline IPS because visibility should precede enforcement during a new deployment.

---

## 10. Why Kubernetes and Slurm coexist

They solve different problems.

```text
Kubernetes → long-running services, APIs, notebooks, platform workloads
Slurm      → HPC batch jobs, MPI, scientific and quantum simulations
```

The project deliberately avoids forcing MPI-style jobs into a microservice scheduler or forcing always-on web services into an HPC batch scheduler.

The login nodes are not compute nodes. That distinction is part of standard HPC architecture and is worth preserving as a teaching example.

---

## 11. Hermes architecture

The infrastructure Hermes orchestrator is outside Kubernetes on purpose.

```text
Personal Hermes
       │
       ├── infrastructure orchestration
       ├── reporting / logs
       └── later → Research Hermes inside Kubernetes
```

A Kubernetes control-plane failure should not take the infrastructure-level observer/orchestrator down with it.

The first implementation should remain tightly permissioned and human-approved for changes.

---

## 12. Domain strategy

The primary domain is `nyameko.com`.

Planned technical names include:

```text
research.nyameko.com
jupyter.research.nyameko.com
grafana.research.nyameko.com
argo.research.nyameko.com
hermes.research.nyameko.com
quantum.nyameko.com
```

`omra.nyameko.com` is reserved for the future nonprofit initiative rather than this infrastructure platform.

A future public identity decision remains between the more descriptive `quantum.nyameko.com` naming and the wider project identity. The technical architecture should not depend on that branding decision.

---

## 13. Evolution roadmap

The platform is intentionally being built in layers:

```text
✓ OpenStack network and VMs
✓ Rocky Linux base configuration
✓ Edge / WireGuard / Pi-hole
✓ Wazuh manager
✓ Suricata IDS
✓ Kubernetes API load balancer
✓ containerd
✓ Kubernetes 1.36.4 prerequisites
✓ kubeadm cluster initialization
✓ 3 control planes
✓ 3 workers
✓ Cilium baseline
→ Cinder CSI
→ Argo CD
→ Prometheus / Grafana
→ Slurm
→ Hermes Orchestrator
→ Hermes Researcher
→ JupyterHub
→ Astro
```

Cilium's later feature path is intentionally staged:

```text
✓ kube-proxy-compatible baseline
→ Hubble
→ kube-proxy replacement
→ ClusterMesh
```

The later work is deliberately not allowed to obscure the baseline deployment.

---

## 14. Teaching method: document the failure, not only the success

One of the strongest lessons from the build is that a polished infrastructure repository can hide the most useful knowledge.

This project should document:

```text
expected state
   ↓
observed failure
   ↓
diagnostic command
   ↓
root cause
   ↓
minimal correction
   ↓
validation
   ↓
automation
```

Real examples from this deployment included:

- OpenStack flavor ID versus flavor name confusion.
- Ansible variable scope and private inventory issues.
- Canonical CIDR naming drift.
- Broken/stale package repositories.
- WireGuard systemd handler issues.
- Pi-hole short-image-name resolution.
- HAProxy SELinux binding denial.
- Wrong API load-balancer security-group source network.
- Rocky Linux containerd packaging assumptions.
- kubeadm temporary bootstrap credential handling.
- Cilium VXLAN requirements.
- Cilium NodePort and ICMP security-group requirements.
- Misinterpreting a privileged Unix socket error as a network firewall error.

Those are the exercises.

---

## 15. Validation philosophy

Do not define success as "the command returned zero."

Validate each dependency layer:

```text
OpenStack
   ↓
VM reachability
   ↓
OS services
   ↓
HAProxy
   ↓
containerd / CRI
   ↓
kubeadm
   ↓
etcd
   ↓
Kubernetes API
   ↓
node registration
   ↓
CNI
   ↓
pod connectivity
   ↓
service connectivity
```

This layered method is both the operating model and the teaching model.

---

## References

- Terraform: https://developer.hashicorp.com/terraform/docs
- Ansible: https://docs.ansible.com/
- Kubernetes kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- Kubernetes HA: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- OpenStack: https://docs.openstack.org/
- OpenGitOps: https://opengitops.dev/
- NIST SP 800-160: https://csrc.nist.gov/pubs/sp/800/160/v1/r1/final
