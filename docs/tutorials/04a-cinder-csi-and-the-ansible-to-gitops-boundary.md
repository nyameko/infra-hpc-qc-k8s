# Tutorial 4A — Cinder CSI, Debugging the Boundary, and the Ansible → GitOps Transition

> Annexure to Tutorial 4: Kubernetes & Platform Services

## Purpose

This annexure records the Cinder CSI implementation journey in full because the failed approaches were useful engineering lessons. The goal is not merely to show the final configuration, but to explain why the architecture changed.

## 1. Starting point

The Kubernetes foundation was already working:

- Kubernetes 1.36.4
- 3 control planes
- 3 workers
- HAProxy API endpoint `10.51.0.100:6443`
- containerd 2.3.4
- Cilium 1.20.1
- Cilium connectivity test: 82/82 tests successful, 780 actions, 55 tests skipped, 1 scenario skipped

The next platform dependency was persistent storage through OpenStack Cinder.

## 2. Discovering the available storage

OpenStack exposed three public volume types:

- `SSD` — Ceph SSD-backed volume type
- `HDD` — Ceph HDD-backed volume type
- `__DEFAULT__` — the configured OpenStack default volume type

The Cinder service listing returned HTTP 403 because the project's OpenStack policy does not permit `volume_extension:services:index`. That is an authorization limitation of the current credentials, not proof that Cinder is unhealthy.

## 3. StorageClass design

Three Kubernetes StorageClasses provide a useful teaching model:

| StorageClass | Cinder type | Kubernetes default | Meaning |
|---|---|---:|---|
| `cinder-ssd` | `SSD` | yes | performance-oriented storage |
| `cinder-hdd` | `HDD` | no | capacity-oriented storage |
| `cinder-default` | omitted | no | let Cinder select its configured default |

`cinder-default` intentionally does not pass a literal `__DEFAULT__` type. It demonstrates the difference between a Kubernetes default StorageClass and the OpenStack/Cinder default volume type.

All three use `WaitForFirstConsumer`, `allowVolumeExpansion: true`, and `Delete` reclaim policy for the initial teaching deployment.

The upstream Cinder CSI driver documents `type` as the StorageClass parameter containing a Cinder volume type name or ID, and supports dynamic provisioning, topology, expansion, snapshots, and cloning.

## 4. First implementation: Ansible + Helm

The initial implementation attempted to use Ansible to:

1. install Helm on a control-plane node;
2. create the Kubernetes namespace;
3. create the Cinder credentials Secret;
4. install the Cinder CSI Helm chart;
5. create StorageClasses;
6. deploy a validation workload;
7. test persistence and expansion.

This looked reasonable at first, but exposed an increasingly awkward dependency chain.

## 5. Credentials: temporary `cloud.conf`

The first design created a temporary `cloud.conf` file and then used that file to create the Kubernetes Secret.

That was unnecessary. The CSI chart accepts an existing Kubernetes Secret containing `cloud.conf`, so Ansible can create the Secret directly from private variables without ever writing a temporary credential file.

The important distinction is:

`cloud.conf` is still the configuration format consumed by the CSI driver, but it does not need to exist as a temporary Ansible file. It can exist only as data in the Kubernetes Secret.

## 6. Kubernetes administration from Ansible

A second problem appeared when `kubernetes.core.k8s` tried to use `/home/nyameko/.kube/config` on `localhost`.

The cause was architectural: the play targeted `localhost`, so the Kubernetes modules executed on the workstation rather than on a Kubernetes control-plane node.

The repository's Kubernetes bootstrap already creates `/home/<admin-user>/.kube/config` from `/etc/kubernetes/admin.conf` on the bootstrap control plane. Therefore a control-plane host can act as the temporary Ansible execution host for bootstrap operations without requiring the workstation's kubeconfig.

## 7. Helm installation incident

The initial Helm RPM repository pointed at `baltocdn.com` and failed TLS verification. The repository was removed.

Important lesson: do not disable certificate verification to make a package source work. The correct response is to stop using the obsolete source and use a supported distribution method.

For this project Helm can be installed from Rocky/EPEL:

```bash
dnf install epel-release
dnf install helm
```

## 8. Privilege escalation incident

The EPEL installation initially failed because Ansible was not running the package task as root:

`SQLite error on /var/lib/dnf/history.sqlite: attempt to write a readonly database`

Adding `become: true` fixed the package-management operation.

This exposed another undesirable coupling: a Kubernetes application role was now taking responsibility for OS package installation and root privileges.

## 9. Python Kubernetes client incident

After Helm installation, `kubernetes.core.k8s` failed because the remote Python interpreter (`/usr/bin/python3.9`) did not have the Python `kubernetes` package installed.

This was another dependency that existed solely because Ansible was being used as a Kubernetes application deployment engine.

## 10. `admin.conf` permission incident

Using `/etc/kubernetes/admin.conf` directly then failed with permission denied for the normal user.

The root cause was correct Kubernetes security: `admin.conf` is root-owned and sensitive. The cleaner bootstrap path is to use the administrator kubeconfig already copied by the Kubernetes bootstrap role into the administrator user's home directory.

## 11. The architectural conclusion

None of these failures meant the Kubernetes cluster was not real or correctly designed. They showed that application lifecycle was being placed in the wrong automation layer.

The resulting ownership model is:

```text
Terraform
    ↓
infrastructure

Ansible
    ↓
OS + base infrastructure

kubeadm
    ↓
Kubernetes bootstrap

Cilium
    ↓
networking

Argo CD
    ↓
Kubernetes application lifecycle
```

Cinder CSI therefore becomes the first application deployed through Argo CD.

## 12. Argo CD does not receive a kubeconfig

This is an important misconception to avoid.

For an application whose destination is the same cluster in which Argo CD runs, the Application can use:

```yaml
spec:
  destination:
    server: https://kubernetes.default.svc
```

Argo CD's application controller authenticates to that API from inside the cluster using its ServiceAccount and RBAC. A kubeconfig is not copied into Argo CD.

For external clusters, Argo CD stores cluster connection credentials as a Kubernetes Secret in the `argocd` namespace. That is a different use case.

## 13. Argo CD and Cinder credentials are different

Cinder CSI needs OpenStack authentication information. Those are not Argo CD's Kubernetes credentials.

The clean flow is:

```text
OpenStack application credential
          ↓
Kubernetes Secret
          ↓
Cinder CSI
```

while Argo CD separately manages the Kubernetes objects:

```text
Git
 ↓
Argo CD
 ↓
Cinder CSI Helm release
 ↓
StorageClasses
```

The Cinder CSI chart supports an existing Secret, so Git does not need to contain the OpenStack secret value.

## 14. First GitOps implementation

The Argo Application points at the upstream Cinder CSI chart repository:

```text
https://kubernetes.github.io/cloud-provider-openstack
```

and deploys:

```text
openstack-cinder-csi
```

The chart's built-in StorageClass creation is disabled. StorageClasses are kept as explicit Git-managed resources.

## 15. Secret strategy

For the first working deployment, the OpenStack application credential Secret can be seeded out-of-band, for example with an Ansible/manual bootstrap step stored outside Git.

That is intentionally a temporary bootstrap boundary.

The long-term design should be one of:

- External Secrets + an external secret store;
- SOPS-encrypted manifests with an appropriate key-management workflow;
- another equivalent GitOps-compatible secret manager.

Do not put the raw application credential secret into `values.yaml` or an Argo `Application` manifest.

## 16. Why the failed implementation was valuable

The sequence taught several important engineering lessons:

- OpenStack credentials are not Kubernetes credentials.
- A CSI driver's `cloud.conf` does not require a temporary local file.
- Kubernetes control-plane kubeconfigs are sensitive and should not casually be exposed to automation.
- Ansible package tasks need appropriate privilege, but application deployment should not automatically inherit root ownership.
- `kubernetes.core` introduces a Python client dependency on the execution host.
- Helm is useful for packaging, but it does not need to become an Ansible-owned application lifecycle mechanism.
- Argo CD is the better long-lived reconciler for Kubernetes applications.
- A bootstrap tool and an application lifecycle tool do not have to be the same tool.

## 17. Verification model

The eventual Cinder CSI verification should remain deterministic and Git-managed:

```text
PVC (SSD)
PVC (HDD)
PVC (DEFAULT)
      ↓
provision
      ↓
attach
      ↓
mount
      ↓
write known marker
      ↓
recreate pod
      ↓
verify marker survived
      ↓
expand SSD PVC
      ↓
verify capacity
      ↓
cleanup
```

The test should become a Kubernetes Job or other Git-managed validation resource once the GitOps layer is active. This keeps deployment and verification reproducible.

## 18. Generalization beyond OpenStack

The platform should not make Kubernetes depend conceptually on OpenStack.

OpenStack is the current infrastructure adapter:

```text
Provider adapter
      ↓
Nova / Neutron / Cinder
      ↓
Kubernetes nodes + storage
```

On another cloud or bare metal, the platform layer should stay the same where possible:

```text
Terraform provider / infrastructure adapter
             ↓
       Kubernetes cluster
             ↓
          Cilium
             ↓
          Argo CD
             ↓
       platform services
```

Cinder CSI is therefore an OpenStack-specific storage implementation behind the generic Kubernetes CSI abstraction. Another environment would substitute its own CSI driver and StorageClasses rather than modifying the application layer.
