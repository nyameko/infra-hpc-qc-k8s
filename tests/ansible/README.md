# Ansible tests

Ansible testing is divided into two different questions.

## Convergence

> If I apply the desired configuration twice, does the second application make no changes?

This is the infrastructure equivalent of checking declarative convergence.

The preliminary runner is `convergence.sh`. It executes a selected playbook twice against the reference inventory and records the second-run recap.

For destructive or production infrastructure, this should eventually run in an isolated test environment rather than directly against the reference environment.

## Functional

> After convergence, does the machine actually provide the contract it claims to provide?

Examples:

- SSH policy is correct.
- required packages/services are present.
- containerd/CRI is healthy.
- Kubernetes prerequisites are correct.
- HAProxy listens and can reach its backends.
- Slurm daemons are healthy.
- Wazuh/Suricata services are running where expected.

The preliminary runner is `functional.sh`.

## Future

The Ansible test stack should evolve toward:

- Molecule for role-level isolated convergence;
- Testinfra/Pytest for host functional assertions;
- provider-backed integration environments for end-to-end verification.

The important boundary is that Ansible remains the deployment mechanism; the tests independently verify the resulting state.
