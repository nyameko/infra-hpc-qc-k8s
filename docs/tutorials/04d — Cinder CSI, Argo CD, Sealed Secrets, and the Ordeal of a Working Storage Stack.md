# Tutorial 4c — Cinder CSI, Argo CD, Sealed Secrets, and the Ordeal of a Working Storage Stack

## Objective

Deploy OpenStack Cinder storage into Kubernetes using Argo CD and establish the repository's canonical pattern for deploying Kubernetes applications.

This tutorial deliberately documents both the **final architecture** and the debugging journey required to get there.

The goal is not merely:

> “Install Cinder CSI.”

The goal is to understand how several independently correct components can still fail as a system when their configuration contracts do not line up.

By the end of this tutorial, the expected architecture is:

```text
GitHub
   │
   ▼
Argo CD root Application
   │
   ▼
cinder-csi Application
   │
   ├── Upstream Cinder CSI Helm chart
   ├── Repository-owned Kubernetes resources
   └── SealedSecret
          │
          ▼
   Kubernetes Secret
          │
          ▼
     Cinder CSI
          │
          ▼
    OpenStack Cinder
```

The completed storage path is:

```text
Kubernetes PVC
      │
      ▼
StorageClass
      │
      ▼
Cinder CSI
      │
      ▼
OpenStack Cinder
      │
      ▼
Persistent Volume
      │
      ▼
Pod
```

---

# 1. Why this tutorial matters

Cinder CSI is deceptively simple.

At first glance the task appears to be:

```text
install Helm chart
+
provide OpenStack credentials
=
working storage
```

In reality there are several independent configuration boundaries:

```text
Argo CD
   ↓
Helm
   ↓
Deployment
   ↓
Secret
   ↓
cloud.conf
   ↓
OpenStack Keystone
   ↓
Cinder
```

A mistake at any one of these boundaries can produce symptoms somewhere else.

For example:

```text
wrong Secret key
        ↓
missing cloud.conf
        ↓
CSI plugin exits
        ↓
CSI socket disappears
        ↓
sidecars cannot connect
        ↓
controller becomes unhealthy
        ↓
Argo reports Progressing
```

The final Argo status tells us that something is wrong, but not necessarily where the original mistake occurred.

This tutorial therefore treats the deployment as a chain of contracts that must all agree.

---

# 2. Architectural boundary

The platform uses the following ownership model:

```text
Terraform
    ↓
OpenStack infrastructure

Ansible
    ↓
OS configuration
Kubernetes bootstrap
Argo CD bootstrap
Sealed Secrets bootstrap

Argo CD
    ↓
Kubernetes application lifecycle

Slurm
    ↓
HPC workload scheduling
```

Cinder CSI belongs to Argo CD.

Ansible does not install the Cinder CSI application.

The division is intentional:

```text
Ansible
    └── establishes the platform

Argo CD
    └── manages the platform applications
```

This prevents Ansible from becoming a giant imperative Kubernetes installer.

---

# 3. Repository structure

The canonical structure is:

```text
argocd/
├── applications/
│   └── cinder-csi.yml
│
├── bootstrap/
│   └── root-application.yaml
│
└── resources/
    └── cinder-csi/
        └── storageclasses.yaml

secrets/
└── cinder/
    └── cinder-sealed.yaml
```

Each part has a different responsibility.

### `argocd/applications/`

Contains Argo CD `Application` objects.

### `argocd/resources/`

Contains Kubernetes resources owned by our deployment.

### `secrets/`

Contains encrypted SealedSecrets.

This structure is deliberately explicit.

There is no Kustomize layer.

There is no ApplicationSet.

There is no KSOPS integration.

---

# 4. The root Application

The root Application points at:

```text
argocd/applications
```

as a normal Argo CD Directory source.

The root does not attempt to install Cinder directly.

Instead:

```text
root
  │
  └── discovers
        │
        ▼
    cinder-csi.yml
        │
        ▼
    cinder-csi Application
```

This is the repository's App-of-Apps pattern.

Because the directory is flat, each file represents one application.

For example:

```text
argocd/applications/

cinder-csi.yml
prometheus.yml
grafana.yml
wazuh.yml
jupyterhub.yml
hermes.yml
```

This is intentionally simple.

---

# 5. Why we did not use Kustomize

An earlier design experimented with Kustomize for the application tree.

That added abstraction without solving a problem we actually had.

The root only needs to discover Application manifests.

A normal Argo Directory source is sufficient.

Therefore:

```text
argocd/applications/
    *.yml
```

is preferable to:

```text
argocd/applications/
    kustomization.yaml
```

for this particular registry.

This keeps the application registration layer boring and predictable.

---

# 6. Why we did not use ApplicationSet

ApplicationSet was also evaluated.

It was unnecessary for this repository.

We explicitly want:

```text
one application
=
one Application manifest
```

rather than introducing a generator to create those manifests.

This is especially useful for teaching.

Students can open:

```text
argocd/applications/cinder-csi.yml
```

and immediately understand which Application is being deployed.

---

# 7. The Cinder Application

The final Cinder Application has three sources.

```text
cinder-csi
   │
   ├── Helm
   │
   ├── Git resources
   │
   └── Git secrets
```

Conceptually:

```yaml
spec:
  project: default

  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system

  sources:
    - Helm chart
    - repository resources
    - SealedSecret
```

The destination is mandatory.

This produced one of the first failures in our deployment.

---

# 8. Failure #1 — Application without a destination

The first Cinder Application omitted:

```yaml
spec:
  destination:
```

Argo rejected it with:

```text
Application.argoproj.io "cinder-csi" is invalid:
spec.destination: Required value
```

This teaches an important rule:

> The root Application's destination does not become the destination of a child Application.

Every Application is a complete Kubernetes object.

Therefore every child Application must declare:

```yaml
destination:
  server: https://kubernetes.default.svc
  namespace: kube-system
```

---

# 9. Multi-source Cinder Application

The final Cinder application consumes:

## Source 1 — upstream Helm chart

```yaml
- repoURL: https://kubernetes.github.io/cloud-provider-openstack
  chart: openstack-cinder-csi
  targetRevision: 2.36.0
```

This provides the upstream Cinder CSI software.

## Source 2 — repository-owned resources

```yaml
- repoURL: https://github.com/nyameko/infra-hpc-qc-k8s.git
  targetRevision: main
  path: argocd/resources/cinder-csi
```

This contains our StorageClasses.

## Source 3 — encrypted secrets

```yaml
- repoURL: https://github.com/nyameko/infra-hpc-qc-k8s.git
  targetRevision: main
  path: secrets/cinder
```

This contains the SealedSecret.

The result is:

```text
Helm
  → vendor software

resources/
  → our Kubernetes policy

secrets/
  → our encrypted credentials
```

---

# 10. Failure #2 — Wrong resources path

At one point the Application referenced:

```text
argocd/applications/cinder-csi/resources
```

but the actual resource directory was:

```text
argocd/resources/cinder-csi
```

This distinction matters.

The final repository structure is:

```text
argocd/
├── applications/
├── bootstrap/
└── resources/
```

Applications and resources are separate concepts.

---

# 11. Cinder StorageClasses

The Cinder resource directory contains:

```text
storageclasses.yaml
```

The cluster exposes:

```text
cinder-ssd
cinder-hdd
cinder-default
```

with:

```text
cinder-ssd
    default Kubernetes StorageClass

cinder-hdd
    capacity-oriented storage

cinder-default
    provider-selected Cinder backend
```

The Helm chart is configured not to create StorageClasses itself:

```yaml
storageClass:
  enabled: false
```

This keeps the StorageClass policy under repository control.

---

# 12. Kubernetes storage versus Cinder storage

Kubernetes should not need to know application-specific Cinder APIs.

Instead:

```text
Application
    ↓
PersistentVolumeClaim
    ↓
StorageClass
    ↓
CSI driver
    ↓
Cinder
```

This abstraction is important for portability.

The same application can ultimately use:

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

The application depends on Kubernetes storage semantics, not directly on OpenStack.

---

# 13. Sealed Secrets

The Cinder credentials are stored in Git as:

```text
secrets/cinder/cinder-sealed.yaml
```

The repository never contains the plaintext credentials.

The workflow is:

```text
plaintext Secret
       │
       ▼
    kubeseal
       │
       ▼
 SealedSecret
       │
       ▼
     GitHub
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

The Sealed Secrets private key remains on the cluster.

The workstation only needs the cluster's public certificate.

---

# 14. The public certificate

The cluster has a Sealed Secrets controller keypair.

The public certificate can be stored on the workstation and used offline:

```bash
kubeseal \
  --cert ~/.config/sealed-secrets/cinder-cluster.cert
```

The private sealing key must never be committed to Git.

The same public certificate can be reused when updating this application's secret as long as the cluster's sealing key remains the corresponding key.

The important distinction is:

```text
Sealed Secrets certificate
    ↓
encrypts Kubernetes Secret

OpenStack application credential
    ↓
authenticates to Keystone
```

They are entirely separate credentials.

---

# 15. Creating the Cinder Secret

The plaintext Secret must contain the key expected by the Cinder CSI deployment.

The final form is:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cinder-csi-cloud-config
  namespace: kube-system
type: Opaque

stringData:
  cloud.conf: |
    [Global]
    auth-url = https://pta.sebowa.nicis.ac.za:5000/v3
    application-credential-id = "..."
    application-credential-secret = "..."
    tenant-id = "..."
    region = RegionOne
    os-endpoint-type = "public"
```

The plaintext file should exist only temporarily on the workstation.

For example:

```text
/tmp/cinder-secret/cinder-secret.yaml
```

It must not be placed in the repository.

---

# 16. Failure #3 — `clouds.yaml` versus `cloud.conf`

One of the most confusing stages of the deployment involved two different OpenStack configuration formats.

OpenStack clients commonly use:

```text
clouds.yaml
```

Cinder CSI can also work with that model when configured appropriately.

However, our deployed CSI container was explicitly launched with:

```text
--cloud-config=/etc/config/cloud.conf
```

Therefore our deployment contract is:

```text
Kubernetes Secret
    ↓
cloud.conf
    ↓
/etc/config/cloud.conf
    ↓
cinder-csi-plugin
```

Introducing `clouds.yaml` without also changing the CSI configuration created a mismatch.

This is why a configuration can be syntactically correct but still be operationally wrong.

---

# 17. Failure #4 — `clouds.conf` versus `cloud.conf`

This was an even smaller mistake.

At one point the SealedSecret contained:

```text
clouds.conf
```

while the CSI Deployment expected:

```text
cloud.conf
```

The Kubernetes Secret therefore looked healthy:

```text
DATA  1
```

but the application could not use it.

The pod was looking for:

```text
/etc/config/clouds.yaml
```

or later:

```text
/etc/config/cloud.conf
```

depending on the Deployment revision.

The lesson is:

> Secret existence is not enough. The key name must match the filename/path expected by the container.

---

# 18. Failure #5 — wrong credentials in the correct configuration

After correcting the filename, Keystone returned:

```text
Could not find Application Credential
```

The authentication endpoint itself was reachable:

```text
https://pta.sebowa.nicis.ac.za:5000/v3
```

The failure was therefore not:

```text
DNS
networking
TLS
Kubernetes service account
```

The application credential values were incorrect.

The actual cause was a simple human error:

```text
application-credential-id
application-credential-secret
```

had been swapped.

That single mistake caused the CSI plugin to ask Keystone for a credential that did not exist.

---

# 19. Why this produced such a large failure

The swapped credentials caused:

```text
Cinder CSI
    ↓
Keystone
    ↓
authentication failure
    ↓
cinder-csi-plugin exits
```

The CSI plugin owns the CSI Unix socket:

```text
/csi/csi.sock
```

When the plugin exits:

```text
CSI socket disappears
```

The CSI sidecars then fail:

```text
csi-attacher
csi-provisioner
csi-resizer
csi-snapshotter
```

because they cannot connect to:

```text
/var/lib/csi/sockets/pluginproxy/csi.sock
```

The logs therefore contained:

```text
dial unix /var/lib/csi/sockets/pluginproxy/csi.sock:
connect: no such file or directory
```

Those errors were secondary symptoms.

The root cause was the Cinder plugin failing first.

This is a classic distributed-systems troubleshooting lesson:

> Diagnose the first failed dependency, not necessarily the largest collection of visible errors.

---

# 20. Why Argo alternated between Healthy and Progressing

Argo was not malfunctioning.

The Application was correctly reporting the state of Kubernetes.

The controller would temporarily reach a ready state:

```text
6/6 Running
```

and Argo would report:

```text
Healthy
```

Then a container would crash:

```text
5/6
```

or:

```text
1/6
```

and Argo would report:

```text
Progressing
```

So the apparent oscillation was:

```text
container starts
    ↓
pod becomes ready
    ↓
Argo = Healthy
    ↓
container exits
    ↓
pod becomes unready
    ↓
Argo = Progressing
    ↓
Kubernetes restarts container
    ↓
pod becomes ready
    ↓
Argo = Healthy
```

Argo was merely observing the instability.

---

# 21. Reading the container status correctly

The controller pod contains six containers:

```text
cinder-csi-plugin
csi-attacher
csi-provisioner
csi-resizer
csi-snapshotter
liveness-probe
```

A command such as:

```bash
kubectl -n kube-system get pod <controller-pod> \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}{" | ready="}{.ready}{" | restarts="}{.restartCount}{" | state="}{.state}{"\n"}{end}'
```

allows us to identify which container is actually failing.

That distinction is crucial.

For example:

```text
cinder-csi-plugin      exit 0 / restarting
csi-attacher           exit 1
csi-provisioner        exit 1
csi-resizer            exit 1
csi-snapshotter        exit 1
liveness-probe         running
```

does not mean five independent problems exist.

It may mean:

```text
cinder-csi-plugin
       ↓
CSI socket disappears
       ↓
four sidecars fail
```

---

# 22. The correct diagnostic order

When the controller is unhealthy, use this order.

First identify the failing container:

```bash
kubectl -n kube-system get pods \
  -l app=openstack-cinder-csi,component=controllerplugin
```

Then inspect its status:

```bash
kubectl -n kube-system get pod <controller-pod> \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}{" | ready="}{.ready}{" | restart="}{.restartCount}{" | last="}{.lastState.terminated.reason}{" | exit="}{.lastState.terminated.exitCode}{"\n"}{end}'
```

Then inspect the previous failure:

```bash
kubectl -n kube-system logs <controller-pod> \
  -c cinder-csi-plugin \
  --previous
```

Only after understanding the main plugin should the sidecar logs be investigated.

---

# 23. Verify the Secret without exposing credentials

To determine which keys exist:

```bash
kubectl -n kube-system get secret cinder-csi-cloud-config \
  -o jsonpath='{.data}'
```

Do not decode and paste the entire result if it contains credentials.

To verify that `cloud.conf` exists:

```bash
kubectl -n kube-system get secret cinder-csi-cloud-config \
  -o jsonpath='{.data.cloud\.conf}' | wc -c
```

A non-zero value confirms that the key exists.

To inspect safe configuration lines:

```bash
kubectl -n kube-system get secret cinder-csi-cloud-config \
  -o jsonpath='{.data.cloud\.conf}' |
  base64 -d |
  sed -E 's/(application-credential-secret[[:space:]]*=).*/\1 <REDACTED>/'
```

Never print credentials unnecessarily.

---

# 24. Resealing a corrected Secret

When updating the secret:

```text
same Secret name
same namespace
same cluster certificate
new encrypted contents
```

The command is:

```bash
kubeseal \
  --cert ~/.config/sealed-secrets/cinder-cluster.cert \
  --format yaml \
  < /tmp/cinder-secret/cinder-secret.yaml \
  > secrets/cinder/cinder-sealed.yaml
```

The resulting file is committed.

The plaintext file is not.

---

# 25. GitOps update flow

Once the corrected SealedSecret is committed:

```bash
git add secrets/cinder/cinder-sealed.yaml
git commit -m "fix(cinder): update CSI credentials"
git push
```

Argo detects the Git change.

Then:

```text
GitHub
   ↓
Argo CD
   ↓
SealedSecret
   ↓
Secret
   ↓
Cinder CSI Pod
```

The existing Kubernetes Secret does not necessarily receive a new creation timestamp.

This is important.

An object being:

```text
AGE 9h
```

does not prove that it has not been updated.

Use:

```text
resourceVersion
generation
managedFields
```

and the actual Secret contents to determine whether reconciliation occurred.

---

# 26. Failure #6 — misleading object age

During this deployment the Secret continued to report an old age.

That initially suggested:

> “Argo did not refresh the Secret.”

But the Secret's metadata showed that it had been updated:

```text
creationTimestamp
    unchanged

managedFields.time
    newer

resourceVersion
    changed
```

Kubernetes updates an existing object in place.

Therefore:

```text
creation age ≠ last modification time
```

This is another useful operational lesson.

---

# 27. Verify the rendered workload

This is one of the most important debugging techniques.

Do not only inspect:

```text
Secret
```

Inspect what Kubernetes actually rendered into the pod:

```bash
kubectl -n kube-system get pod <controller-pod> \
  -o jsonpath='{range .spec.containers[?(@.name=="cinder-csi-plugin")].args[*]}{.}{" "}{end}{"\n"}'
```

The desired result is:

```text
--cloud-config=/etc/config/cloud.conf
```

If the output says:

```text
--cloud-config=/etc/config/clouds.yaml
```

then the Secret can be perfect and the Deployment will still fail.

This is the key distinction:

```text
Secret configuration
        +
Deployment configuration
        ↓
must agree
```

---

# 28. Helm values are part of the application contract

The Cinder Application contains:

```yaml
secret:
  enabled: true
  create: false
  name: cinder-csi-cloud-config
  filename: cloud.conf
```

This value affects the actual Deployment.

Therefore `filename` is not merely descriptive metadata.

It participates in the runtime contract:

```text
Helm value
    ↓
volume mount
    ↓
container argument
    ↓
actual file path
```

A single typo here can break the application even when the Secret itself is perfect.

---

# 29. The final configuration contract

All of these must agree:

```text
Application
  secret.name:
    cinder-csi-cloud-config

Application
  secret.filename:
    cloud.conf

Secret
  metadata.name:
    cinder-csi-cloud-config

Secret
  key:
    cloud.conf

CSI argument:
  --cloud-config=/etc/config/cloud.conf

Mounted file:
  /etc/config/cloud.conf
```

Visually:

```text
Secret
  │
  └── cloud.conf
          │
          ▼
/etc/config/cloud.conf
          │
          ▼
--cloud-config=/etc/config/cloud.conf
          │
          ▼
cinder-csi-plugin
```

Once these agree, the filename problem disappears.

---

# 30. Verify the controller

Once the credential and filename are correct:

```bash
kubectl -n kube-system get pods \
  -l app=openstack-cinder-csi
```

The desired controller state is:

```text
openstack-cinder-csi-controllerplugin-...   6/6   Running
```

The node plugins should be:

```text
3/3 Running
```

on every node.

---

# 31. Verify Argo

Then:

```bash
kubectl -n argocd get application cinder-csi
```

The desired state is:

```text
NAME         SYNC STATUS   HEALTH STATUS
cinder-csi   Synced        Healthy
```

The root should independently remain:

```text
NAME         SYNC STATUS   HEALTH STATUS
root         Synced        Healthy
```

This establishes two different success conditions:

```text
Synced
    =
Git desired state has been applied

Healthy
    =
the resulting Kubernetes resources are healthy
```

Both matter.

---

# 32. Do not stop at a green Argo Application

A healthy CSI deployment is necessary but not sufficient.

The actual test is:

```text
PVC
 ↓
StorageClass
 ↓
CSI provisioner
 ↓
OpenStack Cinder
 ↓
Cinder volume
 ↓
PV
 ↓
Pod
 ↓
filesystem
```

We must test that complete path.

---

# 33. Create a test PVC

Example:

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

Apply it:

```bash
kubectl apply -f cinder-test-pvc.yaml
```

Then:

```bash
kubectl get pvc cinder-test
kubectl get pv
```

The PVC should eventually become:

```text
Bound
```

---

# 34. Verify the OpenStack side

Check Cinder:

```bash
openstack volume list
```

There should be a corresponding Cinder volume.

This proves that Kubernetes is actually talking to Cinder.

The test is therefore stronger than:

```text
CSI pod = Running
```

We are verifying the real provider integration.

---

# 35. Create a test workload

Example:

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

Then:

```bash
kubectl get pod cinder-test
```

The pod should reach:

```text
Running
```

---

# 36. Test the data

```bash
kubectl exec cinder-test -- cat /data/test.txt
```

Expected:

```text
Cinder CSI works
```

This verifies that the volume is actually mounted.

---

# 37. Test persistence

Delete only the pod:

```bash
kubectl delete pod cinder-test
```

Recreate the pod against the same PVC.

Then:

```bash
kubectl exec cinder-test -- cat /data/test.txt
```

Expected:

```text
Cinder CSI works
```

The complete persistence test is:

```text
pod deleted
    ↓
PVC survives
    ↓
PV survives
    ↓
Cinder volume survives
    ↓
new pod attaches
    ↓
data survives
```

That is the operational definition of success.

---

# 38. What Tutorial 4c has now demonstrated

A successful completion demonstrates:

```text
✓ Argo CD root Application

✓ App-of-Apps pattern

✓ Flat Application directory

✓ Argo multi-source Application

✓ Helm deployment

✓ Repository-owned Kubernetes resources

✓ Sealed Secrets integration

✓ Offline kubeseal workflow

✓ Kubernetes Secret generation

✓ OpenStack application-credential authentication

✓ Cinder CSI installation

✓ Cinder StorageClasses

✓ CSI registration

✓ Dynamic provisioning

✓ OpenStack Cinder volume creation

✓ Pod volume mounting

✓ Persistent data across pod recreation
```

More importantly, it demonstrates how to debug failures across the entire chain.

---

# 39. The debugging lessons

The ordeal exposed several important principles.

## Principle 1 — Validate the actual rendered workload

Do not assume that a correct Git file means Kubernetes is running what you intended.

Inspect:

```bash
kubectl get pod -o yaml
```

and particularly:

```text
command
args
volumeMounts
volumes
environment
```

---

## Principle 2 — Follow the first failed dependency

If four containers fail because a Unix socket disappears:

```text
four failures
```

may actually represent:

```text
one root failure
+
three downstream consequences
```

Look for the first component that fails.

---

## Principle 3 — Configuration contracts cross resource boundaries

This deployment depended on agreement between:

```text
Application
Secret
Secret key
volume mount
container argument
OpenStack credential
```

A mismatch anywhere can break the whole chain.

---

## Principle 4 — `Synced` is not the same as `Healthy`

Argo can correctly say:

```text
Synced
```

while the application is:

```text
Progressing
```

That is not contradictory.

Git desired state may have been applied perfectly while the application itself is broken.

---

## Principle 5 — `AGE` is not modification time

An object can be:

```text
9h old
```

and still have been modified seconds ago.

Use:

```text
resourceVersion
generation
managedFields
```

when diagnosing reconciliation.

---

## Principle 6 — Keep the architecture boring

The final architecture is simple:

```text
Terraform
    ↓
Ansible
    ↓
Kubernetes
    ↓
Argo CD
    ↓
Helm + Git resources + SealedSecrets
```

The complexity came from configuration mistakes, not from requiring more frameworks.

That is precisely why we removed:

```text
SOPS
KSOPS
Kustomize
ApplicationSet
```

from this path.

---

# 40. Canonical application pattern for the rest of the repository

Cinder is now the reference implementation.

Future applications should follow the same structure:

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

The mental model is:

```text
Application
    │
    ├── upstream software
    │
    ├── repository-owned resources
    │
    └── encrypted secrets
```

The application then becomes a repeatable unit.

---

# 41. The final lesson

The most important outcome of this tutorial is not Cinder.

It is learning to distinguish:

```text
architecture failure
```

from:

```text
configuration failure
```

The Cinder deployment survived:

```text
wrong Application structure
wrong resources path
wrong secret filename
wrong configuration format
wrong credential values
wrong Helm filename
```

without requiring another architectural framework.

The final architecture remained:

```text
GitHub
   ↓
Argo CD
   ↓
Helm
   +
Git resources
   +
Sealed Secrets
   ↓
Kubernetes
   ↓
Cinder CSI
   ↓
OpenStack Cinder
```

The lesson is therefore deliberately blunt:

> **Do not add another framework when a configuration value is wrong.**

First verify:

```text
What did Git declare?
What did Argo render?
What did Kubernetes create?
What arguments is the container actually using?
What file does it actually see?
What dependency does it actually call?
What is the first component that fails?
```

Once those questions are answered in order, even a seemingly catastrophic failure usually collapses into a very small mistake.

That is the real purpose of Tutorial 4c.