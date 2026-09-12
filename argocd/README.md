# Argo CD

Argo CD is the **Kubernetes application lifecycle and GitOps layer** of `infra-hpc-qc-k8s`.

It is bootstrapped by Ansible and then becomes the normal owner of long-lived Kubernetes applications.

The practical rule is:

> **Once the GitOps boundary exists, a Kubernetes application's desired state belongs in Git and is reconciled by Argo CD.**

---

## Argo CD's question

Argo CD answers:

> **What should Kubernetes be running?**

It does not answer:

> What OpenStack resources exist?

or:

> How should Rocky Linux be configured?

Those belong to Terraform and Ansible.

---

## The ownership boundary

```text
Terraform
    ↓
OpenStack infrastructure

Ansible
    ↓
Hosts + bootstrap

kubeadm / Cilium / CSI
    ↓
Kubernetes substrate

Argo CD
    ↓
Long-lived Kubernetes applications
```

This is the central GitOps boundary in the repository.

---

## Why Argo CD is used

Argo CD gives the platform a continuously reconciled desired state:

```text
Git
  ↓
Argo CD
  ↓
render desired state
  ↓
compare with cluster
  ↓
sync
  ↓
Kubernetes converges
```

That provides:

- versioned application definitions
- repeatable deployments
- drift detection
- self-healing when enabled
- explicit ownership
- a useful audit trail
- a consistent deployment method for students and collaborators

---

## Bootstrap

Ansible installs Argo CD into the cluster.

The bootstrap controller should remain intentionally small:

```text
Ansible
   ↓
install Argo CD
   ↓
wait for core components
   ↓
hand application ownership to GitOps
```

Argo CD does not need the operator's `/etc/kubernetes/admin.conf` for its in-cluster destination. Its application controller uses its Kubernetes ServiceAccount and RBAC to talk to `https://kubernetes.default.svc`.

---

## Repository structure

The preferred structure is application-oriented:

```text
argocd/
├── applications/
│   ├── <application>.yml
│   ├── <application>-config.yml
│   └── ...
│
└── resources/
    ├── <application>/
    └── platform resources
```

For an application using an upstream Helm chart, separate:

```text
upstream package
        +
project-specific values/resources
        +
Argo CD reconciliation
```

Do not assume that placing arbitrary YAML beside a Helm `values.yaml` makes Argo render it. A Git source used as a Helm values source is still only a values source. If a resource needs its own lifecycle, give it an Argo Application or include it through a deliberate multi-source/application structure.

This distinction was important when introducing the Traefik test route.

---

## Platform application versus application configuration

A useful split is:

```text
cert-manager
    → installs the cert-manager platform/controller

cert-manager-config
    → owns the Cloudflare Secret + ClusterIssuer

traefik
    → installs/configures Traefik

traefik-test
    → owns the demonstration Deployment + Service + Ingress
```

This is a good general pattern.

The controller and the application's configuration are different concerns and do not need to be forced into one Application.

---

## Sync waves

Sync waves are useful where one application depends on another capability existing first.

The current pattern is:

```text
wave 0
cert-manager
     ↓
wave 1
cert-manager-config
     ↓
wave 2
traefik-test
```

The purpose is not to create a complicated dependency graph. It is to express a small number of real prerequisites.

Use waves when the ordering is meaningful; do not assign arbitrary waves to everything.

---

## Helm versus Git resources

Many applications naturally have two sources:

```text
Source 1
  upstream Helm chart

Source 2
  project-specific Git resources / values
```

This is particularly useful for platform components where the upstream chart is maintained by another project but the deployment policy is local to this repository.

For example:

```text
cert-manager
  → upstream chart

project configuration
  → ClusterIssuer
  → SealedSecret

traefik
  → upstream chart

project resources
  → Ingress / test application / other Kubernetes objects
```

Keep the local resources explicit enough that a reader can see what this project is adding to the upstream package.

---

## Secrets

The platform uses Bitnami Sealed Secrets.

Argo CD should reconcile only encrypted representations such as:

```yaml
kind: SealedSecret
```

The runtime Kubernetes Secret is produced by the Sealed Secrets controller.

For example:

```text
Cloudflare API token
       ↓
local plaintext Secret
       ↓
kubeseal
       ↓
SealedSecret in Git
       ↓
Argo CD
       ↓
cert-manager Secret
       ↓
Cloudflare DNS-01
```

The same boundary applies to other application credentials.

---

## Ingress and certificate management

The repository intentionally lets applications request certificates through their Ingress rather than hand-authoring a `Certificate` for every application.

The pattern is:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-cloudflare
```

and:

```yaml
tls:
  - hosts:
      - example.quantum.nyameko.com
    secretName: example-tls
```

cert-manager's ingress-shim observes the Ingress and creates the appropriate Certificate resource.

This gives the application an explicit contract:

> "I need TLS for this hostname."

The platform's ClusterIssuer then determines how that certificate is obtained.

---

## External load balancer versus Kubernetes `LoadBalancer`

This project deliberately uses an external HAProxy VM rather than requiring Kubernetes to own the external load-balancer lifecycle.

The Kubernetes path is therefore:

```text
Traefik Service
    ↓
NodePorts
    ↓
worker nodes
```

while the external path is:

```text
HAProxy VM
10.51.0.100
    ↓
worker NodePorts
```

Kubernetes may therefore show a `LoadBalancer` Service or Ingress with an empty `status.loadBalancer`, even though the service is operational through the external HAProxy layer.

Do not introduce MetalLB or Octavia merely to make the Kubernetes status field look conventional. The external LB is an intentional architecture decision.

If the repository later wants a cleaner Argo dashboard, add an explicit custom health interpretation rather than changing the network architecture just to satisfy a generic health heuristic.

---

## Worker scaling and HAProxy

HAProxy backend membership should come from inventory-driven worker topology.

The desired chain is:

```text
Terraform
   ↓
new worker VM
   ↓
Ansible inventory
   ↓
Kubernetes worker
   ↓
HAProxy backend rendering
```

For Traefik:

```text
worker inventory
    ↓
HTTP NodePort 31818
HTTPS NodePort 31924
```

The role should generate all worker backends instead of hard-coding worker01/02/03.

This keeps cluster scaling from becoming a documentation or configuration trap.

---

## Application lifecycle

The normal application lifecycle should be:

```text
developer/operator change
        ↓
Git commit
        ↓
Argo detects new desired state
        ↓
render
        ↓
sync
        ↓
health assessment
        ↓
Kubernetes converges
```

Automated sync, pruning, and self-healing are useful defaults for infrastructure applications once the repository has established confidence in its manifests.

---

## App-of-Apps / ApplicationSet

The repository already has a root Argo application model.

A useful future target is:

```text
root
 ├── cert-manager
 ├── cert-manager-config
 ├── traefik
 ├── prometheus
 ├── grafana
 ├── wazuh
 ├── jupyterhub
 ├── hermes
 └── research applications
```

ApplicationSet becomes attractive when the number of applications, environments, or repeated application patterns is large enough that explicit Application objects become cumbersome.

Do not add ApplicationSet simply because it exists. The repository should earn that abstraction through real repetition.

---

## What should not be managed by Argo CD

Do not move these resources into GitOps just because they are related to Kubernetes:

```text
OpenStack VM lifecycle
Rocky Linux configuration
nftables host firewall
WireGuard host configuration
HAProxy service installation
Slurm operating systems
Terraform state
```

They belong to Terraform and/or Ansible.

---

## Validation model

Argo status must be interpreted together with runtime evidence.

```text
Synced
  ≠
Healthy

Healthy
  ≠
End-to-end reachable from the user
```

For the Traefik milestone we validated all three layers separately:

```text
Argo desired state
        ↓
Kubernetes resources
        ↓
worker NodePort
        ↓
TLS certificate
        ↓
HTTP response
```

This is the standard the rest of the project should follow.

---

## Teaching objective

Argo CD is where the repository teaches GitOps as a control system rather than as a YAML format.

The important lesson is:

> **Git contains desired state; Argo CD reconciles it; Kubernetes executes it; runtime validation proves whether the platform actually works.**

---

## Related documentation

- [Project README](../README.md)
- [Terraform](../terraform/README.md)
- [Ansible](../ansible/README.md)
- [Documentation](../docs/README.md)
