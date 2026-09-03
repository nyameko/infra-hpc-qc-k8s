# Terraform

Terraform owns the **cloud infrastructure layer** of `infra-hpc-qc-k8s`.

The current reference implementation targets OpenStack, but the architecture is deliberately intended to support other clouds or bare metal by replacing the provider-specific infrastructure layer rather than rewriting the platform.

## Responsibility boundary

```text
Terraform
    ↓
cloud resources

Ansible
    ↓
operating systems + host services

kubeadm / Cilium
    ↓
Kubernetes substrate

Argo CD
    ↓
Kubernetes applications
```

Terraform should not become the primary Kubernetes application deployment engine. That would create two competing controllers once Argo CD is active.

## Current layout

```text
terraform/
├── environments/
│   └── template/
└── modules/
    ├── api_lb/
    ├── compute/
    ├── network/
    └── security/
```

The current repository exposes separate compute, network, API load-balancer and security modules, with environment-specific configuration under `terraform/environments`. citeturn438820view2turn438820view3

## What Terraform creates

In the reference OpenStack environment, Terraform is responsible for resources such as:

```text
networks
subnets
ports
security groups
VM instances
API load-balancer infrastructure
cloud-init inputs
```

The actual resource set is provider-specific and should remain isolated inside the relevant environment/module code.

## What Terraform should not own

Terraform should not permanently own:

```text
Kubernetes Deployments
Helm releases
Argo CD Applications
Prometheus/Grafana configuration
JupyterHub
Astro
application lifecycle
```

Those belong to Argo CD after bootstrap.

## Cinder and storage

Terraform may manage **OpenStack-side storage infrastructure and identity prerequisites** where appropriate, but the Kubernetes Cinder CSI driver is not a Terraform-managed application in the target architecture.

The distinction is:

```text
Terraform
    ↓
OpenStack resource / identity prerequisites

Argo CD
    ↓
Cinder CSI Helm application
    ↓
StorageClasses
    ↓
PVCs
```

This avoids Terraform and Argo CD both trying to manage the same Kubernetes application resources.

## Application credentials

Terraform can technically manage OpenStack application credentials, but credential secrets can become part of Terraform state. For sensitive application credentials, prefer a deliberately secured credential/secret-management workflow.

For the current Cinder CSI bootstrap, an application credential is an OpenStack identity input consumed by the Kubernetes Secret used by the CSI driver. Do not commit the credential secret to Terraform variables or Git.

## Provider portability

OpenStack is a reference provider, not the platform definition.

The provider-specific boundary is approximately:

```text
terraform/
└── environments/<provider-or-environment>/
      ↓
provider-specific modules
```

Higher-level platform concepts should remain stable:

```text
Kubernetes
Cilium
Argo CD
Prometheus/Grafana
Slurm
Hermes
Heretic
JupyterHub
Astro
```

A different cloud would replace the relevant infrastructure modules and provider integration.

## Bare metal adaptation

The architecture is also intended to work without a cloud provider:

```text
Bare metal
    ↓
Ansible / bare-metal provisioning
    ↓
Kubernetes + Slurm
```

Nova and Neutron disappear; Kubernetes, Slurm, Cilium, Argo CD and the application architecture do not.

## State and environments

Treat Terraform state as sensitive infrastructure metadata. Do not commit local state or secrets. Keep provider credentials outside the repository.

Use the environment structure to isolate cloud/project-specific values from reusable modules.

## Workflow

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

Always inspect the plan before apply in a real environment.

## Teaching objective

Terraform should teach the difference between:

```text
Desired cloud infrastructure
        vs.
Runtime host configuration
        vs.
Kubernetes desired state
```

Keeping those concerns separate is one of the core architectural lessons of the project.
