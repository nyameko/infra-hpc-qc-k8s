# Kubernetes

The `kubernetes/` directory contains **Kubernetes-native resource definitions and provider-facing cluster resources** that are kept separate from Ansible host configuration and Terraform cloud infrastructure.

The directory is intentionally small at this stage. Kubernetes itself is bootstrapped by kubeadm, networked by Cilium, and increasingly managed at the application layer by Argo CD.

## Ownership model

```text
Terraform
    ↓
OpenStack infrastructure

Ansible
    ↓
host prerequisites + kubeadm bootstrap

Cilium
    ↓
cluster networking

Argo CD
    ↓
application lifecycle

Kubernetes API
    ↓
runtime state
```

## Current layout

```text
kubernetes/
└── cinder-csi/
    └── storageclasses.yaml
```

The current repository exposes the Cinder StorageClass definition here. citeturn438820view1

The matching Argo CD Application consumes this directory as its Git source. citeturn662409view4

## Cluster bootstrap

The reference cluster is:

```text
                    HAProxy VIP
                  10.51.0.100:6443
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
          cp-01          cp-02          cp-03
            │              │              │
            └──────────────┼──────────────┘
                           │
                        Cilium
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
        worker-01      worker-02      worker-03
```

Kubernetes is pinned to the `1.36` minor line in the reference implementation.

## Cilium

Cilium provides the cluster CNI and network policy layer.

The current baseline intentionally leaves advanced features for later exercises, including:

```text
Hubble Relay / deeper observability
kube-proxy replacement
eBPF service-routing experiments
ClusterMesh
advanced policy design
```

The current cluster has passed:

```text
82 tests
780 actions
0 failures
```

That is the network-substrate acceptance milestone.

## Persistent storage: Cinder CSI

The current OpenStack provider exposes three volume types:

```text
SSD
HDD
__DEFAULT__
```

The Kubernetes storage policy maps them as:

```text
cinder-ssd
    → type: SSD
    → default StorageClass

cinder-hdd
    → type: HDD

cinder-default
    → omit type
    → let Cinder select its configured default
```

The actual Cinder CSI driver is deployed through Argo CD, not directly from this directory. The `kubernetes/cinder-csi/` definition is therefore **part of the desired-state input**, not a separate imperative deployment mechanism.

## Why Cinder YAML remains in Git

Although Argo CD is the controller, the desired state still has to live somewhere.

That is what this directory provides:

```text
Git
  ↓
kubernetes/cinder-csi/storageclasses.yaml
  ↓
Argo CD
  ↓
Kubernetes API
```

So the file should **not** be deleted merely because the resource is now Argo-managed.

## What belongs here

Provider-facing Kubernetes resources that are genuinely useful as Git-managed desired state can live here, for example:

```text
StorageClasses
cluster-level Kubernetes resources
provider integration configuration
platform-level resource definitions
```

The directory should not become a dumping ground for every application manifest. Application-specific resources should normally live under their Argo CD application directory or an application repository structure.

## What does not belong here

Do not use this directory as the place to manage:

```text
Terraform infrastructure
Rocky Linux packages
systemd services
host firewalls
OpenStack VMs
Slurm host configuration
```

Those belong to Terraform or Ansible.

## Secrets

Never place live credentials here.

For the Cinder CSI deployment:

```text
OpenStack application credential
        ↓
secret-management/bootstrap path
        ↓
Kubernetes Secret
        ↓
Cinder CSI
```

The Secret should not contain plaintext credentials in Git. The current Cinder application documentation explicitly treats the Secret as a prerequisite supplied separately from the Git application definition. citeturn438820view0

## Provider portability

The storage API should remain portable even though the current implementation is Cinder-specific.

```text
OpenStack
  Cinder CSI

AWS
  EBS / EFS depending workload

Azure
  Azure Disk / Files

GCP
  Persistent Disk / Filestore

Bare metal / Ceph
  Ceph CSI / local storage
```

The application should depend on a Kubernetes StorageClass contract, while the provider adapter implements the storage backend.

## Teaching objective

This directory demonstrates an important distinction:

```text
Kubernetes desired state
        ≠
Kubernetes control loop
```

Git contains the declaration. Argo CD reconciles it. Kubernetes implements it.
