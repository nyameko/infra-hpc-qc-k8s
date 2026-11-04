# Infrastructure wiki

Infrastructure as Code, operations, and reproducible engineering for the hybrid HPC + Kubernetes + quantum research environment.

**Audience:** researchers, students, administrators, platform engineers and automated assistants. **Snapshot:** source repository `main`, 4 November 2026. The wiki documents contracts and examples; `main` is not proof of the currently deployed image or cluster state.

## Start here

| You want to… | Read |
|---|---|
| Understand platform layers, responsibilities and topology | [Architecture](Architecture.md) |
| Join as a researcher and use notebooks/Slurm | [Researcher guide](Researcher-guide.md) |
| Reproduce an installation in your own cloud | [Installation](Installation.md) |
| Inspect or operate the existing deployment | [Operator runbook](Operator-runbook.md) |
| Diagnose a failure without destroying evidence | [Troubleshooting](Troubleshooting.md) |
| Review security and credential ownership | [Security and recovery](Security-and-recovery.md) |
| Modify Terraform, Ansible, Argo CD or tests | [Developer guide](Developer-guide.md) |
| Report or contribute a change | [Contributing](Contributing.md) |

## Platform ownership

`infra-hpc-qc-k8s` owns provider infrastructure, operating systems, networks, Kubernetes, Slurm, shared storage, observability, security monitoring and deployment manifests. [Quantum Platform](https://github.com/nyameko/quantum-platform) owns human identity, programmes and the portal; [Quantum Workflows](https://github.com/nyameko/quantum-workflows) owns science; [ACP](https://github.com/nyameko/agent-control-plane) owns canonical agent context; [PhotonicsLab](https://github.com/nyameko/photonicslab) owns optical models. A deployed component does not imply this repository owns its product behavior.

## Verified versus planned

The historical M3 acceptance documented a restricted Slurm CPU smoke job with durable scientific artifacts. M4 agent persistence, richer programme integration, GPU federation, remote QPUs and terminal pairing have additional schema, authorization, image-promotion and live-conformance gates. **Do not infer a feature is usable from an Argo Healthy status alone.** Inspect the current release and evidence before advising users.

Canonical references: [README](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/README.md), [installation and operations guide](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/INSTALLATION.md), [M3→M4 handoff](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/current-platform-state-m3-m4.md), [recent release notes](https://github.com/nyameko/infra-hpc-qc-k8s/tree/main/docs/releases).