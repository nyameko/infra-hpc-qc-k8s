# M4g — Herdr/tmux terminal host provisioning through Ansible

**Status:** opt-in source deployment recipe, not live installed. This is
terminal ergonomics for M4g and optional engineering agent sandboxes,
**not an ACP authentication broker, a scheduler or a research agent**.

## Host roles, smallest useful implementation

- **Terraform**: ACE/Sebowa VM, NIC, private subnet and security group, only
  if a new VM is actually needed. Existing login nodes need no Terraform
  change. Expose SSH only through existing approved WireGuard/jump paths;
  never open Herdr socket or vLLM port 8000 to the Internet.
- **Ansible**: approved Rocky Linux login/jump host with `tmux`, `git`,
  `jq`, and Herdr v0.9.5 binary installed at `/usr/local/bin/herdr`.
  The upstream **GitHub release asset digest** is verified on download.
  Idempotent `get_url`; no `curl | sh`, no unreviewed auto-update, no root
  Herdr daemon, no `sshd` edits and no service restart.
- **Herdr**: started by **each authenticated user in their own SSH login**,
  per-user sockets/workspaces. Unlike ACP, Herdr owns local pane/session
  state and detected agent status. Users can choose Herdr, tmux, or an
  ordinary shell; never replace the login shell automatically.
- **ACP**: canonical PostgreSQL conversations, per-user authorization,
  projects, memories and browser-approved terminal pairing. The `acp`
  command is installed separately through its reviewed package/source;
  Herdr does NOT identify the user or bypass ACP access checks.
- **Slurm**: existing job scheduler and execution/accounting. Herdr/tmux
  runs on login/client hosts, not on compute nodes as new management daemons.
- **Model inference**: separately hosted A100/H200 vLLM behind restricted
  LiteLLM logical models. No agent gets master gateway credentials.

## Operator installation after host review

Use a protected Ansible inventory with an explicit `research_terminals`
group. The inventory example is a shape only; it is not a deployed ACE host.
On a machine authorized for infrastructure operations (not `k8s-cp-01`):

```bash
cd ansible
ansible-playbook -i inventories/PRIVATE.yml playbooks/research-terminals.yml --check --diff
# After separate human authorization:
ansible-playbook -i inventories/PRIVATE.yml playbooks/research-terminals.yml
```

This installs a binary and OS utilities; no Herdr process is started.
From a normal researcher session:

```bash
command -v herdr && herdr --version
command -v tmux && tmux -V
herdr
# or use tmux / existing shell
```

From a workstation with Herdr configured to connect to an approved SSH host,
`herdr --remote <ssh-host-alias>` uses the existing OpenSSH transport and
per-user remote session. Do not give a cross-user socket to a central agent.

Pinned upstream asset/source:
[Herdr v0.9.5 release](https://github.com/herdrdev/herdr/releases/tag/v0.9.5)
and [official SSH use](https://herdr.dev/tui/docs/how-to-work/).

## Testing / rollback

CI: Ansible syntax check/lint; compare the downloaded SHA-256 with the pinned
release asset. Staging on a synthetic Rocky host: first run changes packages
and binary, second run idempotent, no listening sockets, no SSH/Slurm changes.
Human acceptance: normal SSH shell still works; `tmux` is optional; Herdr
status/panes persist across client disconnect without altering ACP histories.
If Herdr fails, use normal SSH shell or tmux. Roll back by removing the
specific binary through a reviewed Ansible change; do not delete user state.

**No OpenHands/Paperclip orchestrator deployment is implied.** They may run
later in separate restricted, disposable sandboxes with pinned images and a
fine-grained GitHub App, after real authenticated ACP continuity is verified.
