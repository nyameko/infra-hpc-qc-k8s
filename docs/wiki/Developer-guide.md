# Developer guide

## Scope and layout

- `terraform/` provisions provider infrastructure; `environments/template` supplies the public starting point.
- `ansible/` contains inventories, roles and playbooks for Rocky Linux, identity, storage and HPC.
- `argocd/` holds application declarations and version-controlled Kubernetes resources.
- `containers/` holds build contexts; `scripts/` maintenance; `tests/` validation; `docs/tutorials/` the historical teaching record.

## Local contribution workflow

Start from a current `main` or the active integration branch; use a `feature/*` branch; change the owning subsystem and add documentation/test coverage in the same PR. Do not commit files under protected inventory or `secrets/`. Use `terraform fmt -check`, `terraform validate`, `ansible-lint` where configured, `ansible-playbook --syntax-check` with appropriate inventory, YAML/Kustomize validation, and tests documented in [test README](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/tests/README.md). Ansible `--check` is not an automatic guarantee of safety for every module.

## Configuration and releases

A source branch, container image and deployed environment are **three separate identifiers**. Pin image digests; capture migration compatibility; review environment selectors and branch promotion. A high-level change to ACP or Quantum Platform may need an infrastructure image update, but importing foreign business logic into Helm/Ansible is usually the wrong boundary.

## Definition of done

A reproducible change includes a human task, owning repository, dependency versions, expected state, tests (including negative auth tests if relevant), privacy review, release/rollback notes and observed acceptance evidence. New operators should be able to repeat the procedure without private chat history. If a feature is merely planned, label it as planned.

See [documentation course outline](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/COURSE_OUTLINE.md), [release conventions](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/README.md) and [GitOps guide](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/04b-argocd-gitops-secrets-ksops.md).