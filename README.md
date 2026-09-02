# Hybrid Quantum Centric Supercomputing Kubernetes Infrastructure

Infrastructure-as-code for the National Integrated Cyber Infrastructure Systems (NICIS) Quantum Hybrid HPC / AI / ML / QC platform.

## Current Deployment Status

Infrastructure
-  ✓ OpenStack network and VMs
-  ✓ Rocky Linux base configuration
-  ✓ Edge / WireGuard / Pi-hole
-  ✓ Wazuh manager
-  ✓ Suricata IDS
-  ✓ Kubernetes API load balancer
-  ✓ containerd
-  ✓ Kubernetes 1.36.4 prerequisites
-  ✓ kubeadm cluster initialization
-  → Cilium
-  → Cinder CSI
-  → Argo CD
-  → Slurm
-  → Prometheus / Grafana
-  → Hermes Orchestrator
-  → Hermes Researcher
-  → JupyterHub
-  → Astro

## Initial environment

This first environment is the central personal/admin federation environment. It is **not** the research production cluster. It provides the control/orchestration foundation from which the later production and Purple Team environments will be derived.

### Initial VM topology

| VM | IP | Role |
|---|---:|---|
| edge | 10.50.0.10 | WireGuard, Pi-hole, nftables, Suricata IDS, SSH bastion, Wazuh agent |
| hermes-orchestrator-01 | 10.50.0.11 | isolated personal Hermes orchestrator; read/report only by default |
| slurm-controller-01 | 10.50.0.12 | slurmctld + slurmdbd + initial MariaDB; no user logins |
| login1 | 10.50.0.20 | SSH user login, Slurm client |
| login2 | 10.50.0.21 | SSH user login, Slurm client |
| slurm-cpu-01 | 10.50.0.30 | 64-core pure Slurm compute node |
| slurm-cpu-02 | 10.50.0.31 | 64-core pure Slurm compute node |
| k8s-cp-01 | 10.51.0.11 | Kubernetes control plane |
| k8s-cp-02 | 10.51.0.12 | Kubernetes control plane |
| k8s-cp-03 | 10.51.0.13 | Kubernetes control plane |
| k8s-worker-01 | 10.51.0.21 | Kubernetes worker |
| k8s-worker-02 | 10.51.0.22 | Kubernetes worker |
| k8s-worker-03 | 10.51.0.23 | Kubernetes worker |

Kubernetes API VIP: **10.51.0.100**.

WireGuard clients: **10.60.0.0/24**.

## Hermes federation

There are two Hermes roles from the beginning:

1. `hermes-orchestrator-01`: isolated VM outside Kubernetes. This is the personal/federation orchestrator and reporting point. It receives read-only telemetry/log access and has no credentials capable of directly pushing Git changes or bypassing approval.
2. `research-hermes`: later deployed inside Kubernetes. It is the research-cluster agent and reports upward to the personal/federation Hermes.

The VM agent is deliberately outside Kubernetes so a Kubernetes failure cannot take down the orchestration/control root.

## Slurm architecture

`slurmctld` is on **its own dedicated VM**, not `edge` and not a login node. The initial controller also hosts `slurmdbd` and MariaDB to keep the first deployment small. A dedicated database VM and a backup slurmctld VM can be introduced later.

`login1` and `login2` provide user SSH access and Slurm commands (`sbatch`, `squeue`, `srun`, etc.). They are not the compute pool.

`slurm-cpu-01` and `slurm-cpu-02` are initially the pure CPU partition, each provisioned as a 64-core compute VM.

## Deployment order

1. Terraform: OpenStack networks, router, security groups, ports, VMs, and Kubernetes API Api_Lb LB.
2. Ansible: OS hardening, SSH, Wazuh agent, edge services, Hermes orchestrator host, Slurm nodes, Kubernetes prerequisites.
3. kubeadm: bootstrap 3 control-plane + 3 worker Kubernetes cluster.
4. Cilium + OpenStack CCM + Cinder/shared-storage CSI.
5. Argo CD.
6. Platform services: ingress, cert-manager, Prometheus/Grafana/Loki, Wazuh, JupyterHub, Ollama, llama.cpp.
7. Research Hermes inside Kubernetes.

## Secrets

No credentials belong in the repository. Use environment variables for Terraform/OpenStack credentials and Ansible Vault or SOPS/age for secrets. A future GitOps secret manager can be layered on later.

## How to Deploy

- TODO: Fix ip and kubernetes network infrastructure
- TODO: Turn this deployment guide, instao an installaiton guide / and / or workshop / tutorial.

This setup will walkthrough and guide users on deployment of the Kubernetes cluster onto an OpenStack workspace. This will be done initially from an Arch Workstation (I use Arch btw) adn POC servers will deploy Rocky 9 where appropriate.

### Installation Guide

1. Clone the Repository
```bash
git clone https://github.com/nyameko/infra-hpc-qc-k8s.git
cd infra-hpc-qc-k8s
```

1. Install Terraform, Ansible and the OpenStack Client on your Local Workstation

```bash
sudo pacman -Syu ansible terraform python-openstackclient
```
