# Paperclip M5 — first private, bounded GitOps pilot

**Not yet a production deployment.** This source is intentionally manually
synchronized, not rolled out by the root application's automatic reconciliation.
The separate `argocd/applications/paperclip-pilot.yaml` tracks `main` and
has **no automated syncPolicy**. Root reconciliation may create an OutOfSync
Application object; it must never automatically launch Paperclip.

## Why this minimal slice

Paperclip is the upstream engineering-agent team/task/approval/budget system.
Herdr is the interactive terminal, agent status and resume UI; neither owns
ACP's durable researcher conversations or user-approved memories.
Quantum Platform/ACP remain the trusted identity and research context source.
Do **not** add another heartbeat scheduler, agent orchestrator, custom TUI,
policy DB or scientific CLI.

Source version candidate: upstream
[Paperclip `v2026.1106.0`](https://github.com/paperclipai/paperclip/releases/tag/v2026.1106.0)
at source commit `d69631b01b9c658f80bf8bed389863dce82643e1`.
The upstream Docker workflow builds the **production** image and publishes
`ghcr.io/paperclipai/paperclip:2026.1106.0`; **before first sync**, verify
the actual registry manifest, image labels, architecture and attestations,
then replace the version tag with its immutable `@sha256:...` manifest
digest. No `latest` or `-cloud` images.

### Deliberately small infrastructure

- One unprivileged Paperclip pod, PodSecurity `restricted`, no SA token.
- No ingress, public DNS, NodePort, SSH or cluster-admin credentials.
- Single 20Gi Cinder SSD volume under `/paperclip` for embedded data,
  workspaces, uploads and instance key. Keep backups, verify restore.
- No GPU, root/hostPath/Docker socket, Slurm credentials or research NFS.
- Default-deny ingress/egress; allow DNS and LiteLLM port 4000 only.
  Corresponding allow-from-paperclip ingress is added to LiteLLM policy.
- No unrestricted Internet or GitHub egress: Paperclip UI can boot and
  an approved local model can be tested, but **engineering PR agents cannot
  reach GitHub yet**. Do not claim a working task pilot until a separate
  operator-reviewed, destination-restricted egress and sandbox PR is merged.

### Prerequisites before an approved first sync

1. **M4 human owner:** confirm ACP schema version 8, API/worker digests,
   separated migrations, recovered personal worker, RLS and private-memory
   human tests. No unapproved production DB migration here.
2. **Image:** inspect official GHCR manifest and pin a verified immutable
   digest in `deployment.yaml`. Review runtime filesystem paths and verify
   rootless writeability to the Cinder PVC; a green manifest CI is not runtime
   proof.
3. **Sealed secrets (required):** create `paperclip-pilot-auth` with two
   independent, persistent random secrets:
   `BETTER_AUTH_SECRET` and `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`.
   Keep operator-generated plaintext entirely outside Git and shell
   command-line arguments, encrypt to the current SealedSecrets controller
   certificate, and commit the **encrypted** SealedSecret into this resource
   directory. Add it to `kustomization.yaml` only after review. Never
   rotate these secrets automatically when pods restart.
4. **Restricted inference (optional for UI, required for agent):** operator
   creates `paperclip-pilot-model` from a *restricted* LiteLLM virtual key,
   `OPENAI_API_KEY`, not `LITELLM_MASTER_KEY`; record quota/model and
   deny public/vendor-cloud fallback. Review that Paperclip/OpenCode honors
   `OPENAI_BASE_URL` and actually routes to the internal `research-general`
   model before spending GPU time. If unsupported, add a reviewed adapter
   configuration rather than exposing the master key.
5. **Capacity/backups:** confirm cinder-ssd quota, CPU and memory budget;
   configure an independently stored backup and a proven isolated restore.
   No ACP/Postgres PVC or researcher dataset may be mounted.
6. **Manual activation:** operator uses an authorized ArgoCD administrative
   environment (NOT exploratory arbitrary commands on `k8s-cp-01`) to
   synchronize **only** the `paperclip-pilot` app after all gates. Keep
   automated sync disabled during the pilot.

### Secure local access

From an **authorized Kubernetes workstation** with a scoped kubeconfig
and the operator's explicit permission:

```bash
kubectl -n paperclip-pilot get deployment,pod,pvc,networkpolicy
kubectl -n paperclip-pilot rollout status deployment/paperclip-pilot --timeout=240s
kubectl -n paperclip-pilot port-forward deployment/paperclip-pilot 3100:3100 --address 127.0.0.1
```

The UI is reachable as `http://localhost:3100` on that workstation.
Access via an approved remote SSH tunnel if working from Blackmyth; do not
bind port-forward to 0.0.0.0. Port-forward reachability through default-deny
depends on the CNI's port-forward path: **test it** rather than claiming
success from a healthy pod. No authenticated remote browser access exists
until a separate approved private TLS/WG ingress is designed.

### Activation and acceptance

1. Confirm operator authenticated login, persisted state across a controlled
   single-pod restart, and both signing keys persist unchanged.
2. Test the model connection to approved LiteLLM with a **limited virtual key**,
   verified upstream weight/provider route and no bypass to external vendors.
3. Run one engineer and one reviewer using an already isolated, disposable
   workspace. Before enabling outbound GitHub, review egress and token scope
   **separately**. First action: draft patch to disposable GitHub `dev`
   branch, test/diff review, human approvals. No automatic merge.
4. Check task cancellation, run budget limits, audit and unexpected egress
   denial. No SLURM/SSH admin, ACP memory export or privileged cluster changes.
5. After explicit opt-in, consider upstream Paperclip's existing experimental
   Discord connector for redacted notifications only; do not write a new
   Discord bot unless unsupported requirements are demonstrated.
6. Restore the Paperclip-only volume into a **disposable** environment and
   check that neither ACP nor LiteLLM database state was touched.

### Rollback

Pause Paperclip runs, revoke the limited LiteLLM key and external GitHub
credentials, then in the approved Argo environment scale/suspend **only**
`paperclip-pilot`. Preserve the PVC for investigation and use a reviewed
backup before destructive removal. Do not delete ACP, LiteLLM or Slurm
workloads. No change to a researcher login shell is necessary.

Tracked: [infra #267](https://github.com/nyameko/infra-hpc-qc-k8s/issues/267),
[ACP #89](https://github.com/nyameko/agent-control-plane/issues/89).
