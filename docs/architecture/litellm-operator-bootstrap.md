# LiteLLM operator bootstrap — do not sync until reviewed

## Workstation boundary

**blackmyth (Arch):** Git, Ansible, Terraform, kubeseal and Python operator tools. Do **not** assume local kubectl or yamllint. Use GitHub Actions for yamllint/Kustomize/schema validation. **k8s-cp-01:** kubectl and Argo CD inspection/manual human-approved sync. No production action by the agent.

## Required private inputs

- Site SealedSecrets certificate copied from the currently deployed controller and verified with the cluster operator (historically \`ansible/inventories/private/infra-hpc-qc-k8s.cert\`; verify correct certificate/current namespace and controller before use).
- Protected vLLM bearer key from the existing A100 deployment (do not paste it into PRs or chat).
- Verified private A100 IP and route through wg-fabric; ensure TCP/8000 is reachable **from pod CIDRs**, not only an edge node.
- A **verified digest** for \`ghcr.io/berriai/litellm:v1.90.2\`, identical in deployment and migration Job; confirm command line and dependency chain. Do not infer a digest from the tag or use latest. Obtain via \`skopeo inspect --raw docker://ghcr.io/berriai/litellm:v1.90.2\` or \`crane digest ghcr.io/berriai/litellm:v1.90.2\` on a trusted equipped runner. Check the registry's multi-arch index vs the selected architecture. Verify provenance and vulnerability advisories before deployment. **Never sync with unverified tags.**
- Actual cost rates for self-hosted hardware. The repository's nonzero development rates are accounting placeholders, **not** actual South African infrastructure chargeback rates.

## Secrets

The Kustomization **does not yet include** the three operator-generated SealedSecret files. This keeps CI rendering valid while preventing anyone from mistaking placeholder ciphertext for working credentials. Add the reviewed sealed files and the Kustomization references together in a follow-up PR **before first sync**. The workloads cannot start successfully without the named Secrets.

Required keys are:

| Secret | Keys |
| --- | --- |
| \`litellm-db-owner\` | \`POSTGRES_PASSWORD\` |
| \`litellm-db-app\` | \`LITELLM_DB_APP_PASSWORD\`, \`DATABASE_URL\` |
| \`litellm-credentials\` | \`LITELLM_MASTER_KEY\`, \`LITELLM_SALT_KEY\`, \`ACE_VLLM_API_KEY\`, \`ACE_VLLM_BASE_URL\` |

**Critical:** The generator must be paired with a secure existing master-key/salt recovery process before operational use. Do not rotate database passwords without updating PostgreSQL roles on retained volumes; the init script executes only on first initialization. SealedSecrets do not replace encrypted, offline recovery storage.

A future approved operator run can create strictly scoped ciphertext directly. Do not generate credentials into shell history, PR comments, command-line arguments or pipeline output. Review the \`kubeseal\` version and exact options. Never store unsealed secrets in Git.

## Networking

Keep the existing default deny. Add a **separately reviewed** narrowly scoped egress NetworkPolicy selecting only LiteLLM Pods with destination \`<verified ACE IPv4>/32\` TCP/8000. Do not publish guessed private IPs or permit all egress. If the IP and route are sensitive, manage the additional policy in protected GitOps configuration; do not apply it ad hoc. Validate route, Cilium, OpenStack SG, nftables and vLLM ACL before any live test.

## Deployment ordering

1. Merge the YAML fix from PR #150 into dev, validate full Kustomize output in CI, then promote the reviewed change to main. Argo CD apps currently follow **main**.
2. Inspect SealedSecrets controller / cert, Cinder \`SSD\` backing, PostgreSQL PVC retention and backups.
3. Create trusted protected secrets, resolve/pin/scan LiteLLM gateway and migration **same digest**, verify Prism migration procedure, network policy, and actual costs.
4. **Only after operator authorization:** manual Argo sync LiteLLM, inspect Postgres first, migrate, then gateway; provision restricted ACP virtual key using operator-only channel (never mount master key in ACP).
5. Reseal \`acp-model\` with restricted ACP key; manually sync ACP; execute M4a destructive PostgreSQL continuity drill and attach evidence to ACP issue #21.

Paperclip and scientific workflow rollouts remain separate.
