# M4a — LiteLLM single-backend inference gateway (draft rollout)

## Decision and milestone boundary

M4a's acceptance is **durable, tenant/subject-isolated conversation, message, task and run history in ACP PostgreSQL**, independent of browser, personal worker, Hermes cache and inference backend. LiteLLM is supporting M4a infrastructure, **not** an ACP canonical state store, and does not move M4b–M4g into M4a.

Deploy a small **single replica**, internal **no-database** LiteLLM proxy for the initial model path:

```text
ACP personal/admin workers -> LiteLLM ClusterIP:4000 (research-general)
                         -> ACE A100 vLLM:8000 (qwen3.5-27b)
                         -> later Axis H200 provider (additional backend)
ACP PostgreSQL -> canonical projects, conversations, messages, tasks/runs
```

Why single backend now: keep A100 operational and prove M4a state first. Do not introduce silent external provider fallback, Redis, Paperclip, per-user routing, another PostgreSQL database, public ingress, or new Slurm changes as M4a requirements.

**Important limitation:** With no LiteLLM database, requests use the **gateway master key** (administrator credential); there are no virtual keys, reliable spend budgets or per-user accounting. For production multi-user access, migrate to a separate LiteLLM persistence store and issue narrowly scoped virtual keys **before** exposing the gateway to general users. For M4a the only accepted clients are protected internal ACP workers. Keep usage and quota policy in ACP; do not claim LiteLLM enforces them in this mode.

## Repo/GitOps

- `argocd/applications/litellm.yaml`: manual-first-sync Application, tracks protected `main`.
- `argocd/resources/litellm/`: one Deployment, private ClusterIP, ConfigMap, Kubernetes NetworkPolicy, namespace.
- `argocd/resources/agent-control-plane/`: ACP `ACP_MODEL=research-general`, `ACP_MODEL_BASE_URL=http://litellm.litellm.svc.cluster.local:4000/v1`, narrow egress to gateway.
- `agent-control-plane` remains owned by its own GitOps Application and PostgreSQL migrations.

The branch must be reviewed and merged to `dev`, tested, then promoted to `main` under the release procedure **before** Argo CD's `main` applications can see it. Do not manually `kubectl apply` these directory manifests or alter production GitOps targets as a workaround. No Argo CD sync has been performed by this change.

## Prerequisites — do not initiate first sync until all verified

1. From `k8s-cp-01`, verify six nodes Ready, Cinder CSI/storage class or the declared `cinder-agent-retain` class with verified Cinder `SSD` volume type, sealed-secrets-controller Ready, and Argo CD permissions. The ACP namespace/storage class are expected to be missing until the first successful ACP sync.
2. Verify the chosen LiteLLM image exists at the pinned version `ghcr.io/berriai/litellm:v1.90.2`, resolve a valid release digest, scan/confirm supply chain, then **pin by digest** for production. Confirm the CLI flags and probes for that exact image.
3. Create a **SealedSecret** named `litellm-credentials` in namespace `litellm` using the site controller certificate, with keys:
   - `LITELLM_MASTER_KEY`: long random private gateway admin key (do not commit plaintext).
   - `ACE_VLLM_API_KEY`: the bearer secret already used by vLLM (do not commit plaintext).
   - `ACE_VLLM_BASE_URL`: verified protected destination such as `http://<ACE-VLLM-PRIVATE-ADDRESS>:8000/v1`; preserve the URL in private configuration.
   Existing `acp-model` SealedSecret must be **re-sealed** with `ACP_MODEL_API_KEY` equal to the gateway key for this initial *internal-only* design. Distinguish this from the A100 bearer key and do not accidentally reuse the A100 key as the gateway key.
4. Preserve the present **default deny**. A separately reviewed **protected** network policy must allow LiteLLM pod egress only to the verified ACE /32 on TCP 8000 and routing must work via `wg-fabric`. The public manifests intentionally do **not** publish that private CIDR or permit arbitrary egress. Verify any existing ACE nftables, Cilium, OpenStack SG and Sebowa fabric forwarding requirements; do not change unrelated firewall/security controls.
5. Test LiteLLM from an authenticated internal pod/service, not through an internet-facing ingress. The gateway master key must remain unreadable to browsers, student namespaces or arbitrary users.
6. Verify ACP sealed DB owner/app/verification secrets, pinned images, PostgreSQL PVC retention and migration job before ACP sync.

## Controlled acceptance sequence (operator-run, not performed)

On A100, confirm vLLM model listing and one `/v1/chat/completions` with the protected A100 bearer token; avoid displaying it.

From `k8s-cp-01`:
```sh
kubectl -n argocd get applications litellm agent-control-plane
kubectl get storageclasses
kubectl -n kube-system get deployment sealed-secrets-controller
```

After merge/promotion, sealed-secret review and secure backend egress:
- Manually sync **LiteLLM** through Argo CD; `kubectl -n litellm get deploy,svc,pod,networkpolicy`; inspect /health/readiness from an authorized source. Probe `/v1/models` and one small chat completion with `research-general` and the gateway credential. Record route status, not keys.
- Manually sync **ACP** after storage/secret checks; observe PostgreSQL PVC readiness, migration job, API and personal/admin workers.
- Conduct the M4a **ACP-PERSIST-7F31** destructive drill: stable project/conversation UUIDs; canonical transcript/task/run history survives browser and worker loss, API restart and runtime-local cache loss; cross-user reads denied; continue a conversation from an authorized alternate surface. Do not mark M4a done based on LiteLLM HTTP 200 alone.

## H200 in parallel, but not an M4a blocker

Once the Axis AccessProvider/tunnel policy and provider authorization are established, add an H200 vLLM backend as another **reviewed** LiteLLM model route. Keep backend credentials separate, do not enable automatic failover across privacy boundaries, and do not allow ACP/clients to rely on hardcoded hostnames. H200 integration is optional for first M4a acceptance.

## Deferred work

- ACP M4b: explicit scoped/provenanced long-term memory.
- M4c: rich projects/workspaces/task scopes.
- M4d: governed skills.
- M4e: richer Hermes profiles.
- M4f: Quantum Platform Guide.
- M4g: SSH Enterprise Client.
- Org-mode/Org-roam-first and secondary Markdown/Obsidian export: tracked in [agent-control-plane issue #20](https://github.com/nyameko/agent-control-plane/issues/20), **not part of M4a acceptance**.

## References

- [LiteLLM production/deployment](https://docs.litellm.ai/docs/proxy/deploy)
- [LiteLLM running without a DB and its limits](https://docs.litellm.ai/docs/proxy/docker_quick_start)
- [ACP M4 persisted history](https://github.com/nyameko/agent-control-plane/blob/dev/docs/M4-PERSISTENT-AGENTS.md)
