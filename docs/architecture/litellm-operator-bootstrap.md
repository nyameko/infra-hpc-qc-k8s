# LiteLLM operator bootstrap — do not sync until reviewed

## Workstation boundary

**blackmyth (Arch):** Git, Ansible, Terraform and **direct `kubeseal` CLI**. Do not add secret-generating Python helpers. Do **not** assume local kubectl or yamllint. Use GitHub Actions for yamllint/Kustomize/schema validation. **k8s-cp-01:** kubectl and Argo CD inspection/manual human-approved sync. No production action by the agent.

## Required private inputs

- Site SealedSecrets certificate copied from the currently deployed controller and verified with the cluster operator (historically `ansible/inventories/private/infra-hpc-qc-k8s.cert`; verify correct certificate/current namespace and controller before use).
- Protected vLLM bearer key from the existing A100 deployment (do not paste it into PRs or chat).
- Verified private A100 IP and route through wg-fabric; ensure TCP/8000 is reachable **from pod CIDRs**, not only an edge node.
- A **verified digest** for `ghcr.io/berriai/litellm:v1.90.2`, identical in deployment and migration Job; confirm command line and dependency chain. Do not infer a digest from the tag or use latest. Obtain via `skopeo inspect --raw docker://ghcr.io/berriai/litellm:v1.90.2` or `crane digest ghcr.io/berriai/litellm:v1.90.2` on a trusted equipped runner. Check the registry's multi-arch index vs the selected architecture. Verify provenance and vulnerability advisories before deployment. **Never sync with unverified tags.**
- Actual cost rates for self-hosted hardware. The repository's nonzero development rates are accounting placeholders, **not** actual South African infrastructure chargeback rates.

## Secrets

The Kustomization **does not yet include** the three operator-generated SealedSecret files. This keeps CI rendering valid while preventing anyone from mistaking placeholder ciphertext for working credentials. Add the reviewed sealed files and the Kustomization references together in a follow-up PR **before first sync**. The workloads cannot start successfully without the named Secrets.

Required keys are:

| Secret | Keys |
| --- | --- |
| `litellm-db-owner` | `POSTGRES_PASSWORD` |
| `litellm-db-app` | `LITELLM_DB_APP_PASSWORD`, `DATABASE_URL` |
| `litellm-credentials` | `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `ACE_VLLM_API_KEY`, `ACE_VLLM_BASE_URL` |

**Critical:** Plaintext Secret JSON input is generated and stored solely in the ignored protected private directory (mode 0700); seal using the existing direct CLI workflow. Use securely escrowed master key, salt and database passwords. Do not rotate database passwords without updating PostgreSQL roles on retained volumes; the init script executes only on first initialization. SealedSecrets do not replace encrypted, offline recovery storage.

The operator seals existing plaintext Secret JSON via `kubeseal --cert ansible/inventories/private/infra-hpc-qc-k8s.cert --format yaml < secrets/litellm/litellm-db-app.json > argocd/resources/litellm/litellm-db-app-sealed.yaml` (repeat for owner and gateway credentials). Confirm the `metadata.name` and `metadata.namespace=litellm` match the destination; strict sealing is name/namespace-bound. Review ciphertext-only changes before adding the three files to `kustomization.yaml`. Do not generate credentials into shell history, PR comments, command-line arguments or pipeline output. Review the `kubeseal` version and exact options. Never store unsealed secrets in Git.

## ACE site / network topology

- ACE Dev OpenStack edge: `ace-edge-01` public floating IP `196.24.241.108`, private `10.70.0.10`; WireGuard site-to-site via `wg-fabric`.
- A100 vLLM: `gpu-a100-01` `10.70.0.20:8000` (`qwen3.5-27b`); second A100 `gpu-a100-02` `10.70.0.21` is not an automatically approved backend.
- Sebowa Kubernetes connects to the ACE private subnet through the existing WireGuard federation. Do not point LiteLLM at the ACE public floating IP.
- Only the local authenticated vLLM `GET /v1/models` was confirmed so far; **cross-site pod-to-A100 routability and return routes are not yet proven**.

## Networking

Keep the existing default deny. Add a **separately reviewed** narrowly scoped egress NetworkPolicy selecting only LiteLLM Pods with destination `<verified ACE IPv4>/32` TCP/8000. Do not publish guessed private IPs or permit all egress. If the IP and route are sensitive, manage the additional policy in protected GitOps configuration; do not apply it ad hoc. Validate route, Cilium, OpenStack SG, nftables and vLLM ACL before any live test.

## Deployment ordering

1. Merge the YAML fix from PR #150 into dev, validate full Kustomize output in CI, then promote the reviewed change to main. Argo CD apps currently follow **main**.
2. Inspect SealedSecrets controller / cert, Cinder `SSD` backing, PostgreSQL PVC retention and backups.
3. Create trusted protected secrets, resolve/pin/scan LiteLLM gateway and migration **same digest**, verify Prisma migration procedure, network policy, and actual costs.
4. **Only after operator authorization:** manual Argo sync LiteLLM, inspect Postgres first, migrate, then gateway; provision restricted ACP virtual key using operator-only channel (never mount master key in ACP).
5. Reseal `acp-model` with restricted ACP key; manually sync ACP; execute M4a destructive PostgreSQL continuity drill and attach evidence to ACP issue #21.

Paperclip and scientific workflow rollouts remain separate.
