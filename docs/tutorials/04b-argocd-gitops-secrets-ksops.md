# Tutorial — Argo CD GitOps Secrets: From SOPS/KSOPS to Sealed Secrets

## Purpose

This tutorial documents the evolution of secret management in `infra-hpc-qc-k8s`.

The final platform uses **Sealed Secrets** for Kubernetes secrets managed through GitOps.

The tutorial deliberately documents the abandoned SOPS/KSOPS approach because the failed design exposed an important infrastructure principle:

> Bootstrap should remain small and boring. Secret-management mechanisms should not turn the platform bootstrap role into an application deployment framework.

---

## 1. The original problem

Kubernetes applications need credentials.

For example, Cinder CSI needs an OpenStack `cloud.conf` containing credentials allowing the CSI driver to communicate with OpenStack.

The credential must:

- exist in Kubernetes;
- be available to the application;
- be managed through GitOps;
- not appear in plaintext in Git;
- not require a developer workstation to remain online.

The first approach considered was:

```text
SOPS + age
```

with Argo CD decrypting the secret during GitOps manifest generation.

---

## 2. The SOPS/age approach

The proposed architecture was:

```text
Developer workstation
    │
    │ SOPS + age
    ▼
Encrypted Kubernetes Secret
    │
    ▼
GitHub
    │
    ▼
Argo CD repo-server
    │
    │ decrypt
    ▼
Kubernetes Secret
```

This is technically viable.

The workstation needs:

```text
sops
age
```

but does not need Kubernetes access.

The repository stores encrypted data and the age public key.

The age private key must remain outside Git.

---

## 3. The KSOPS detour

To make Argo CD decrypt SOPS files during manifest generation, we explored KSOPS and Config Management Plugin integration.

This introduced additional moving parts:

```text
Argo CD
   ↓
repo-server modifications
   ↓
Kustomize exec plugins
   ↓
KSOPS
   ↓
SOPS
   ↓
age private key
```

This caused the Argo bootstrap role to grow to include:

- private-key staging;
- Kubernetes Secret creation;
- repo-server patching;
- Kustomize configuration;
- plugin configuration;
- additional rollout handling;
- temporary files and cleanup.

The result was technically interesting but architecturally undesirable.

The `argo_cd` Ansible role became responsible for too much.

---

## 4. The lesson

Ansible should bootstrap infrastructure.

It should not become a framework for installing every application and every secret-rendering mechanism.

The preferred ownership model is:

```text
Terraform
    → cloud infrastructure

Ansible
    → machines and bootstrap

Argo CD
    → Kubernetes applications

Application-specific controllers
    → application-specific Kubernetes behaviour
```

The Argo bootstrap role therefore remains intentionally small.

---

## 5. Sealed Secrets

The project subsequently adopted Bitnami Sealed Secrets.

Sealed Secrets separates the client-side encryption operation from cluster-side decryption.

The workstation uses:

```text
kubeseal
```

The cluster runs:

```text
Sealed Secrets controller
```

The controller owns the private sealing key.

The public certificate is sufficient to create encrypted `SealedSecret` objects and may safely be stored on the workstation.

---

## 6. Final architecture

```text
                         WORKSTATION

cloud-config.yaml
       │
       │ kubeseal + public certificate
       ▼
cinder-csi-cloud-config.yaml
       │
       │ git push
       ▼
     GitHub
       │
       ▼
    Argo CD
       │
       ▼
SealedSecret/cinder-csi-cloud-config
       │
       ▼
Sealed Secrets controller
       │
       │ private key
       ▼
Secret/cinder-csi-cloud-config
       │
       ▼
     Cinder CSI
```

The workstation does not need:

```text
kubectl
kubeconfig
Argo CD access
cluster administrator access
```

It only needs:

```text
git
kubeseal
the public Sealed Secrets certificate
```

---

## 7. Controller bootstrap

The Sealed Secrets controller is installed as part of the Kubernetes/Argo bootstrap process.

The bootstrap role is responsible for:

```text
install Argo CD
install Sealed Secrets controller
wait for both
```

The controller generates and manages its sealing key pair.

The controller's private key is never committed to Git.

---

## 8. Protect the private key

Immediately after installing the controller, make a secure backup of its sealing keys.

Example:

```bash
kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > /tmp/sealed-secrets-backup.yaml
```

Copy this backup to secure offline storage.

Delete the temporary copy from the control plane.

The private key backup is recovery material.

If the cluster and its sealing keys are lost, existing SealedSecrets may no longer be decryptable without a valid backup.

---

## 9. Obtain the public certificate

The workstation does not need access to the Kubernetes API.

The certificate can be fetched once from the control plane:

```bash
kubeseal --fetch-cert > infra-hpc-qc-k8s.cert
```

Copy the certificate to the workstation.

The certificate is public information.

The private sealing key is not.

---

## 10. Create a sealed Cinder credential

Create the normal Kubernetes Secret locally:

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
    ...
```

Do not commit this plaintext file.

Seal it offline:

```bash
kubeseal \
  --cert ~/.config/sealed-secrets/infra-hpc-qc-k8s.cert \
  --format yaml \
  < cloud-config.yaml \
  > cinder-csi-cloud-config.yaml
```

Delete the plaintext source.

Commit only the resulting `SealedSecret`.

---

## 11. GitOps lifecycle

The encrypted resource follows the normal GitOps lifecycle:

```text
Developer
   ↓
Git commit
   ↓
GitHub
   ↓
CI validation
   ↓
human review / merge
   ↓
Argo CD
   ↓
SealedSecret
   ↓
Sealed Secrets controller
   ↓
Kubernetes Secret
   ↓
application
```

CI does not need the private sealing key.

The developer workstation does not need Kubernetes credentials.

---

## 12. Why the final design is simpler

The abandoned approach required Argo to understand SOPS.

The final approach requires Argo to understand only ordinary Kubernetes resources.

```text
SOPS/KSOPS:

Argo
 └── custom manifest rendering
      └── KSOPS
           └── SOPS
                └── age


Sealed Secrets:

Argo
 └── SealedSecret
       └── Kubernetes controller
            └── Secret
```

The second model has a much cleaner ownership boundary for this platform.

---

## 13. What we learned

The important lesson is not that SOPS or KSOPS are bad tools.

Both solve real problems.

The lesson is:

> Choose the simplest mechanism that satisfies the operational and security requirements without contaminating an unrelated ownership boundary.

For this project:

```text
SOPS + age
    → excellent general-purpose secret encryption

KSOPS
    → useful when SOPS decryption must be integrated into manifest rendering

Sealed Secrets
    → a better fit for our Kubernetes-native GitOps secret lifecycle
```

The project therefore standardises on:

```text
Sealed Secrets
    +
Argo CD
    +
GitOps
```

for Kubernetes application credentials.

---

## 14. Recovery principle

Sealed Secrets key material is part of the platform's disaster-recovery state.

The platform should therefore include:

```text
cluster backup
+
Sealed Secrets private-key backup
+
repository
+
infrastructure state
+
provider credentials/recovery procedures
```

A future disaster-recovery tutorial should demonstrate rebuilding the cluster and restoring the original Sealed Secrets keys before attempting to reconcile encrypted application secrets.

---

## 15. Final principle

The resulting architecture is intentionally boring:

```text
Bootstrap
    ↓
Argo CD + Sealed Secrets

Git
    ↓
Argo CD

SealedSecret
    ↓
Secret

Application
    ↓
works
```

That is the desired outcome.

The infrastructure complexity should be in the architecture and automation where it provides value, not in making application bootstrap harder than necessary.