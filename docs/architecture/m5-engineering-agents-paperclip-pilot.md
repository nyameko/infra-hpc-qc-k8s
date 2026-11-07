# M5 engineering agents — deploy upstream tools, not another orchestrator

**Stage: source-only operator runbook, unexecuted.** Human approval is required
to allocate any CPU/GPU, add a Discord app/bot, issue a LiteLLM key, start
untrusted code execution, or deploy against an existing ACE/Sebowa host.

## Responsibility boundaries

| Component | What it actually owns | What it never owns |
| --- | --- | --- |
| ACP + Quantum Platform | Human identity, PI membership, approved research conversations, durable memory, browser pairing, explicit privileged approvals | Terminal panes or arbitrary OS commands |
| Herdr + tmux | Per-user terminals, panes, running agents, detach/reattach, named sessions | ACP identity; it must not claim terminal scrollback is canonical research history |
| Paperclip | Isolated **engineering pilot** task assignment, agent status, budget and coordination | Production changes, user research data, Slurm allocations |
| OpenCode | Local coding harness; benchmark with restricted self-hosted OpenAI-compatible route | Global repo access, unattended deploy |
| Hermes / PydanticAI | Existing personal assistant and alternate local harness tests | New independent conversation database |
| OpenHands | Optional sandboxed execution/IDE research; only where basic OpenCode+Herdr fails | Host Docker socket, production SSH keys, default approval path |
| LiteLLM | Restricted virtual keys, quotas, logical model names, traffic to vLLM | User membership policy or scientific scheduler |
| Slurm / Axis Atmos | Approved CPU/H200 research allocations | Agent framework/terminal history |

Do not deploy every harness. **First choose one of OpenCode or Hermes**, run
one safe coding task with a local model, add Paperclip coordination when the
two-agent task genuinely needs it. No broad model-router rewrite.

## Pinned Paperclip canary (disposable sandbox only)

Upstream has a documented single-container quickstart with embedded state.
Use its **unchanged upstream compose file** rather than inventing a new
deployment wrapper. Review release changes before a future version bump.

- Paperclip release `v2026.1106.0` commit:
  `d69631b01b9c658f80bf8bed389863dce82643e1`.
- Upstream config:
  `docker/docker-compose.quickstart.yml`, with
  `PAPERCLIP_DEPLOYMENT_MODE=authenticated` and
  `PAPERCLIP_DEPLOYMENT_EXPOSURE=private`.
- Requires Node 24+ only if deploying the npm CLI; the upstream Docker build
  includes its own runtime.
- Run on a **disposable, network-filtered sandbox VM**. Do not mount host
  Docker socket, infrastructure repositories, Kubernetes kubeconfig, real
  research homes or production database storage. Use a dedicated, private
  data directory with a tested recovery policy.

After operator approval, on the isolated sandbox host:

```bash
git clone https://github.com/paperclipai/paperclip.git paperclip-pilot
cd paperclip-pilot
git checkout --detach d69631b01b9c658f80bf8bed389863dce82643e1
git rev-parse HEAD   # must equal pinned commit
# Review Dockerfile + docker/docker-compose.quickstart.yml before building.
# Private .env in docker/ is owned by the operator, chmod 0600:
# BETTER_AUTH_SECRET=<unique persistent 32+ random bytes>
# PAPERCLIP_TOOL_ACTION_SIGNING_SECRET=<independent random secret>
# PAPERCLIP_PUBLIC_URL=http://localhost:3100
# PAPERCLIP_PORT=127.0.0.1:3100
# PAPERCLIP_DATA_DIR=<dedicated private data path>
# OPENAI_API_KEY=<restricted non-master LiteLLM virtual key>
docker compose --env-file docker/.env -f docker/docker-compose.quickstart.yml config
# Inspect the rendered configuration privately; never paste it into PR logs.
docker compose --env-file docker/.env -f docker/docker-compose.quickstart.yml up --build -d
```

Do **not** create `docker/.env` from this README without operator secret
custody; never copy keys into GitHub, shell history or terminal scrollback.
The compose port should bind `127.0.0.1:3100` only and be accessed with
an authorized SSH tunnel from a trusted workstation. Validate with
`docker compose ps` and a signed-in browser. No public DNS or listener.

Paperclip's internal database is **not ACP Postgres** and must not be
treated as canonical research history. Only share opaque task/PR references.

## Restricted model routing and agent test

Current infra already has an **ACE A100 vLLM Ansible role** and LiteLLM
logical model `research-general` with upstream `Qwen3.5-27B` candidate.
Do not claim running weights without a real authenticated `/v1/models`
and completion test. H200 inference is a separate allocation in [#267](https://github.com/nyameko/infra-hpc-qc-k8s/issues/267).

Pilot logical names: `research-general` for explanations, and proposed
`code-interactive` for a reviewed open-weight coder after compatibility,
license, source weight revision, tokenizer/context, GPU-memory and
prompt/tool-use benchmarking. Names do not imply a model is available.
Never put `LITELLM_MASTER_KEY` into Paperclip, OpenCode, Herdr or Discord.

Two-agent scenario:
1. Operator creates disposable GitHub issue and one restricted dev branch in
   a **throwaway** project; model/harness works with one local virtual key.
2. Engineer proposes a small code diff, reviewer checks correctness and
   tests. Paperclip tracks tasks/budget; Herdr shows running panes/status.
3. Human approves a **draft PR to dev only**. No autonomous merge, host
   provisioning, Terraform apply, Slurm submit or production deployment.
4. Verify revocation/budget denial, cancellation, no hidden remote provider
   fallback, no reading another user's files and retention of audit records.

## Discord pilot (minimum acceptable)

Use an operator-created app, not a server-wide listener with privileged
permissions. First stage: **outbound-only opt-in notifications** for public or
pre-approved non-sensitive job/agent state:
`engineering PR review needed`, `job completed`, `agent blocked`.
Transmit no raw prompts, file paths, usernames, conversation UUIDs, private
datasets or tokens to Discord. Apply channel allowlist, rate limiting and
deduplication. Keep webhook secret in Vault/SealedSecret; rotate upon leak.

A later **inbound** `/status` or `/help` command must verify Discord
interactions' Ed25519 signature, timestamp, replay protection, guild/channel
allowlist and authenticated account linking. Return metadata only. All
privileged actions must link to authenticated Quantum Platform with MFA; no
Discord job submission, PR merge, device pairing or production approvals.

The bot is not connected or installed by this doc. Discord server owner
must authorize the app and give explicit channel/permission scope.

## Gates for 'deployed'

- Local model completion + vLLM source and image revision captured; restricted
  LiteLLM virtual key; no public inference ports.
- One bounded agent run, review, cancel, CPU/GPU time budget denial and
  actual human-approved draft PR to dev.
- Paperclip UI authenticated and blocked outside authorized tunnel;
  unprivileged runner cannot read ACP/production or host socket.
- Discord outbound redacted notification delivered to opted-in channel;
  rejected app/channel not delivered; no token in logs.
- ACP browser, Jupyter and terminal human M4 gates complete separately.
