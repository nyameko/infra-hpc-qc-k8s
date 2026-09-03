# Argo CD

Argo CD is the **Kubernetes application lifecycle and GitOps layer** of `infra-hpc-qc-k8s`.

It is bootstrapped by Ansible and then becomes the normal owner of long-lived Kubernetes applications.

## The boundary

```text
Terraform
    ↓
cloud

Ansible
    ↓
hosts + Kubernetes bootstrap

Argo CD
    ↓
Kubernetes applications
```

The transition is intentional:

```text
Ansible bootstraps Argo CD
          ↓
Argo CD manages Kubernetes
          ↓
new Kubernetes applications are Git-managed
```

## Why Argo CD is in the architecture

Argo CD provides declarative, version-controlled application definitions and continuous reconciliation. Its application controller continuously compares live state to the desired state defined by the configured source. citeturn523162search4turn883343search9

That makes Git the application declaration and Argo CD the reconciler.

## Bootstrap

The current bootstrap path is:

```text
Ansible
   │
   ▼
k8s-cp-01
   │
   ├── existing kubectl
   ├── existing administrator kubeconfig
   └── Kubernetes API access
             │
             ▼
        install Argo CD
```

The role is intentionally small. It is not intended to become a general Kubernetes application installer.

The current standard installation is suitable for an Argo CD instance managing the same cluster in which it runs. Argo's documentation describes the standard installation as the normal in-cluster multi-tenant installation pattern and the HA installation as the production-oriented alternative. citeturn523162search1

## How Argo CD authenticates to Kubernetes

For the in-cluster destination, **Argo CD does not consume `/etc/kubernetes/admin.conf` and does not consume the operator's kubeconfig**.

Instead:

```text
Argo CD application-controller
        │
        ▼
Kubernetes ServiceAccount
        │
        ▼
RBAC permissions
        │
        ▼
https://kubernetes.default.svc
        │
        ▼
Kubernetes API
```

The standard in-cluster configuration uses the service identity available inside the pod. The Argo application controller therefore has the Kubernetes permissions it needs through Kubernetes RBAC, not by receiving a copied administrator kubeconfig. citeturn523162search1turn523162search3

For external clusters, Argo supports storing cluster credentials as Secrets in the `argocd` namespace. That is a different pattern and is not required for this single in-cluster reference deployment. citeturn523162search3

## Application controller: StatefulSet vs Deployment

The current application controller is a StatefulSet:

```text
argocd-application-controller-0
```

This is normal.

Argo's controller sharding model has historically used stable replica identity and predictable pod names. The official high-availability documentation describes increasing the StatefulSet replicas to create additional shards. citeturn883343search0turn883343search1

A Deployment instead treats replicas as interchangeable. Argo documents a separate dynamic cluster-distribution feature that can run the controller as a Deployment, but that is a deliberate alternative mechanism rather than something we need to enable for this project. citeturn883343search3

For our current small cluster:

```text
1 controller replica
    → sufficient initially

StatefulSet
    → normal current implementation

No persistent application data
    → implied by the StatefulSet choice
```

We do not need to modify it merely because it is a StatefulSet.

## Repository layout

```text
argocd/
└── applications/
    ├── cinder-csi/
    │   ├── application.yaml
    │   ├── values.yaml
    │   ├── README.md
    │   └── resources/
    │       └── storageclasses.yaml
    │
    └── <future applications>/
```

The current Cinder application is already represented this way. citeturn438820view0turn662409view4

## Cinder CSI: first GitOps application

The current Cinder Application uses two sources:

```text
Source 1
  upstream Helm chart
  openstack-cinder-csi

Source 2
  this Git repository
  StorageClasses
```

This gives a useful distinction:

```text
Helm
  → package/vendor application

Git repository
  → project-specific configuration and policy

Argo CD
  → reconciliation
```

The Application targets:

```yaml
server: https://kubernetes.default.svc
```

and syncs into `kube-system`. citeturn662409view4

## Cinder credentials

Cinder CSI needs OpenStack credentials, not Kubernetes credentials.

```text
Argo CD
   │
   └── Kubernetes ServiceAccount

Cinder CSI
   │
   └── OpenStack application credential
```

The OpenStack credential is supplied through a Kubernetes Secret containing `cloud.conf`. The secret is deliberately not stored in plaintext in Git. The current Cinder application documentation explicitly calls out the Secret as a prerequisite. citeturn438820view0

## StorageClasses

The reference cloud exposes:

```text
SSD
HDD
__DEFAULT__
```

The Kubernetes policy is:

```text
cinder-ssd
    → SSD
    → Kubernetes default

cinder-hdd
    → HDD

cinder-default
    → no explicit volume type
    → Cinder chooses its configured default
```

StorageClasses live under the Git-managed application resources.

## Sync model

The project currently uses automated synchronization with pruning and self-healing for the Cinder Application. citeturn662409view4

The intended lifecycle is:

```text
Git change
   ↓
Argo detects drift
   ↓
render desired state
   ↓
sync
   ↓
Kubernetes converges
```

## What should move here next

After Cinder:

```text
Prometheus / Grafana
Slurm integration services that actually run in K8s, where applicable
Hermes research deployment
Heretic components
JupyterHub
Astro
research applications
```

Slurm itself remains outside Argo because the scheduler and compute nodes are not Kubernetes workloads.

## What should not move here

Do not put these under Argo CD:

```text
Terraform cloud infrastructure
Rocky Linux host configuration
OpenStack VM lifecycle
Slurm compute-node operating systems
host firewall configuration
WireGuard host configuration
```

Those remain with Terraform and Ansible.

## App-of-Apps / ApplicationSet

The current Cinder Application is intentionally applied explicitly while the GitOps foundation is being established.

Once several applications exist, a root Application or ApplicationSet can become the single GitOps entry point:

```text
root application
      │
      ├── Cinder CSI
      ├── Prometheus
      ├── Grafana
      ├── JupyterHub
      ├── Hermes
      └── Astro
```

That should be introduced once there is enough application inventory to justify it, rather than adding another abstraction before the first few applications are proven.

## Teaching objective

Argo CD should demonstrate:

```text
Git
  = desired application state

Argo CD
  = reconciliation engine

Kubernetes
  = runtime platform

Helm
  = packaging mechanism

Secrets
  = separate trust domain
```

This is the key architectural transition point of the project.
