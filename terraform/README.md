# Terraform

Terraform owns the **cloud infrastructure layer** of `infra-hpc-qc-k8s`.

Its job is to declare and reconcile the infrastructure that must exist before Ansible, Kubernetes, Argo CD, Slurm, or research applications can operate.

The reference implementation targets OpenStack, but OpenStack is an implementation detail of the current environment rather than the definition of the platform.

---

## Terraform's question

Terraform answers one question:

> **What infrastructure exists?**

It should not answer:

> How is the operating system configured?

or:

> What Kubernetes application should be running?

Those questions belong to other layers.

---

## Ownership boundary

```text
Terraform
    ↓
OpenStack resources
    ↓
VMs / networks / security groups / ports

Ansible
    ↓
Rocky Linux + host services + bootstrap

kubeadm / Cilium
    ↓
Kubernetes substrate

Argo CD
    ↓
Kubernetes applications
```

Keeping these boundaries separate prevents multiple tools from fighting over the same state.

---

## What Terraform owns

In the reference OpenStack environment Terraform is responsible for resources such as:

```text
Networking
├── networks
├── subnets
├── routers
├── ports
└── network attachments

Security
└── security groups and rules

Compute
└── VM instances and their infrastructure metadata

External access
└── api-lb-01 / HAProxy infrastructure

Bootstrap inputs
└── cloud-init and other machine-creation inputs
```

The exact resources are provider-specific and should remain isolated in the Terraform modules and environment definitions.

---

## What Terraform does not own

Terraform should not become the long-lived application controller for:

```text
Kubernetes Deployments
Helm releases
Argo CD Applications
Traefik configuration
cert-manager Certificates
Prometheus / Grafana runtime configuration
JupyterHub
Astro
Hermes / Heretic applications
```

Those resources belong to Argo CD after the Kubernetes/GitOps boundary is established.

Likewise, Terraform should not replace Ansible for host configuration.

---

## Repository structure

The intended shape is:

```text
terraform/
├── environments/
│   └── <environment>/
└── modules/
    ├── api_lb/
    ├── compute/
    ├── network/
    └── security/
```

### Modules

Modules should express reusable infrastructure concepts:

- `network` — networks, subnets, routers and related primitives
- `security` — OpenStack security-group policy
- `compute` — VM creation and attachment
- `api_lb` — the external Kubernetes API/load-balancer VM infrastructure

### Environments

Environment directories should contain the provider-specific and deployment-specific decisions:

```text
provider credentials
project IDs
image IDs
flavors
CIDRs
node counts
network names
availability zones
```

Those values should not leak into reusable modules when they can be parameterized cleanly.

---

## Scaling model

Terraform should make node-count changes boring.

Adding a Kubernetes worker should be a change to infrastructure intent, not a manual sequence of VM operations.

The intended lifecycle is:

```text
Change worker count / node declaration
        ↓
terraform plan
        ↓
review resource delta
        ↓
terraform apply
        ↓
new OpenStack VM exists
        ↓
Ansible configures it
        ↓
kubeadm joins the node
        ↓
GitOps / HAProxy consume the resulting topology
```

The important rule is that Terraform creates the machine; it does not need to understand the application's Kubernetes workload running on that machine.

---

## Load balancing boundary

The project intentionally uses an explicit `api-lb-01` VM running HAProxy rather than relying on an OpenStack Octavia controller being available.

Terraform therefore owns the existence and networking of the VM:

```text
Terraform
   ↓
api-lb-01
10.51.0.100
   ↓
Ansible
   ↓
HAProxy
```

HAProxy's configuration belongs to Ansible, not Terraform.

This is a useful example of layered ownership:

```text
Terraform → VM exists
Ansible   → HAProxy is configured
Kubernetes → application endpoints exist
```

---

## Storage boundary

Terraform may provision OpenStack-side storage prerequisites and identity resources where appropriate, but the Kubernetes Cinder CSI driver belongs to Argo CD.

The separation is:

```text
Terraform
    ↓
OpenStack-side infrastructure / identity

Argo CD
    ↓
Cinder CSI
    ↓
StorageClasses
    ↓
PVCs
```

Do not make Terraform and Argo CD co-own the same Kubernetes storage resources.

---

## Credentials and state

Terraform state is infrastructure state and should be treated as sensitive metadata.

Do not commit:

```text
*.tfstate
*.tfstate.backup
provider credentials
application credentials
private cloud files
```

Cloud credentials belong outside Git and should be supplied through the normal Terraform/OpenStack authentication mechanism.

Be particularly careful with OpenStack application credentials: if Terraform creates a credential and exposes its secret material in state, the state itself becomes sensitive.

For Kubernetes application credentials, prefer the project's Git-safe Sealed Secrets workflow rather than pushing provider credentials into Terraform variables.

---

## Portability

OpenStack is the current reference provider.

The stable platform contracts above it should remain provider-neutral:

```text
OpenStack / bare metal / future cloud
                ↓
         Kubernetes substrate
                ↓
        Argo CD applications
                ↓
     Slurm / research workloads
```

A future cloud implementation should replace the infrastructure provider and related modules without requiring a redesign of Kubernetes applications, Slurm, Hermes, or the research layer.

---

## Bare-metal interpretation

The same architecture can be adapted to bare metal:

```text
Bare metal provisioning
        ↓
Ansible / hardware management
        ↓
Kubernetes + Slurm
```

In that model there is no Nova or Neutron, but the higher-level contracts remain.

---

## Normal workflow

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

Use `terraform plan` as the review boundary. A production change should be understandable before it is applied.

Useful discipline:

```text
edit
 ↓
format / validate
 ↓
plan
 ↓
review
 ↓
apply
 ↓
verify the actual OpenStack state
```

---

## Teaching objective

Terraform exists in this project to teach the distinction between:

```text
Infrastructure desired state
        vs.
Host/runtime configuration
        vs.
Kubernetes desired state
```

If a Terraform change starts requiring knowledge of a Kubernetes Deployment, a Linux service unit, or an application-level configuration file, stop and re-evaluate the ownership boundary.

---

## Related documentation

- [Project README](../README.md)
- [Ansible](../ansible/README.md)
- [Argo CD](../argocd/README.md)
- [Installation and tutorials](../docs/README.md)
