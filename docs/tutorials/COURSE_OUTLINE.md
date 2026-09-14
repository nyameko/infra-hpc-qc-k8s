# Course Outline: Hybrid HPC / Cloud / AI-ML / Quantum Infrastructure

A facilitation guide for turning `infra-hpc-qc-k8s` into a practical multi-week or intensive infrastructure course.

## Audience and prerequisites

Students or early-career engineers comfortable with Linux and basic networking. No prior Kubernetes, Slurm or quantum-computing experience is required.

## Learning outcomes

By the end of the course a participant should be able to:

- provision segmented OpenStack infrastructure with Terraform;
- configure Rocky Linux hosts with Ansible;
- bootstrap and validate a highly available Kubernetes cluster;
- explain Cilium's role and validate its datapath;
- deploy persistent Kubernetes applications through Argo CD;
- build and validate Prometheus/Grafana observability;
- operate a layered Wazuh/Siccata security plane;
- operate Slurm alongside Kubernetes;
- establish private DNS and ingress through Pi-hole, HAProxy and Traefik;
- deploy PostgreSQL and JupyterHub as platform services;
- explain Hermes/Heretic trust boundaries and least-privilege capabilities;
- run a quantum-computing sandbox within JupyterHub;
- close a real infrastructure gap through a reviewed Git change.

## Module map

| Module | Theme | Primary deliverable |
|---|---|---|
| M0 | Orientation and access | working lab access |
| M1 | Architecture and separation of concerns | architecture explanation |
| M2 | Networking, WireGuard and edge security | validated network/security path |
| M3 | Terraform provisioning | reproducible OpenStack resources |
| M4 | Ansible fleet configuration | host bootstrap playbooks |
| M5 | Kubernetes bootstrap and Cilium | healthy six-node cluster |
| M6 | GitOps and observability | Argo-managed Prometheus/Grafana dashboards |
| M7 | Wazuh / Siccata security plane | security telemetry pipeline |
| M8 | Slurm HPC scheduler | working partition + sample job |
| M9 | Private ingress and DNS | end-to-end private application path |
| M10 | PostgreSQL + JupyterHub | researcher platform baseline |
| M11 | Hermes / Heretic | capability design and safe orchestration |
| M12 | Quantum sandbox | notebook-based simulator lab |
| M13 | Astro portal | user-facing application |
| M14 | Capstone | reviewed PR closing a platform gap |

## M6 — GitOps and observability

### Objectives

Students learn why Kubernetes application reconciliation and metric observability are distinct layers.

### Workshop

Deploy/validate:

```text
Argo CD
Prometheus
Grafana
Grafana dashboard sidecar
Git-managed dashboard ConfigMaps
```

Build dashboard panels from actual Prometheus metrics.

### Key experiments

1. Put `extraScrapeConfigs` at the wrong Helm hierarchy and observe why Git can look correct while the runtime configuration is wrong.
2. Compare `job="haproxy"`, `job="kubernetes-pods"` and `job="kubernetes-service-endpoints"`.
3. Update a dashboard in Git and observe Argo + Grafana sidecar reconciliation.
4. Distinguish “metric exists” from “dashboard query is correct”.

### Deliverable

A validated Git-managed dashboard set with a written explanation of at least one failed PromQL assumption and its correction.

## M7 — Wazuh / Siccata

### Objectives

Understand the separation between security-event management, IDS/IPS telemetry and operational observability.

### Architecture

```text
edge
 ├── Wazuh Manager
 └── Siccata

Kubernetes
 ├── Wazuh Indexer
 └── Wazuh Dashboard

Prometheus/Grafana
 └── operational/security telemetry
```

### Workshop

- complete the edge Wazuh Manager configuration;
- deploy Wazuh Indexer;
- deploy Wazuh Dashboard;
- verify an agent event end-to-end;
- add Siccata telemetry;
- add Grafana security-health panels.

### Deliverable

Working Wazuh security pipeline plus Grafana operational security dashboard.

## M8 — Slurm HPC scheduler

### Objectives

Operate Slurm independently of Kubernetes.

### Workshop

```text
controller
  ↓
login
  ↓
compute
```

Validate:

```bash
sinfo
squeue
scontrol show nodes
```

Submit and verify a sample job.

Add Grafana telemetry after Slurm is working.

### Deliverable

Working partition + completed sample job + first Slurm dashboard.

## M9 — Private ingress and DNS

### Objectives

Replace temporary GUI tunnels with the actual platform access path.

### Architecture

```text
WireGuard
   ↓
Pi-hole private DNS
   ↓
HAProxy
   ↓
Traefik
   ↓
Kubernetes Service
```

Cloudflare provides public DNS/ACME where public exposure is intentional.

### Workshop

- validate HAProxy application frontends/backends;
- deploy and validate Traefik;
- establish Pi-hole private DNS records;
- configure Cloudflare DNS/ACME;
- publish one application;
- remove normal-use `kubectl port-forward` and SSH tunnels.

### Deliverable

An end-to-end application URL reachable through the intended ingress path, with the DNS path documented.

## M10 — PostgreSQL + JupyterHub

### Objectives

Introduce the platform identity/data layer and interactive computing environment.

### Deliverable

PostgreSQL-backed platform service and JupyterHub environment with observable health.

## M11 — Hermes / Heretic

### Objectives

Understand controlled orchestration, trust boundaries, and prompt-injection risks.

### Workshop

Design capabilities using:

```text
read → propose → approve → apply
```

External interfaces:

```text
Telegram
Discord
   ↓
controlled liaison
   ↓
Hermes
```

No external message should directly become an unrestricted infrastructure action.

### Deliverable

Capability specification with scope, approval gate, audit trail and threat model.

## M12 — Quantum sandbox

Use JupyterHub to run the quantum simulator progression and later connect to controlled remote quantum resources.

Potential sandbox toolkits include Qiskit, PennyLane and CUDA-Q, with hardware-provider access handled through explicit secrets and capability boundaries.

## M13 — Astro portal

Deliver the user-facing application through the completed DNS/ingress path.

## M14 — Capstone

Choose a real item from the project's backlog and ship it through the same Git/Argo/validation path used throughout the course.

Suggested capstone themes:

- complete Wazuh hardening;
- improve Slurm observability;
- complete ingress/DNS automation;
- build a Hermes read-only integration;
- create a GPU/QPU accounting schema and dashboard template;
- close a disaster-recovery or backup gap.

## Assessment

| Component | Weight |
|---|---:|
| Tutorial checklists | 40% |
| Capstone PR | 35% |
| Capstone presentation | 15% |
| Participation / peer support | 10% |

## Teaching principle

The point is not to create a tutorial in which everything works on the first attempt.

The point is to teach students how to identify which layer owns a failure, inspect the actual runtime state, change the smallest responsible layer, and prove the fix with an acceptance test.
