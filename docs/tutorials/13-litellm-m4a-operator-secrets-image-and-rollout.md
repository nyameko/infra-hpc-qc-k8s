# M4a LiteLLM staging operator checklist

**No automation/agent production changes:** this is an operator-run plan, not evidence of a completed installation. The 2026-10-24 ACE tests confirmed an authenticated vLLM `/v1/models` result on loopback, HTTP 401 without credentials from ACE and Sebowa edges, and an established `wg-fabric` peer connection. Pod-to-A100 TCP and routed return traffic still require verification.

## Hosts and deployment discipline

- `blackmyth`: Git, editor, private Secret JSON and direct `kubeseal` using the certified controller certificate. No assumption of local `kubectl` or `yamllint`.
- `k8s-cp-01`: `kubectl`, Argo CD manual sync and inspection. Do **not** install or invoke Kubernetes tooling on blackmyth as an implicit step.
- ACE edge `196.24.241.108` / `10.70.0.10`; primary A100 vLLM `10.70.0.20:8000`. The public edge address is **not** the LiteLLM backend.
- ACP canonical state in its **separate** PostgreSQL. The LiteLLM database is only for virtual-key and spend records.
- No Traefik, new DNS, extra Pi-hole, TLS ingress, firewall-cmd, new WireGuard peer or extra network services for M4a.

## Generating and escrowing the credentials (blackmyth, **not** k8s-cp-01)

`VAULT-ESCROWED` means a strong random value that has a **separate, encrypted, recoverable copy** under the operator's control. An ordinary private directory with Unix mode 0700 is **not** by itself an encrypted password vault. Prefer a password manager with an encrypted offline backup and documented operator recovery. Do not store the plaintext originals on `k8s-cp-01`, in Git, in Argo CD parameters or in Kubernetes Pod logs. Once SealedSecrets are applied, the controller creates ordinary Kubernetes Secrets in the `litellm` namespace. Verify that Kubernetes etcd encryption-at-rest and backup access controls meet site policy; sealing does not itself encrypt etcd contents.

The working directories below are on `blackmyth`. Confirm that the workstation filesystem is encrypted, use restrictive modes, and do not keep the extra plaintext working files any longer than necessary. A protected tmpfs may be preferable for temporary creation if disk-remanence matters.

### A. Create four independent random credentials

From the `infra-hpc-qc-k8s` checkout, **without `set -x`**, run:

```sh
umask 077
install -d -m 700 "$HOME/.local/private/litellm"
install -d -m 700 secrets/litellm
PRIVATE="$HOME/.local/private/litellm"

# Generates 256 random bits for each database account.
openssl rand -hex 32 | tr -d '\n' > "$PRIVATE/db-owner"
openssl rand -hex 32 | tr -d '\n' > "$PRIVATE/db-app"

# Master key is distinct from database roles, and starts with sk-.
{ printf 'sk-'; openssl rand -hex 32 | tr -d '\n'; } > "$PRIVATE/master-key"

# Stable salt: preserve the same value across LiteLLM gateway restarts/upgrades.
openssl rand -hex 32 | tr -d '\n' > "$PRIVATE/salt-key"
chmod 600 "$PRIVATE/db-owner" "$PRIVATE/db-app" "$PRIVATE/master-key" "$PRIVATE/salt-key"
```

These commands write no password to console output or shell command arguments. They do create **plaintext working files** (mode 0600) at `$PRIVATE`. The `db-app` password uses lowercase hex only, making it safe to embed directly in the database URL without further URL escaping; if using a password containing other characters instead, percent-encode the URL password separately.

**Escrow each value in the encrypted vault before sealing**, using distinct entries: `LiteLLM/PostgresOwner`, `LiteLLM/PostgresApp`, `LiteLLM/MasterKey`, and `LiteLLM/SaltKey`. Verify secure recovery from an independent vault/backup, not just access to these local files. Do **not** rerun the commands over existing files after database initialization: PostgreSQL `initdb` only initializes first-run credentials, and a changed salt/master key may make stored LiteLLM data unusable.

The fifth value, the ACE vLLM bearer token, **already exists** on `gpu-a100-01` and was proven to work in an authenticated `/v1/models` request. Reuse the *exact existing backend token*; do not generate a new A100 token just to deploy LiteLLM. Retrieve it through your approved credential vault or another protected channel, and store a temporary copy as `$PRIVATE/ace-vllm-api-key` with mode 0600. Do not paste the token into chat, issues, shell history or logs. Do not assume `secrets/agent-control-plane/model-api-key` contains the A100 token unless it is verified against the source.

### B. Build Kubernetes Secret JSON locally using jq

These commands read each secret via `--rawfile` (avoiding secret values in process arguments) and write files only under the already-ignored `secrets/` directory:

```sh
# Database bootstrap owner Secret.
jq -n --rawfile pw "$PRIVATE/db-owner" '{
  apiVersion: "v1", kind: "Secret",
  metadata: {name: "litellm-db-owner", namespace: "litellm"},
  type: "Opaque",
  stringData: {POSTGRES_PASSWORD: $pw}
}' > secrets/litellm/litellm-db-owner.json

# Database application Secret. Same db-app password in both fields.
jq -n --rawfile pw "$PRIVATE/db-app" '{
  apiVersion: "v1", kind: "Secret",
  metadata: {name: "litellm-db-app", namespace: "litellm"},
  type: "Opaque",
  stringData: {
    LITELLM_DB_APP_PASSWORD: $pw,
    DATABASE_URL: (
      "postgresql://litellm_app:" + $pw +
      "@litellm-postgres.litellm.svc.cluster.local:5432/litellm?schema=public"
    )
  }
}' > secrets/litellm/litellm-db-app.json

# Gateway Secret. Uses the existing authenticated A100 backend token.
jq -n \
  --rawfile master "$PRIVATE/master-key" \
  --rawfile salt "$PRIVATE/salt-key" \
  --rawfile ace "$PRIVATE/ace-vllm-api-key" '{
  apiVersion: "v1", kind: "Secret",
  metadata: {name: "litellm-credentials", namespace: "litellm"},
  type: "Opaque",
  stringData: {
    LITELLM_MASTER_KEY: $master,
    LITELLM_SALT_KEY: $salt,
    ACE_VLLM_API_KEY: $ace,
    ACE_VLLM_BASE_URL: "http://10.70.0.20:8000/v1"
  }
}' > secrets/litellm/litellm-credentials.json

chmod 600 secrets/litellm/*.json
git check-ignore -v secrets/litellm/litellm-credentials.json
```

Expected result of `git check-ignore`: an ignore match for `secrets/`. If the command exits nonzero, **stop** and repair ignore rules *before any Git staging*. Run the metadata validation below and check all three `stringData` key sets without dumping secret values. For `litellm-db-app`, verify the password in `DATABASE_URL` matches `LITELLM_DB_APP_PASSWORD`. **Never commit the plaintext JSON.**

### C. Seal, review, and retain recovery material

Use the existing direct `kubeseal --cert ... --format yaml` commands later in this document. The inputs must be namespaced exactly `litellm` with the expected Secret names. The three encrypted outputs go in `argocd/resources/litellm/`, and only the sealed outputs are committed. Add those files to the same reviewed Kustomization PR, preserving the deliberate manual-first-sync gate.

After confirming all three SealedSecrets contain the expected encrypted field names and that all **original values are recoverable from the encrypted vault**, remove unneeded plaintext working files and JSON inputs from `blackmyth`. Simple deletion on SSD/Btrfs is not a forensic wipe, so minimize disk copies and rely on workstation full-disk encryption / temporary memory-backed storage where necessary. Keep the **vault entries** securely backed up for reinstallation, database restore and credential rotation. The generated SealedSecret ciphertext alone is not a substitute for a master-key/salt recovery process.

Do not transfer plaintext secrets to the Kubernetes control-plane host. The controller will produce the runtime Secrets during the approved GitOps rollout; administrators should not hand-create them with `kubectl create secret`.

## Exactly three dedicated LiteLLM Secrets

Each is a standard Kubernetes **input** Secret with `apiVersion: v1`, `kind: Secret`, `type: Opaque`, `metadata.namespace: litellm`, exact `metadata.name`, and `stringData` (or encoded `data`). Keep plaintext under the ignored `secrets/litellm/` directory with restrictive permissions, encrypt for safe offline recovery and never commit. Do not paste values into issues, CI logs or chat.

1. **`secrets/litellm/litellm-db-owner.json`**:
   `{"apiVersion":"v1","kind":"Secret","metadata":{"name":"litellm-db-owner","namespace":"litellm"},"type":"Opaque","stringData":{"POSTGRES_PASSWORD":"<VAULT-ESCROWED-OWNER-PASSWORD>"}}`
2. **`secrets/litellm/litellm-db-app.json`**:
   `{"apiVersion":"v1","kind":"Secret","metadata":{"name":"litellm-db-app","namespace":"litellm"},"type":"Opaque","stringData":{"LITELLM_DB_APP_PASSWORD":"<VAULT-ESCROWED-APP-PASSWORD>","DATABASE_URL":"postgresql://litellm_app:<URL-ENCODED-APP-PASSWORD>@litellm-postgres.litellm.svc.cluster.local:5432/litellm?schema=public"}}`
3. **`secrets/litellm/litellm-credentials.json`**:
   `{"apiVersion":"v1","kind":"Secret","metadata":{"name":"litellm-credentials","namespace":"litellm"},"type":"Opaque","stringData":{"LITELLM_MASTER_KEY":"sk-<VAULT-ESCROWED-MASTER-KEY>","LITELLM_SALT_KEY":"<PERSISTENT-ESCROWED-SALT>","ACE_VLLM_API_KEY":"<EXISTING-PROTECTED-VLLM-TOKEN>","ACE_VLLM_BASE_URL":"http://10.70.0.20:8000/v1"}}`

The PostgreSQL application password and database URL password **must match** (URL-encode any special characters in the URL). Owner, application, gateway master, salt and ACE bearer must be distinct where applicable. Make no password changes on a retained database PVC without coordinating PostgreSQL role changes. The owner/bootstrap script only runs when PostgreSQL first initializes.

## Validate metadata locally, without leaking data

At the repository root, operator can run:

```sh
umask 077
for name in litellm-db-owner litellm-db-app litellm-credentials; do
  f="secrets/litellm/${name}.json"
  jq -e --arg n "$name" '
    .apiVersion == "v1" and .kind == "Secret" and
    .metadata.name == $n and .metadata.namespace == "litellm" and
    .type == "Opaque" and
    (.stringData | type == "object")
  ' "$f" >/dev/null || exit 1
  printf 'Validated metadata for %s\n' "$name"
done
```

Ensure correct keys without echoing values: `jq -r '.stringData|keys[]' secrets/litellm/litellm-credentials.json`.

Seal directly, with the **verified existing** SealedSecrets controller certificate. Each output is strict-name/namespace encrypted ciphertext:

```sh
kubeseal --cert ansible/inventories/private/infra-hpc-qc-k8s.cert --format yaml \
  < secrets/litellm/litellm-db-owner.json \
  > argocd/resources/litellm/litellm-db-owner-sealed.yaml
kubeseal --cert ansible/inventories/private/infra-hpc-qc-k8s.cert --format yaml \
  < secrets/litellm/litellm-db-app.json \
  > argocd/resources/litellm/litellm-db-app-sealed.yaml
kubeseal --cert ansible/inventories/private/infra-hpc-qc-k8s.cert --format yaml \
  < secrets/litellm/litellm-credentials.json \
  > argocd/resources/litellm/litellm-credentials-sealed.yaml
```

Check every output SealedSecret metadata name, namespace and encryptedData key names, with no plaintext. Add the three encrypted manifest paths to `argocd/resources/litellm/kustomization.yaml` in the same review PR, plus the wave -3 annotation if required for pre-DB bootstrap. Do not create empty or invented ciphertext files.

## Image and Prisma validation (must pass before first sync)

At least one trusted image-capable environment should resolve the actual registry digest for the **reviewed** version `ghcr.io/berriai/litellm:v1.90.2`:

```sh
crane digest ghcr.io/berriai/litellm:v1.90.2
# or, on a trusted host with skopeo:
skopeo inspect --format '{{.Digest}}' docker://ghcr.io/berriai/litellm:v1.90.2
```

Verify the digest via independent registry inspection and inspect architecture, expected CLI/probes, entrypoint, image provenance and applicable security advisories; **do not guess a digest**. Pin the **same verified digest** in `argocd/resources/litellm/deployment.yaml` and `migrate-job.yaml`. Existing version-tag source contains `litellm/proxy/prisma_migration.py`, but container compatibility and migration behavior have not been verified. The gateway starts with `DISABLE_SCHEMA_UPDATE=true`; the separate migration hook is wave 1, gateway wave 2. Check the non-superuser app-role grants and that migration succeeds before starting the gateway.

Test nonzero internal model cost accounting and disposable virtual-key allowlist, unauthorized and over-budget rejection. No ACP worker gets the LiteLLM master key.

## ACE network gate

Review proposed `litellm-to-ace-a100` policy: it restricts **only** LiteLLM pod egress to `10.70.0.20/32` TCP/8000, with existing default deny retained. Do not broaden to `10.70.0.0/24` or edge floating IP. It does not automatically configure Linux routes, cloud security groups or nftables.

Before deployment, run non-secret routing/HTTP status checks on both edges and source-node diagnostics. Successful HTTP 401 from Sebowa edge proves working authenticated-service response across WireGuard for that path; reverse ping failure to k8s-cp-01 is not proof of broken inference. Verify Cilium SNAT and an authorized Pod-to-A100 request after deployment; ensure OpenStack return path and policy allow the translated source. Do not enable the review-only full ruleset flush / default-drop ACE nftables candidate.

## Promotion and acceptance

1. Review branch PR and GitHub Actions YAML+Kustomize tests (and verify the operator-generated encrypted files are present).
2. Promote reviewed GitOps manifests `dev` → `main`, preserving the six-month release policy and human release approval; do not directly change the live Argo Application targetRevision.
3. Explicit approval for the manual first LiteLLM Argo sync on `k8s-cp-01`. Confirm namespace, retained PVC, Secret unsealing, bootstrap, Prisma Job logs, gateway readiness. An Argo "Healthy" without matching workloads is not acceptance.
4. Use operator-only management access to issue a restricted ACP virtual key, test authorization/rate/budget rules, seal `acp-model` with the virtual key—not the master key—and review/publish it.
5. Explicit approval for ACP Argo sync; verify schema v3, API, worker, model route, volume persistence and portal client identity.
6. Only then run `tools/m4a-conformance.py` with different AgentPrincipal subjects, record baseline, **manually** replace the disposable worker and API Pods and destroy client/Jupyter runtime, then verify canonical history and subject isolation. Close ACP issue #21 only with observed evidence.

**Unresolved**: actual immutable image digest, secret values/ciphertext, Pod-to-A100 connectivity, migration execution and destructive acceptance. None is represented as completed.
