# Contributing and getting help

Search the [existing issues](https://github.com/nyameko/infra-hpc-qc-k8s/issues), [pull requests](https://github.com/nyameko/infra-hpc-qc-k8s/pulls) and this wiki before opening a duplicate. Use the owning repository for the problem: identity/portal → Quantum Platform; canonical agents → ACP; scientific algorithms → Quantum Workflows; optical physics → PhotonicsLab; scheduler/network/storage/deployment → Infra.

## Good bug report

State user role, sanitized environment, affected component, expected/actual behavior, steps to reproduce, time/window, relevant source revision and image digest, ticket/job/run ID, redacted logs, whether it is reproducible locally and your attempted non-destructive diagnostics. For security issues follow the repository's secure disclosure process; do not open a public issue containing exploit material or secrets.

## Good pull request

Keep the change narrow; reference the issue, describe changed contracts, provide validation and backward-compatibility risks, identify migrations or irreversible effects, update user/developer docs, and explain how to roll back. Preserve historical lessons while making newer status explicit. Do not merge solely because CI passed.

For local execution see [Developer guide](Developer-guide.md). For doc format use [Wiki publishing and editorial policy](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/WIKI_PUBLISHING.md).