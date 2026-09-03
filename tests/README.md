# Testing

The infrastructure test suite follows a testing pyramid.

```text
                         E2E / POC
                            ▲
                            │
                   integration tests
                            │
              ┌─────────────┴─────────────┐
              │                           │
       infrastructure               application/
          functional                  scientific
              │
       ┌──────┴──────┐
       │             │
     Ansible       OpenStack
    convergence   infrastructure
       │             │
       └──────┬──────┘
              │
       static / policy tests
```

## Infrastructure

### Terraform / OpenStack

- `tests/terraform/` contains provider policy/security and infrastructure smoke-test foundations.
- Static CI validates Terraform and runs preliminary IaC security analysis.
- Provider-backed tests are kept separate because they require real OpenStack credentials and infrastructure.

### Ansible

- `tests/ansible/convergence.sh` checks repeated application of desired state.
- `tests/ansible/functional.sh` checks host-level operational contracts.
- Molecule/Testinfra/Pytest can be introduced as the roles mature.

## Scientific software

The future quantum/research repository will use a deeper testing hierarchy:

```text
unit
numerical correctness
integration
reference implementation
end-to-end
benchmarking
```

Tests answer **"is it correct?"**.

Benchmarks answer **"how well does it perform?"**.

They are related but deliberately separate.

## CI/CD boundary

CI validates changes before merge. GitOps/CD reconciles the merged desired state.

```text
Hermes / developer
        │
        │ PR
        ▼
     GitHub
        │
        ▼
 GitHub Actions
   validate/test
        │
      merge
        │
        ▼
     Argo CD
        │
        ▼
   Kubernetes
```

Hermes agents may eventually propose changes, but do not bypass review or directly trigger deployment.
