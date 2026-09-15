# Quantum Platform — Kubernetes / Argo CD Deployment

This document is the infrastructure-side deployment guide for:

- `blog.nyameko.com`
- `wiki.quantum.nyameko.com`
- `users.quantum.nyameko.com`
- Django User API
- PostgreSQL

Application source lives in:

```text
https://github.com/nyameko/quantum-platform
```

Production desired state lives here in `infra-hpc-qc-k8s`.

## 1. Architecture

```text
GitHub quantum-platform
        │
        ├── CI
        └── GHCR images
               │
               ▼
GitHub infra-hpc-qc-k8s
        │
        ▼
     Argo CD
        │
        ▼
    Kubernetes
        │
        ├── Astro Blog
        ├── Astro Wiki
        ├── Astro Users
        ├── Django User API
        └── PostgreSQL + Cinder PVC
        │
        ▼
      Traefik
```

The cluster already uses Argo CD for long-lived applications and Cinder CSI for persistent OpenStack-backed storage. This application follows that model.

## 2. Images

The application CI publishes:

```text
ghcr.io/nyameko/quantum-platform-blog
ghcr.io/nyameko/quantum-platform-wiki
ghcr.io/nyameko/quantum-platform-users
ghcr.io/nyameko/quantum-platform-user-api
```

The initial integration uses the mutable `main` tag to make first deployment simple.

After the integration test is complete, switch:

```yaml
newTag: main
```

to immutable:

```yaml
newTag: sha-<commit>
```

for reproducible rollbacks.

## 3. GHCR visibility

Because the application repository is public and the images contain no secrets, the simplest cluster setup is to make these four GHCR packages public.

If they remain private, configure an image pull secret and attach it to each Deployment/Job.

## 4. Secrets

Plaintext production secrets are not committed.

Generate values locally:

```bash
export POSTGRES_PASSWORD="$(openssl rand -base64 36)"
export DJANGO_SECRET_KEY="$(
  python - <<'PY'
import secrets
print(secrets.token_urlsafe(64))
PY
)"
```

Bootstrap:

```bash
./scripts/bootstrap-quantum-platform-secrets.sh
```

The resulting Kubernetes Secret is:

```text
quantum-platform-secrets
```

This out-of-band bootstrap is acceptable for the first integration checkpoint. Once the platform secret workflow is finalized, move it to the chosen encrypted GitOps mechanism.

## 5. TLS

The Ingress expects:

```text
quantum-platform-tls
```

in namespace:

```text
quantum-platform
```

The certificate must cover:

```text
blog.nyameko.com
wiki.quantum.nyameko.com
users.quantum.nyameko.com
```

If a suitable certificate already exists locally:

```bash
export TLS_CERT=/path/to/tls.crt
export TLS_KEY=/path/to/tls.key

./scripts/bootstrap-quantum-platform-secrets.sh
```

The script will create/update the TLS Secret.

If the cluster's certificate automation owns this instead, adapt the Ingress to that existing mechanism rather than duplicating certificate lifecycle.

## 6. Storage

The PostgreSQL `StatefulSet` requests:

```text
20Gi
ReadWriteOnce
```

No explicit StorageClass is pinned.

That intentionally uses the cluster default StorageClass.

Before deployment:

```bash
kubectl get storageclass
```

Confirm the default class is backed by OpenStack Cinder CSI.

If there is no default, add the correct `storageClassName` to the PostgreSQL volume claim template before syncing.

## 7. Validate Kustomize

From the infrastructure repository:

```bash
kubectl kustomize argocd/resources/quantum-platform >/tmp/quantum-platform.yaml
```

Inspect:

```bash
less /tmp/quantum-platform.yaml
```

There must be no plaintext secret values in the rendered output.

## 8. Bootstrap the Argo CD Application

If the current root Application does not automatically discover `argocd/applications/`, apply the child Application once:

```bash
kubectl apply -f argocd/applications/quantum-platform.yaml
```

After this step, Git is authoritative.

Do not manually edit the Deployments.

## 9. Watch Argo

```bash
kubectl -n argocd get application quantum-platform -w
```

Detailed state:

```bash
kubectl -n argocd describe application quantum-platform
```

The expected ordering is:

```text
wave 0
  PostgreSQL / configuration

wave 1
  Django migrations

wave 2
  Blog / Wiki / Users / User API

wave 3
  Ingress
```

## 10. Validate workloads

```bash
kubectl -n quantum-platform get pods -o wide
kubectl -n quantum-platform get svc
kubectl -n quantum-platform get pvc
kubectl -n quantum-platform get ingress
```

Expected:

```text
PostgreSQL PVC: Bound
PostgreSQL pod: Ready
Blog pods: Ready
Wiki pods: Ready
Users pods: Ready
User API pods: Ready
```

## 11. Validate the API inside Kubernetes

```bash
kubectl -n quantum-platform run curl-test \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  -- \
  curl -fsS \
  http://quantum-platform-user-api:8000/api/v1/health/
```

Expected:

```json
{
  "status": "ok",
  "service": "quantum-platform-user-api",
  "database": "ok"
}
```

## 12. DNS / ingress acceptance

Before relying on public DNS, confirm the intended HAProxy → Traefik path reaches the Ingress.

Then add/validate DNS for:

```text
blog.nyameko.com
wiki.quantum.nyameko.com
users.quantum.nyameko.com
```

For private split DNS, resolve them to the private application ingress endpoint while connected through WireGuard.

Test:

```bash
curl -Ik https://blog.nyameko.com/
curl -Ik https://wiki.quantum.nyameko.com/
curl -Ik https://users.quantum.nyameko.com/
curl -Ik https://users.quantum.nyameko.com/api/v1/health/
```

## 13. Same-origin routing test

The critical User Portal property is:

```text
same hostname
```

with different Kubernetes backends.

Confirm:

```text
https://users.quantum.nyameko.com/
    → Astro users

https://users.quantum.nyameko.com/api/v1/health/
    → Django

https://users.quantum.nyameko.com/_allauth/browser/v1/auth/session
    → django-allauth
```

Do not split Django onto a separate browser origin unless there is a compelling reason.

## 14. First production account test

While the email backend remains console-based:

```bash
kubectl -n quantum-platform logs \
  deploy/quantum-platform-user-api \
  --tail=200 -f
```

Register a test user and retrieve the verification URL from the logs.

Then validate:

```text
registration
→ email verification
→ login
→ MFA
→ dashboard
→ profile
→ programme workflow
→ logout
```

Before student onboarding, configure real SMTP delivery.

## 15. Persistence acceptance

Create a test account, then:

```bash
kubectl -n quantum-platform delete pod quantum-platform-postgres-0
```

Wait for recreation:

```bash
kubectl -n quantum-platform get pod quantum-platform-postgres-0 -w
```

Confirm the account still exists.

If it does not, stop: the deployment is not production-ready.

## 16. Rollback

Once image tags are immutable, rollback is a Git change:

```yaml
newTag: sha-oldgood
```

Commit it.

Argo CD performs the rollback by reconciling the cluster to Git.

## 17. Operational boundary

This deployment does not yet attempt to provision:

- Linux users
- SSH authorized keys
- WireGuard peers
- Slurm accounts
- JupyterHub users

Those are later workflows.

Phase 2 ends at authoritative identity, MFA, programme approval, audit state, and a deployable web/API platform.
