# Supported versions and coordinated releases

This document defines version policy, not an assertion that every service has been upgraded. The machine-readable candidate and evidence ledger is [versions/platform.yaml](../versions/platform.yaml).

## v0.1.0-alpha.1 runtime targets

| Dependency | Target | Release gate |
| --- | --- | --- |
| Python | 3.14 | API, ACP, workflows, CI and Python Docker build/runtime must pass |
| Node.js | 24 LTS | Astro workspaces, CI and Docker builders must pass |
| PostgreSQL | 18 | Validate database migration/restore against deployed minor |
| Kubernetes | 1.36 | Capture actual cluster versions and API compatibility |
| Rocky Linux | 9 | Record deployed guest version and Ansible compatibility |

A common interpreter does not imply interchangeable scientific dependencies. If SQD, PySCF, Qiskit or Hermes do not support Python 3.14, record the tested exception and block alpha sign-off until a compatibility decision is reviewed.

## Snapshot versus release

The September 23 snapshot records the original source dev commits. The image digests in platform.yaml come from operator-provided Kubernetes output: they are historical observations, NOT a newly verified live cluster state. Refresh source SHAs, deployed imageIDs, Argo revisions, Kubernetes/Cilium/Slurm/Wazuh/Suricata versions, migrations and backup evidence at the freeze. Never equate a healthy Deployment with successful integration.

Alpha.1 remains a candidate until gates pass. Freeze each repo's tested commit and capture independently versioned images and OCI digests. The umbrella manifest is the compatible bill of materials; independently evolving components need not keep matching package versions forever.

## Change and promotion

Humans, students and agents branch from protected dev and PR into dev. Create a temporary release/vX.Y.Z from a reviewed integration commit; validate identical artifacts in isolated staging before merging into protected main and tagging. Back-merge all release fixes into dev. Keep main the GitHub default. The active infra Argo root remains on reviewed infra/main while the live portal is temporarily using development images.

A mutable dev tag changing is not a GitOps change. Implement a reviewed automated Git-visible digest update or a separate generated release overlay that triggers the matching Django migration hook BEFORE the application rollout. Do not manually pin digests in human-authored Kustomization or delete pods to deploy.

A hotfix branches from released main/tag, runs scoped tests and security checks, verifies on staging/canary where feasible, ships a patch release, then back-merges into dev. Every emergency gate waiver must be recorded.
