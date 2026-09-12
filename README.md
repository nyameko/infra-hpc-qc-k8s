# infra-hpc-qc-k8s

## Hybrid Quantum-Centric Supercomputing Infrastructure

`infra-hpc-qc-k8s` is a reproducible Infrastructure-as-Code and GitOps platform for hybrid **HPC + Kubernetes + AI/ML + quantum-computing research**.

The project is deliberately more than a collection of deployment scripts. It is a reference implementation and teaching environment for understanding how a modern research-computing platform is assembled, operated, validated, secured, extended, and eventually reproduced or recovered.

The central design rule is simple:

> **Each layer has an owner, each boundary has a contract, and each capability is validated before the next layer depends on it.**

---

## What this project builds

The reference environment currently uses OpenStack and Rocky Linux as the infrastructure substrate, with Kubernetes and Slurm providing complementary execution environments.

```text
                          Users / Researchers
                                  │
                  ┌───────────────┴───────────────┐
                  │                               │
                  ▼                               ▼
             Research Portal                 Research Services
                  │                        JupyterHub / Hermes /
                  │                        AI/ML / quantum apps
                  ▼                               │
             Kubernetes                           │
                  │                               │
        ┌─────────┼─────────┐                     │
        ▼         ▼         ▼                     │
      Cilium   Argo CD   Observability             │
                  │      Prometheus/Grafana        │
                  ▼                                │
           Platform applications                   │
                                                   │
      ┌────────────────────────────────────────────┘
      │
      ▼
   Slurm HPC
      │
      ├── CPU / MPI / batch workloads
      └── future GPU / accelerator workloads

OpenStack
   │
   ├── Terraform → cloud infrastructure
   └── Rocky Linux VMs
          │
          └── Ansible → hosts + bootstrap
```

The current architecture intentionally keeps Kubernetes and Slurm complementary rather than attempting to turn either into a universal scheduler.

---

## The ownership model

The project is easiest to understand as a sequence of control boundaries:

```text
Terraform
    ↓
Cloud infrastructure

Ansible
    ↓
Operating systems + host services + bootstrap

kubeadm
    ↓
Kubernetes cluster formation

Cilium
    ↓
Kubernetes networking + policy

Cinder CSI
    ↓
Persistent storage integration

Argo CD
    ↓
Long-lived Kubernetes applications

Prometheus / Grafana
    ↓
Observability

Slurm
    ↓
HPC scheduling + execution

Hermes / Heretic
    ↓
Research orchestration + controlled execution
```

The separation is intentional. Terraform should not become a Kubernetes application manager. Ansible should not become the long-term Kubernetes application controller. Argo CD should not manage OpenStack VMs or Rocky Linux configuration. Slurm should remain authoritative for HPC batch scheduling.

---

## Reference network topology

The current reference environment uses three logical network planes:

| Network | CIDR | Primary purpose |
|---|---|---|
| Management | `10.50.0.0/24` | hosts, SSH, infrastructure services |
| Kubernetes | `10.51.0.0/24` | Kubernetes nodes and the external Kubernetes VIP |
| WireGuard | `10.60.0.0/24` | private operator/researcher access |

Important reference endpoints include:

```text
edge              10.50.0.10
api-lb-01         10.51.0.100
k8s-cp-01         10.51.0.11
k8s-cp-02         10.51.0.12
k8s-cp-03         10.51.0.13
k8s-worker-01     10.51.0.21
k8s-worker-02     10.51.0.22
k8s-worker-03     10.51.0.23
```

The Kubernetes API is consumed through the stable endpoint:

```text
10.51.0.100:6443
        │
      HAProxy
      /  |  \
    CP1  CP2  CP3
```

The same external load-balancer boundary is being used for application ingress:

```text
WireGuard client
      │
      ▼
Pi-hole / private DNS
      │
      ▼
10.51.0.100
      │
    HAProxy
      │
      ├── workers:31818 → Traefik HTTP
      └── workers:31924 → Traefik HTTPS
                 │
                 ▼
              Ingress
                 │
                 ▼
             Application
```

Kubernetes does not own the external load balancer. The OpenStack VM and HAProxy do. This distinction is important when interpreting Kubernetes and Argo CD health fields.

---

## Current platform milestones

The platform has already crossed several significant boundaries:

- OpenStack infrastructure is provisioned through Terraform.
- Rocky Linux hosts and core services are configured through Ansible.
- A three-control-plane / three-worker Kubernetes cluster is bootstrapped with kubeadm.
- Cilium is the cluster CNI, and the baseline connectivity suite has passed.
- OpenStack Cinder CSI provides persistent storage through Kubernetes StorageClasses.
- Argo CD provides the Kubernetes GitOps boundary.
- Sealed Secrets is the selected Git-safe mechanism for Kubernetes secrets.
- Traefik is deployed as the Kubernetes ingress controller.
- Pi-hole provides private infrastructure DNS over WireGuard.
- cert-manager obtains trusted certificates through Cloudflare DNS-01 and Let's Encrypt.
- The Traefik test route has been validated directly through all three worker NodePorts, including valid Let's Encrypt TLS and an `HTTP/2 200` response from the nginx test application.

The next objective is to operationalize the external HAProxy ingress path as a fully inventory-driven, scalable component and then build observability around the resulting platform.

---

## Repository map

```text
infra-hpc-qc-k8s/
├── terraform/       # cloud infrastructure
├── ansible/         # hosts, security, services, bootstrap
├── argocd/          # GitOps applications and platform resources
├── docs/            # installation guides and engineering tutorials
└── secrets/         # local/non-public secret inputs; never commit plaintext secrets
```

The repository deliberately avoids turning a single directory into the owner of everything.

### `terraform/`

Terraform answers:

> **What infrastructure exists?**

Networks, subnets, ports, security groups, VM instances, and OpenStack-side load-balancer infrastructure belong here.

[Terraform README](terraform/README.md)

### `ansible/`

Ansible answers:

> **How are those machines configured and bootstrapped?**

Operating systems, users, SSH, firewalls, containerd, host services, Kubernetes prerequisites, kubeadm bootstrap, edge services, Slurm VMs, and the Argo CD bootstrap belong here.

[Ansible README](ansible/README.md)

### `argocd/`

Argo CD answers:

> **What should the Kubernetes platform be running?**

Long-lived Kubernetes applications, Helm configuration, Kubernetes resources, and GitOps reconciliation belong here.

[Argo CD README](argocd/README.md)

### `docs/`

The documentation answers three different questions:

```text
README
  → What is this project?

Installation / quick guides
  → How do I deploy it?

Tutorials
  → What did we learn, why does it work, and how do we debug it?
```

See [docs/README.md](docs/README.md).

---

## Secrets

The platform uses **Bitnami Sealed Secrets** rather than committing plaintext Kubernetes credentials.

The workflow is:

```text
plaintext Secret on workstation
        ↓
     kubeseal
        ↓
   SealedSecret
        ↓
       Git
        ↓
     Argo CD
        ↓
Sealed Secrets controller
        ↓
 Kubernetes Secret
```

The controller's private sealing key must remain outside Git and be backed up securely. The public certificate may be distributed to trusted operators so secrets can be sealed offline.

The project deliberately does not require KSOPS or SOPS for the Kubernetes application path.

---

## Documentation philosophy

This is a teaching repository, so failure analysis is part of the documentation.

Tutorials should normally follow this rhythm:

```text
Goal
  ↓
Architecture / ownership
  ↓
Change one layer
  ↓
Validate the layer
  ↓
Inspect the real runtime state
  ↓
Diagnose failures
  ↓
Move to the next layer
```

The preferred lesson is not merely "run these commands." It is:

> **Understand which controller owns the state, inspect that controller's inputs and outputs, and validate the actual runtime path.**

---

## Current limitations and deliberate deferrals

The baseline platform intentionally does not enable every advanced feature immediately.

Deferred Kubernetes/Cilium work includes:

- Hubble / advanced flow observability
- kube-proxy replacement
- advanced eBPF service-routing experiments
- ClusterMesh
- advanced Cilium policy design

These should be introduced only after the baseline is stable and observable.

Likewise, advanced research services such as Hermes, Heretic, JupyterHub, quantum SDK infrastructure, and GPU/QPU integration should arrive only after the core platform is measurable and recoverable.

---

## Path forward

The recommended progression is:

```text
1. Finish scalable HAProxy ingress
          ↓
2. Prometheus / Grafana observability
          ↓
3. Re-run Cilium validation while watching telemetry
          ↓
4. Wazuh / Suricata operational integration
          ↓
5. JupyterHub
          ↓
6. Slurm services and HPC integration
          ↓
7. A100 / accelerator integration
          ↓
8. Hermes / Heretic
          ↓
9. research and quantum-computing applications
```

The immediate priority is not adding more frameworks. It is making the platform **observable, reproducible, scalable, and boring to operate**.

---

## Start here

Read these in order:

1. [Terraform](terraform/README.md)
2. [Ansible](ansible/README.md)
3. [Argo CD](argocd/README.md)
4. [Documentation](docs/README.md)
5. [Tutorials](docs/tutorials/)

For a complete deployment, follow the installation documentation rather than reconstructing the deployment from individual commands in the README.

---

## Project principle

The project is ultimately trying to demonstrate one thing well:

> **A complex hybrid research-computing platform can remain understandable when infrastructure, hosts, Kubernetes, applications, HPC scheduling, security, and research services are separated into explicit control planes with observable contracts between them.**
