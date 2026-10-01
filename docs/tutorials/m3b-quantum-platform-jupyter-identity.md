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

Generate three high-entropy values privately:

```bash
openssl rand -hex 32  # launch signing key
openssl rand -hex 32  # Hub service API token
openssl rand -hex 32  # JUPYTERHUB_CRYPT_KEY
```

The launch signing key and API token must be identical across the two namespace
Secrets.

### jupyterhub namespace

```text
Secret/jupyterhub-workbench-platform

launch_signing_key
api_token
crypt_key
```

### quantum-platform namespace

Add to the existing sealed `quantum-platform-secrets`:

```text
JUPYTERHUB_LAUNCH_SIGNING_KEY
JUPYTERHUB_API_TOKEN
```

Seal the values with the existing SealedSecret workflow. Never commit plaintext
secrets.

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
