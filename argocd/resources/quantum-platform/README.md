# Quantum Platform Kubernetes resources

Managed by Argo CD.

Resources:

```text
namespace
configuration
PostgreSQL StatefulSet + PVC
migration Job
Blog Deployment + Service
Wiki Deployment + Service
Users Deployment + Service
Django API Deployment + Service
Traefik Ingress
```

`secret.example.yaml` is documentation only and is intentionally not included in `kustomization.yaml`.

Before syncing:

1. publish the four application images;
2. make GHCR packages public or configure image pull credentials;
3. create `quantum-platform-secrets`;
4. create `quantum-platform-tls`;
5. verify the default StorageClass is Cinder-backed.
