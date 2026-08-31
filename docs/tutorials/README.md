# NICIS Hybrid HPC / Cloud / AI-ML / Quantum Infrastructure — Documentation & Course Pack

This pack is a refined, teaching-grade rewrite of the documentation in
[`nyameko/infra-hpc-qc-k8s`](https://github.com/nyameko/infra-hpc-qc-k8s), reorganised so it can carry a
multi-week course: video lectures, in-person workshops, and self-paced tutorials, in the same spirit as
[CHPC's Student Cluster Competition materials](https://github.com/chpc-tech-eval/scc).

It does three things the original scattered `.md` files didn't:

1. **Consolidates** thirteen overlapping documents into eight topic-owning references, each with a
   "Further reading" section instead of a single link buried mid-paragraph.
2. **Reconciles** the docs against the live repository — the Terraform modules, Ansible roles, Makefile
   targets and file tree that actually exist today — and flags every place they disagree.
   See [`docs/09-gap-analysis-and-recommendations.md`](docs/09-gap-analysis-and-recommendations.md).
3. **Structures** the material as a course, with the gap analysis doubling as the capstone assignment list.
   See [`COURSE_OUTLINE.md`](COURSE_OUTLINE.md).

## Reading order

| # | File | Covers |
|---|------|--------|
| 1 | [`docs/01-architecture-and-design.md`](docs/01-architecture-and-design.md) | Hybrid HPC/K8s/AI-ML/QC architecture, VM topology, separation of concerns, environment roadmap |
| 2 | [`docs/02-networking-and-security.md`](docs/02-networking-and-security.md) | Network segmentation, WireGuard, nftables, access control groups, Pi-hole, Wazuh, Suricata, threat model |
| 3 | [`docs/03-deployment-terraform-ansible.md`](docs/03-deployment-terraform-ansible.md) | Terraform provisioning, Ansible configuration, bootstrap sequence, variable model |
| 4 | [`docs/04-kubernetes-platform.md`](docs/04-kubernetes-platform.md) | kubeadm, API load balancing, Cilium, storage, Argo CD, ingress, observability, JupyterHub, Astro, PostgreSQL |
| 5 | [`docs/05-slurm-hpc-scheduler.md`](docs/05-slurm-hpc-scheduler.md) | Slurm controller/login/compute design, job submission, roadmap |
| 6 | [`docs/06-hermes-ai-agents.md`](docs/06-hermes-ai-agents.md) | Hermes federation, AI agent orchestration, Hermes as a security orchestrator |
| 7 | [`docs/07-quantum-computing-sandbox.md`](docs/07-quantum-computing-sandbox.md) | Qiskit/PennyLane/CUDA-Q sandbox design inside JupyterHub |
| 8 | [`docs/08-secrets-variables-versions.md`](docs/08-secrets-variables-versions.md) | Secrets policy, canonical variable names, version-pinning policy |
| 9 | [`docs/09-gap-analysis-and-recommendations.md`](docs/09-gap-analysis-and-recommendations.md) | Concrete inconsistencies found between docs and repo, prioritised fixes |
| — | [`COURSE_OUTLINE.md`](COURSE_OUTLINE.md) | Module map → lectures → workshops → tutorials → rubric |

## Conventions used throughout this pack

- **Canonical names only.** Network variables are always `mgmt_cidr` (`10.50.0.0/24`), `k8s_cidr`
  (`10.51.0.0/24`), `vpn_cidr` (`10.60.0.0/24`). No document in this pack uses `management_cidr` or
  `wireguard_cidr`.
- **"Initial environment" means the personal/admin federation environment**, not the research production
  cluster and not a Purple Team range. Every doc says so explicitly the first time it matters, because this
  distinction drives a lot of the security posture (see `docs/01` §1.8).
- **A callout marked `⚠ Gap`** means the pack found a disagreement between two source documents, or between
  a document and the live repository, during the review that produced this pack (31 August 2026). These are
  collected in `docs/09`.
- **A callout marked `▶ Lab`** means the item is deliberately left unfinished in the reference repo and is
  earmarked as a course exercise rather than a bug.

## Relationship to the source repository

This pack supersedes, but does not yet replace, the following files currently in
`nyameko/infra-hpc-qc-k8s`: `README.md`, `docs/bootstrap-sequence.md`, `docs/domains.md`,
`docs/secrets.md`, `docs/versions.md`, plus the drafted-but-not-yet-committed `architecture.md`,
`EDGE_SECURITY.md`, `hermes-federation.md`, `INSTALLATION.md`, `QUICK_GUIDE.md`, `slurm.md`,
`VARIABLE_MODEL.md`. The recommendation in `docs/09` is to commit this pack's `docs/` directory in place of
all of them, and point `README.md` at it.
