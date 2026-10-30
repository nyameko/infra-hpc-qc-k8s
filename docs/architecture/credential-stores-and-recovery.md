# Credential stores, custody and recovery (Sebowa / ACE)

This is a **public, secret-free inventory** of credential roles and recovery procedures. Never put values, hashes, private topology, tokens, passwords, plaintext Kubernetes Secret manifests, environment dumps or private keys into Git, issues, PRs, chat, logs or screenshots.

## Ownership and boundaries

**Sebowa and ACE are two entirely separate OpenStack clouds.** Each has independent Keystone/Neutron credentials, projects, security groups, Terraform state, edge hosts and backup responsibilities. They are connected only by the deliberately configured site-to-site `wg-fabric`; they do **not** share an OpenStack router, tenant, management plane or credential store.

- **Encrypted vault** (operator-managed password manager with encrypted/offline recovery copy): authoritative recoverable originals and rotation metadata; verify each entry has actually been escrowed, not merely documented.
- **Blackmyth**: ignored `secrets/`, protected Ansible inventory and `~/.local/private/` are *working copies*, not a vault just because directories are mode 0700. Workstation storage encryption is an additional measure, not an independently recoverable backup.
- **ACE GPU host**: `/etc/vllm/vllm.env` holds `VLLM_BEARER_TOKEN` for the vLLM service. The Ansible `vllm_server_bearer_token` variable comes from protected inventory/Vault. The original *generation* and first escrow location have not been independently established.
- **Kubernetes**: `kubeseal` produces public-to-commit SealedSecret ciphertext. The controller produces ordinary namespaced Kubernetes Secrets and Pod env values; those are runtime copies, **not** sufficient disaster-recovery escrow. Back up the SealedSecrets controller private recovery keys under restricted encrypted custody.
- **Git**: committed SealedSecrets are encrypted deployment material, **not** proof that the password manager contains usable originals.

## Credentials: source and destination, not interchangeable

| Vault entry (suggested) | Value / variable | Working / runtime location | Recovery and rotation note |
| --- | --- | --- | --- |
| `ACE/vLLM/BearerToken` | `VLLM_BEARER_TOKEN` = `ACE_VLLM_API_KEY` | ACE `gpu-a100-01:/etc/vllm/vllm.env`; ACE protected Ansible `vllm_server_bearer_token`; Blackmyth `~/.local/private/litellm/ace-vllm-api-key` (documented destination); `secrets/agent-control-plane/ace-vllm-api-key` (operator-observed local copy); Sebowa `litellm/litellm-credentials` | The **same token bytes** on both ends. Recover via approved privileged channel; verify equivalence without displaying token. Location of original generation/escrow is unverified. |
| `LiteLLM/Gateway/MasterKey` | `LITELLM_MASTER_KEY` | `secrets/litellm/litellm-credentials.json` -> `litellm-credentials` Secret -> LiteLLM Pod | Administrative only; never give to ACP or users. Preserve continuity during database recovery. |
| `LiteLLM/Gateway/SaltKey` | `LITELLM_SALT_KEY` | Same Secret | **Stable**, preserve when restoring stored gateway key data; don't regenerate casually. |
| `LiteLLM/PostgresOwner` | `POSTGRES_PASSWORD` | `secrets/litellm/litellm-db-owner.json` -> `litellm-db-owner` | Owner/bootstrap credential, not app credential; retained PVC password changes require coordination. |
| `LiteLLM/PostgresApp` | `LITELLM_DB_APP_PASSWORD`, `DATABASE_URL` | `secrets/litellm/litellm-db-app.json` -> `litellm-db-app` | URL embeds same app password; preserve URI scheme and URL-encoding. |
| `ACP/Model/VirtualKey` | `ACP_MODEL_API_KEY` | `secrets/agent-control-plane/acp-model.json` -> `agent-control-plane/acp-model` | Restricted LiteLLM **virtual key** for `research-general`, not A100 bearer or LiteLLM master key. Verify provisioned key and budgets; a legacy placeholder may still exist. |
| `ACP/PostgresOwner`, `ACP/PostgresApp` | ACP DB passwords/connection URL | `secrets/agent-control-plane/acp-db-owner.json`, `acp-db-app.json` | Distinct ACP PostgreSQL, authoritative for projects, conversations, tasks, policies and durable memory. Preserve database backups **as well as** passwords. |
| `ACP/Signing`, `ACP/Verification` | Signing/verification identity material | `secrets/agent-control-plane/acp-signing.json`, `acp-verification.json` | Preserve private signing keys, verification/public keys and their version/rotation history as applicable. |
| `SealedSecrets/ControllerRecovery` | Controller **private** sealing keys; public sealing certificate | Live controller Secret(s); workstation certificate e.g. `ansible/inventories/private/infra-hpc-qc-k8s.cert` | Public certificate **alone cannot decrypt** sealed manifests; escrow controller private key backups securely and test restore. |
| `Sebowa/OpenStack`, `ACE/OpenStack` | Independent clouds.yaml/application credentials | Respective protected client config, Terraform private variables | Two vault namespaces; store project, region, endpoints, expiry, scopes and recovery, never mix sites. |
| `Sebowa/wg-fabric`, `ACE/wg-fabric` | Separate WireGuard private keys and optional PSKs | Protected site inventories, `/etc/wireguard/wg-fabric.conf` | Escrow **both** ends separately; peer public keys are non-secret. Include human/admin `wg0` client keys where restoration requires them. |
| `SSH/Admin`, `SSH/ServiceSlurm` | Protected admin, bootstrap/recovery and Slurm gateway SSH private keys | Workstation `~/.ssh`; ignored `secrets/slurm/`; protected host config | Back up passphrases and known recovery method; `*.pub` and known-host records are not secret. |
| `Cloudflare/DNS`, `cert-manager/ACME` | API token; ACME private account key, TLS private keys where recovery needed | `secrets/cert-manager/cloudflare-api-token.yaml`, Kubernetes TLS/ACME state | Limit token scope; retain account/certificate recovery material. |
| `Cinder/CSI` | OpenStack Cinder/CSI cloud credentials | `secrets/cinder/cloud-config.yaml`; deployed CSI Secret | May reference scoped Sebowa cloud application credential; treat as secret even if YAML. |
| `Grafana/Admin` | Admin password/API token | `secrets/grafana/grafana-admin.yaml` | Prefer rotation and scoped automation tokens. |
| `JupyterHub/ProxyOAuth` | Hub cookie secret, proxy auth token, OAuth client secrets, workbench integration credentials | `secrets/jupyterhub/*.yaml` and generated K8s Secrets | Record which values need stable continuity and upstream identity-provider registrations. |
| `QuantumPlatform/AppIdentity` | Application DB credentials, session/JWT signing material, OAuth secrets | `secrets/quantum-platform/quantum-platform-secrets.yaml` | Preserve signing/session continuity where required. |
| `Slurm/MUNGEAccounting` | MUNGE key, database/SlurmDBD credentials, submission gateway private key | Protected Slurm hosts/inventory; `secrets/slurm/` | Keep MUNGE consistent across participating nodes; protect host/service identities. |
| `Wazuh/ManagerIndexerDashboard` | API/indexer/dashboard credentials, internal users, enrolment credentials, TLS private keys and PKI CA | `secrets/wazuh/credentials/`, `secrets/wazuh/pki/`, `secrets/wazuh/*.yaml` | Escrow root/intermediate CA private keys, trust chains, rotations and user passwords separately. |
| `GitOps/Automation` | GitHub/GitOps deploy keys, webhook HMACs, CI signing tokens, registry pull credentials | Approved secret managers / runner or Kubernetes Secrets | Inventory only **if deployed**; never assume one already exists. |
| `Backup/Recovery` | Encryption keys/passphrases for backups, LUKS recovery, Ansible Vault unlock secret, password-manager recovery kit | Independently encrypted offline storage | Recovery root: test independently; do not store unlock secret only inside the volume it unlocks. |

The following are normally *configuration rather than secrets*: `ACE_VLLM_BASE_URL` (must end in `/v1` for LiteLLM), model alias `research-general`, `qwen3.5-27b`, peer public keys, and certificates' public halves. Still keep authoritative internal IP inventories private according to topology policy. Do not confuse an API base URL with an API key.

### Local inventory observed by operator (2026-10-30; contents NOT audited)

`secrets/{agent-control-plane,cert-manager,cinder,grafana,jupyterhub,litellm,quantum-platform,slurm,wazuh}/` exists on Blackmyth. In particular, operator observed `secrets/agent-control-plane/ace-vllm-api-key`, `secrets/agent-control-plane/model-api-key`, `secrets/litellm/litellm-credentials.json`, `litellm-db-app.json`, `litellm-db-owner.json`. File *presence* does not confirm token validity, recovery custody or equivalence. The observed bearer-key file and LiteLLM JSON files were mode **0644**; fix to **0600** as soon as practical. A restricted parent directory is not a substitute for restrictive file modes.

On Blackmyth, run without printing values:

```bash
cd ~/Projects/infra-hpc-qc-k8s
chmod 600 secrets/agent-control-plane/ace-vllm-api-key secrets/litellm/*.json
git check-ignore -v secrets/litellm/litellm-credentials.json
stat -c '%a %n' secrets/agent-control-plane/ace-vllm-api-key secrets/litellm/*.json
```

The user-reported 2026-10-30 test from inside LiteLLM returned authenticated `GET /v1/models` HTTP 200 with model `qwen3.5-27b`: **network and backend authentication passed at that moment**. End-to-end LiteLLM generation and ACP destructive persistence have **not** been established by that test.

## Recovery and rotation: ACE bearer token

1. Check encrypted password manager/vault entry `ACE/vLLM/BearerToken` (if it exists), protected ACE Ansible inventory/Vault, then ACE GPU host `/etc/vllm/vllm.env`. Do not assume the original was ever stored in the vault.
2. Avoid emitting the token or copying it through chat, Git, shell history, process arguments or logs. Escrow a recoverable copy through an operator-approved encrypted path; verify the original was not unintentionally rotated.
3. Seal the matched token into Sebowa `litellm-credentials` as `ACE_VLLM_API_KEY` with `ACE_VLLM_BASE_URL` ending `/v1`; review ciphertext-only PR, promote to `main`, manually sync via Argo CD on `k8s-cp-01`, restart **only** LiteLLM Deployment if Pod environment changed.
4. Validate actual LiteLLM Pod authenticated `GET /v1/models` before running a small gateway completion. Do not replace A100's token merely to work around a misconfigured consumer.
5. Rotate with planned coordinated updates of ACE service and Sebowa secret, verification, and rollback; maintain a dated audit of which vault entry and protected hosts have been updated, without recording values.

## Safeguards and acceptance

- Inventory each entry as **present in vault / recoverable-tested / missing / needs rotation**, plus owner, scope, issuer, last verified, rotation date and protected storage location. Never include actual secret values or fingerprints in the public inventory.
- Encrypted vault + offline encrypted backup, not `secrets/` alone. Restore test the Sealed Secrets controller private key and app/data backups; save the ability to decrypt historic SealedSecrets.
- Check ignored plaintext paths before staging Git changes; do not stage `secrets/`, `*.tfstate`, `clouds.yaml`, WireGuard or SSH private keys.
- Keep GitOps/Ansible/Terraform permissions minimal; avoid broad SG/nftables allowances. Worker and Pod rescheduling may require reviewed narrow controls.
- Do not mark **M4a** complete until the ACP PostgreSQL-backed destructive continuity and subject-isolation acceptance test is **actually** observed. LiteLLM and Paperclip are supporting workstreams, not M4a closure criteria.

See [private-state disaster recovery](../tutorials/private-state-disaster-recovery.md), [LiteLLM operator runbook](../tutorials/13-litellm-m4a-operator-secrets-image-and-rollout.md), and [secrets policy](../tutorials/08-secrets-variables-versions.md).
