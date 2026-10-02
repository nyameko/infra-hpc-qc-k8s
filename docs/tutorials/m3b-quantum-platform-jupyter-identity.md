# M3b — Quantum Platform identity handoff to JupyterHub

## Security boundary

Researchers authenticate to Quantum Platform. They never receive Kubernetes
credentials or the JupyterHub service API token.

Quantum Platform issues a short-lived HMAC assertion containing:

- system username;
- provisioned POSIX UID;
- provisioned POSIX GID;
- audience;
- issue/expiry timestamps.

JupyterHub validates that assertion, stores UID/GID in encrypted auth_state and
sets KubeSpawner UID/GID immediately before spawning the user's Pod.

## Required secrets

Sealing is performed **offline on workstation `blackmyth`**. The workstation
does not run `kubectl` and does not require a kubeconfig.

The established workflow is:

```text
k8s-cp-01
    kubectl / controller operations only

blackmyth
    git
    kubeseal
    inventories/private/infra-hpc-qc-k8s.cert
    plaintext Secret YAML outside Git
```

Generate three high-entropy values privately on blackmyth:

```bash
openssl rand -hex 32  # launch signing key
openssl rand -hex 32  # Hub service API token
openssl rand -hex 32  # JUPYTERHUB_CRYPT_KEY
```

Create plaintext Secret YAML files locally outside the public repository, for
example under `../secrets/jupyterhub/`. Never commit those plaintext files.

### jupyterhub namespace

```text
Secret/jupyterhub-workbench-platform

launch_signing_key
api_token
crypt_key
```

### quantum-platform namespace

```text
Secret/quantum-platform-jupyterhub

JUPYTERHUB_LAUNCH_SIGNING_KEY
JUPYTERHUB_API_TOKEN
```

The launch signing key and API token must be identical across the two Secrets.

Seal each plaintext file locally on blackmyth using the checked-in public
certificate. The established working directory is
`~/Projects/infra-hpc-qc-k8s/ansible`, so repository-root paths must be
prefixed with `../`:

```bash
# cwd: ~/Projects/infra-hpc-qc-k8s/ansible
kubeseal \
  --cert inventories/private/infra-hpc-qc-k8s.cert \
  --format yaml \
  < ../secrets/jupyterhub/<plaintext>.yaml \
  >| ../argocd/resources/<target>/<name>-sealed.yaml
```

If working from the repository root instead, omit that leading `../` from
`argocd/...`. The plaintext JupyterHub Secret YAMLs are kept under
`~/Projects/infra-hpc-qc-k8s/secrets/jupyterhub/`, outside the Ansible
subdirectory, while the public sealing certificate is
`~/Projects/infra-hpc-qc-k8s/ansible/inventories/private/infra-hpc-qc-k8s.cert`.

Only the resulting `SealedSecret` manifests are committed to Git. Argo CD
applies them and the cluster-side Sealed Secrets controller creates the ordinary
Kubernetes Secrets.

The Quantum Platform JupyterHub service role is deliberately least-privilege:

- `read:users` to read the authenticated user's Hub model;
- `read:servers` to inspect notebook server state;
- `delete:servers` to stop the user's notebook server.

It does not receive `admin:users`, `admin:servers`, Kubernetes credentials, or
permission to create/delete Hub identities. JupyterHub creates the Hub user as
part of the validated browser login flow.

## Research identity prerequisite

Before a user can launch a workbench, Quantum Platform must have the POSIX UID
and GID that already own `/home/research/<username>`.

For the M3 bootstrap this can be inspected/set by the platform administrator in
Django Admin. The later provisioning reconciler becomes authoritative.

## Acceptance

1. Login to Quantum Platform as a provisioned research user.
2. Open `/workbench/`.
3. Launch.
4. JupyterHub consumes the short-lived assertion and creates/updates the Hub user.
5. KubeSpawner runs with the user's own numeric UID/GID.
6. `$HOME` is `/home/research/<username>`.
7. Portal status reports running.
8. Portal stop terminates only the notebook server.
9. Research files remain on shared NFS.
