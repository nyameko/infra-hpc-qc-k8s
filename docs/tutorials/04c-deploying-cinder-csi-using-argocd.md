# Tutorial 4c — Deploying Cinder CSI through Argo CD

## Objective

Deploy OpenStack Cinder storage into Kubernetes using Argo CD and establish the canonical pattern for installing infrastructure applications in `infra-hpc-qc-k8s`.

By the end of this tutorial:

```text
GitHub
  │
  ▼
Argo CD root Application
  │
  ▼
cinder-csi Application
  │
  ├── Cinder CSI Helm chart
  ├── repository-managed Kubernetes resources
  └── SealedSecret
        │
        ▼
   cinder-csi-cloud-config
        │
        ▼
    Cinder CSI driver
        │
        ▼
 Kubernetes StorageClasses
```

This tutorial is deliberately important beyond Cinder itself.

**Cinder is the reference implementation for how this repository deploys applications through Argo CD.**

The same architecture will later be used for Prometheus, Grafana, Wazuh, JupyterHub, Hermes and other Kubernetes applications.

---

## 1. What problem are we solving?

Kubernetes needs a storage provider in order to dynamically provision persistent volumes.

Our OpenStack environment provides Cinder, but Kubernetes does not automatically know how to talk to it.

The Cinder CSI driver provides the integration between the two:

```text
Kubernetes PVC
      │
      ▼
 CSI Cinder driver
      │
      ▼
 OpenStack Cinder
      │
      ▼
 Cinder volume
```

The upstream Cinder CSI project describes the driver as a CSI-compliant driver for managing the lifecycle of OpenStack Cinder volumes from a container orchestrator. It supports dynamic provisioning, topology, expansion, snapshots and other CSI capabilities.

---

## 2. Why Cinder is deployed through Argo CD

At this point in the platform bootstrap:

```text
Terraform
    │
    ▼
OpenStack infrastructure

Ansible
    │
    ▼
Rocky Linux
Kubernetes prerequisites
kubeadm
Argo CD
Sealed Secrets

Argo CD
    │
    ▼
Kubernetes applications
```

Cinder CSI belongs below the infrastructure/application boundary.

Ansible establishes the platform.

Argo CD owns the long-lived Kubernetes application.

Therefore:

```text
Ansible
    └── install/bootstrap Argo CD

Argo CD
    └── deploy Cinder CSI
```

This prevents Ansible from becoming a giant Kubernetes application installer.

---

## 3. Why we chose this structure

The repository intentionally separates three things:

```text
argocd/applications/
    Application definitions

argocd/resources/
    Kubernetes resources belonging to applications

secrets/
    encrypted application secrets
```

For Cinder:

```text
argocd/
├── applications/
│   └── cinder-csi.yml
│
└── resources/
    └── cinder-csi/
        └── storageclasses.yaml

secrets/
└── cinder/
    └── cinder-sealed.yaml
```

This gives each application a predictable shape.

```text
Application
    │
    ├── upstream software
    ├── repository-owned resources
    └── encrypted configuration
```

---

## 4. The Argo CD Application

The Cinder Application is defined in:

```text
argocd/applications/cinder-csi.yml
```

The Application points at the Kubernetes cluster:

```yaml
destination:
  server: https://kubernetes.default.svc
  namespace: kube-system
```

This is important.

The root Application's destination is not inherited by child Applications.

Every child Application must declare its own destination.

The Cinder CSI components therefore belong in:

```text
kube-system
```

while the Argo `Application` object itself lives in:

```text
argocd
```

---

## 5. Source one: the upstream Helm chart

The first source is the upstream Cinder CSI Helm repository:

```yaml
- repoURL: https://kubernetes.github.io/cloud-provider-openstack
  chart: openstack-cinder-csi
  targetRevision: 2.36.0
```

This allows Argo CD to install the vendor-maintained CSI driver rather than requiring us to copy its manifests into the repository.

This is a useful general principle:

> Use upstream packaging for upstream software; keep repository-owned configuration in our repository.

---

## 6. Source two: repository-owned Kubernetes resources

The second source is:

```yaml
- repoURL: https://github.com/nyameko/infra-hpc-qc-k8s.git
  targetRevision: main
  path: argocd/resources/cinder-csi
```

This contains our Kubernetes configuration.

For Cinder, this currently provides:

```text
storageclasses.yaml
```

The StorageClasses expose the Cinder backend using the Kubernetes storage abstraction.

We deliberately do not ask the Helm chart to create the StorageClasses:

```yaml
storageClass:
  enabled: false
```

That keeps vendor installation and repository-owned policy separate.

---

## 7. Source three: encrypted credentials

The third source is:

```yaml
- repoURL: https://github.com/nyameko/infra-hpc-qc-k8s.git
  targetRevision: main
  path: secrets/cinder
```

This directory contains:

```text
cinder-sealed.yaml
```

The file is a Bitnami SealedSecret.

Argo applies the SealedSecret.

The Sealed Secrets controller decrypts it inside Kubernetes.

The result is:

```text
SealedSecret
    │
    ▼
Sealed Secrets controller
    │
    ▼
Secret/cinder-csi-cloud-config
```

The Cinder CSI Helm configuration refers to:

```yaml
secret:
  enabled: true
  create: false
  name: cinder-csi-cloud-config
  filename: cloud.conf
```

Therefore the Helm chart consumes a Secret which is managed separately by Sealed Secrets.

The upstream Cinder CSI documentation supports supplying `cloud.conf` from a Kubernetes Secret and documents the corresponding controller/node plugin deployment model.

---

## 8. Why we removed `values.yaml`

An earlier version stored Helm values separately:

```text
argocd/resources/cinder-csi/values.yaml
```

We removed that duplication.

The final Application contains:

```yaml
helm:
  valuesObject:
    ...
```

This means the Cinder deployment configuration is visible directly in the Application definition.

There is now one source of truth for the Helm configuration:

```text
argocd/applications/cinder-csi.yml
```

while Kubernetes resources remain in:

```text
argocd/resources/cinder-csi/
```

This avoids a situation where a student needs to determine whether the application's configuration lives in:

```text
Application
values.yaml
valuesObject
Helm defaults
```

---

## 9. Automated synchronization

The final Cinder Application uses:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

Therefore:

```text
git commit
    │
    ▼
git push
    │
    ▼
GitHub
    │
    ▼
Argo CD
    │
    ▼
Cinder reconciled automatically
```

`prune: true` means resources removed from the desired configuration can also be removed from the cluster.

`selfHeal: true` means Argo attempts to restore resources when their live state differs from the desired Git state.

This is the GitOps contract we want applications to follow.

---

## 10. The failures that led to the final design

This application was deliberately useful because it exposed several architectural mistakes.

### 10.1 Child Application without a destination

The first Cinder Application did not specify:

```yaml
spec:
  destination:
```

Argo therefore rejected the child Application:

```text
Application.argoproj.io "cinder-csi" is invalid:
spec.destination: Required value
```

The root Application itself was healthy, but the child Application could not become valid.

This established an important rule:

> Every Argo Application is a complete Kubernetes object and must contain its own destination.

---

### 10.2 Referencing a nonexistent resources directory

An early version referenced:

```text
argocd/applications/cinder-csi/resources
```

but that directory did not exist.

The actual resource directory was:

```text
argocd/resources/cinder-csi
```

The final structure avoids nesting application resources underneath the Application definition.

```text
applications/
resources/
secrets/
```

remain distinct concepts.

---

### 10.3 Kustomize was removed

We originally experimented with Kustomize to build the application tree.

It was unnecessary.

The root Application now points directly at:

```text
argocd/applications
```

as a normal Argo CD directory.

There is no:

```text
kustomization.yaml
```

for the application registry.

---

### 10.4 ApplicationSet was removed

We also experimented with ApplicationSet.

That introduced unnecessary abstraction and made the application registration model harder to understand.

The final model is explicit:

```text
argocd/applications/
    cinder-csi.yml
    prometheus.yml
    grafana.yml
    ...
```

One file means one Argo Application.

This is intentionally boring.

That is a feature.

---

## 11. Verifying the Argo deployment

Once the Git commit reaches GitHub:

```bash
kubectl -n argocd get applications
```

Expected:

```text
NAME         SYNC STATUS   HEALTH STATUS
cinder-csi   Synced        Healthy
root         Synced        Healthy
```

Inspect the resources managed by Cinder:

```bash
kubectl -n argocd get application cinder-csi \
  -o jsonpath='{range .status.resources[*]}{.kind}{" | "}{.namespace}{" | "}{.name}{" | "}{.status}{" | "}{.health.status}{"\n"}{end}'
```

Expected resource categories include:

```text
ServiceAccount
DaemonSet
Deployment
SealedSecret
ClusterRole
ClusterRoleBinding
CSIDriver
StorageClass
```

---

## 12. Verify the Secret

The SealedSecret should exist:

```bash
kubectl -n kube-system get sealedsecret
```

Expected:

```text
cinder-csi-cloud-config
```

The decrypted Secret should also exist:

```bash
kubectl -n kube-system get secret cinder-csi-cloud-config
```

Expected:

```text
NAME                     TYPE     DATA
cinder-csi-cloud-config  Opaque   1
```

This proves the complete secret path is functioning:

```text
Git
 │
 ├── encrypted SealedSecret
 │
 ▼
Argo CD
 │
 ▼
Sealed Secrets controller
 │
 ▼
Kubernetes Secret
```

---

## 13. Verify the CSI driver

```bash
kubectl get csidriver
```

Expected:

```text
cinder.csi.openstack.org
```

This is Kubernetes' registration of the Cinder CSI driver.

---

## 14. Verify the StorageClasses

```bash
kubectl get storageclass
```

Expected:

```text
cinder-ssd (default)
cinder-hdd
cinder-default
```

The default class is:

```text
cinder-ssd
```

This is a Kubernetes default and should not be confused with the default Cinder volume type in OpenStack.

The Kubernetes application only needs to know about the StorageClass abstraction.

That allows the same workload to work with different backends:

```text
OpenStack
    → Cinder CSI

AWS
    → EBS CSI

Azure
    → Azure Disk CSI

GCP
    → Persistent Disk CSI

Ceph
    → Ceph CSI
```

The workload asks for:

```yaml
storageClassName: cinder-ssd
```

rather than embedding OpenStack-specific API calls in the application.

---

## 15. Verify the Cinder CSI pods

```bash
kubectl -n kube-system get pods | grep -i cinder
```

A healthy deployment should show:

```text
controllerplugin    6/6 Running
nodeplugin           3/3 Running
```

The controller consists of the Cinder CSI driver plus CSI sidecars responsible for provisioning, attachment, resizing, snapshots and related operations.

The Cinder CSI project's deployment documentation shows the expected controller/node plugin architecture.

---

## 16. Understanding `Progressing` versus `Healthy`

Argo does not simply ask whether the Application object exists.

It evaluates the health of its managed resources.

For example:

```text
controller Deployment
        │
        ▼
controller Pod
        │
        ├── container 1
        ├── container 2
        ├── container 3
        ├── container 4
        ├── container 5
        └── container 6
```

Suppose one container crashes:

```text
5/6 Ready
```

The Deployment may temporarily become unavailable.

Argo therefore reports:

```text
Progressing
```

When Kubernetes restarts the failed container and the pod becomes fully ready:

```text
6/6 Ready
```

Argo can return to:

```text
Healthy
```

If the same container fails again, the Application transitions back.

Therefore:

```text
Healthy
   ↕
Progressing
```

can be evidence of a **flapping workload**, not a flapping GitOps controller.

The diagnostic command is:

```bash
kubectl -n kube-system get pod <controller-pod> \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}{" | ready="}{.ready}{" | restarts="}{.restartCount}{" | state="}{.state}{"\n"}{end}'
```

Then inspect the failed container:

```bash
kubectl -n kube-system logs <controller-pod> \
  -c <failing-container> \
  --previous
```

Always diagnose the container before changing the Argo Application.

---

## 17. The actual storage test

A green CSI deployment is not sufficient.

The real test is:

```text
PVC
 ↓
StorageClass
 ↓
CSI provisioner
 ↓
Cinder
 ↓
Cinder volume
 ↓
PV
 ↓
Pod
 ↓
filesystem
```

Create a small test PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim

metadata:
  name: cinder-test

spec:
  accessModes:
    - ReadWriteOnce

  storageClassName: cinder-ssd

  resources:
    requests:
      storage: 1Gi
```

Then create a test pod:

```yaml
apiVersion: v1
kind: Pod

metadata:
  name: cinder-test

spec:
  containers:
    - name: test
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "Cinder CSI works" > /data/test.txt
          sleep 3600

      volumeMounts:
        - name: data
          mountPath: /data

  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: cinder-test
```

Then check:

```bash
kubectl get pvc
kubectl get pv
kubectl get pod cinder-test
```

The PVC should become:

```text
Bound
```

The upstream Cinder CSI documentation uses this same fundamental dynamic-provisioning flow: StorageClass → PVC → Pod, resulting in a Cinder volume being consumed by the workload.

---

## 18. Verify the volume in OpenStack

After the PVC becomes bound:

```bash
openstack volume list
```

The Kubernetes PVC should correspond to an actual Cinder volume.

This is the first genuine end-to-end platform test.

We are no longer testing merely:

```text
"Kubernetes says CSI is installed."
```

We are testing:

```text
"Kubernetes can consume OpenStack storage."
```

---

## 19. Test persistence

The definitive test is to destroy the pod without destroying the PVC.

First:

```bash
kubectl exec cinder-test -- cat /data/test.txt
```

Expected:

```text
Cinder CSI works
```

Delete the pod:

```bash
kubectl delete pod cinder-test
```

Recreate it with the same PVC.

Then:

```bash
kubectl exec cinder-test -- cat /data/test.txt
```

Expected:

```text
Cinder CSI works
```

The important chain is therefore:

```text
Pod destroyed
   ↓
PVC remains
   ↓
PV remains
   ↓
Cinder volume remains
   ↓
new pod attaches volume
   ↓
data remains
```

That demonstrates persistence rather than merely successful provisioning.

---

## 20. Cinder StorageClass policy

The cluster currently exposes:

```text
cinder-ssd
cinder-hdd
cinder-default
```

This provides a useful storage abstraction:

```text
cinder-ssd
    → performance-oriented storage

cinder-hdd
    → capacity-oriented storage

cinder-default
    → provider-selected Cinder backend
```

The important point is that applications request storage characteristics rather than directly managing Cinder.

Later, additional StorageClasses can be introduced for:

```text
encrypted volumes
high-performance volumes
multiattach
special availability zones
retained research datasets
```

The Cinder CSI driver supports topology-aware provisioning and other storage features documented by the upstream project.

---

## 21. Final architecture

The finished application now follows this contract:

```text
                    GitHub
                       │
                       ▼
                 Argo CD root
                       │
                       ▼
              cinder-csi Application
                       │
          ┌────────────┼─────────────┐
          │            │             │
          ▼            ▼             ▼
        Helm       Resources      SealedSecret
          │            │             │
          ▼            ▼             ▼
     CSI driver   StorageClasses   Kubernetes Secret
          │            │             │
          └────────────┼─────────────┘
                       ▼
               Cinder CSI driver
                       │
                       ▼
                 OpenStack Cinder
```

---

## 22. The repository pattern established by Cinder

Cinder establishes the template for future Argo applications:

```text
argocd/
├── applications/
│   ├── cinder-csi.yml
│   ├── prometheus.yml
│   ├── grafana.yml
│   ├── wazuh.yml
│   ├── jupyterhub.yml
│   └── hermes.yml
│
└── resources/
    ├── cinder-csi/
    ├── prometheus/
    ├── grafana/
    ├── wazuh/
    ├── jupyterhub/
    └── hermes/

secrets/
├── cinder/
├── prometheus/
├── grafana/
├── wazuh/
├── jupyterhub/
└── hermes/
```

Each application therefore has three concerns:

```text
Application definition
        +
Kubernetes resources
        +
Encrypted secrets
```

Ansible does not install the application.

Kustomize does not assemble the application.

ApplicationSet does not generate the application.

KSOPS does not decrypt the application.

The Git repository describes the desired state, and Argo CD reconciles it.

---

## 23. What this tutorial proves

When this tutorial succeeds, we have demonstrated all of the following:

```text
✓ Argo CD root Application works

✓ Child Applications can be registered from a flat directory

✓ Argo CD multi-source Applications work

✓ Helm charts can be consumed directly

✓ repository-owned Kubernetes resources can be layered alongside Helm

✓ Sealed Secrets integrate with Argo CD

✓ secrets can remain encrypted in Git

✓ Kubernetes can consume OpenStack Cinder

✓ StorageClasses expose provider-neutral Kubernetes storage

✓ dynamic provisioning works

✓ Cinder volumes can be consumed by workloads

✓ persistent data survives pod replacement
```

This is the point at which the platform moves from:

```text
"we have Kubernetes"
```

to:

```text
"we have a reproducible Kubernetes platform capable of consuming
OpenStack infrastructure through declarative GitOps."
```

---

## 24. Next step

Once the Cinder controller itself is completely healthy and the PVC persistence test passes, **do not redesign this pattern again**.

The following applications should use the same structure:

```text
4d  → Prometheus
4e  → Grafana
4f  → Wazuh
4g  → JupyterHub
4h  → Hermes
```

Cinder is the template.

Everything after this should become progressively boring.