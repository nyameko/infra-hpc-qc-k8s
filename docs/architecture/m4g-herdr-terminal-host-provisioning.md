# M4g — Herdr/tmux/optional-zsh terminal host provisioning through Ansible

**Status:** opt-in source deployment recipe, not live installed. This is
terminal ergonomics for M4g and optional engineering agent sandboxes,
**not an ACP authentication broker, a scheduler or a research agent**.

## Host roles, smallest useful implementation

- **Terraform**: ACE/Sebowa VM, NIC, private subnet and security group, only
  if a new VM is actually needed. Existing login nodes need no Terraform
  change. Expose SSH only through existing approved WireGuard/jump paths;
  never open Herdr socket or vLLM port 8000 to the Internet.
- **Ansible**: approved Rocky Linux login/jump host with `tmux`, `zsh`, `git`,
  `jq`, and Herdr v0.9.5 binary installed at `/usr/local/bin/herdr`.
  The upstream **GitHub release asset digest** is verified on download.
  Idempotent `get_url`; no `curl | sh`, no unreviewed auto-update, no root
  Herdr daemon, no `sshd` edits and no service restart.
- **Herdr**: started by **each authenticated user in their own SSH login**,
  per-user sockets/workspaces. Unlike ACP, Herdr owns local pane/session
  state and detected agent status. Users can choose Herdr, tmux, or an
  ordinary shell; never replace the login shell automatically.
- **ACP**: canonical PostgreSQL conversations, per-user authorization,
  projects, memories and browser-approved terminal pairing. The existing ACP `acp` CLI is optionally installed by this role from a
  pinned ACP Git commit into an isolated Python virtual environment, once an
  approved Python 3.13/3.14 runtime is available on the login host;
  Herdr does NOT identify the user or bypass ACP access checks.
- **Slurm**: existing job scheduler and execution/accounting. Herdr/tmux
  runs on login/client hosts, not on compute nodes as new management daemons.
- **Model inference**: separately hosted A100/H200 vLLM behind restricted
  LiteLLM logical models. No agent gets master gateway credentials.

## Explicit per-user shell choice — no default changes

The role installs the `zsh` *binary* for anyone who elects to use it. It never
changes `/etc/passwd`, account `shell:` attributes, PAM, `/etc/shells`,
login defaults, system-wide profile files, `~/.bashrc`, `~/.zshrc`,
Slurm `slurm.conf` or any job-submission wrapper.

New and existing users retain their current login shell. Within a login
session a user may optionally run `zsh` and exit back to their original
shell via `exit`. An explicit permanent shell change would be a separate
account-management request; it is **not** part of this playbook. A submitted
Slurm job continues to use its **own shebang**, such as `#!/bin/bash`,
regardless of an interactive `zsh` session.

## Operator installation after host review

Use the **existing** protected Sebowa inventory
`ansible/inventories/private/hosts.yml` and its `slurm_login` group,
which already contains `login1` and `login2`. The `group_vars/`
files are variable definitions, **not inventories**. Do not pass
`inventories/private/group_vars/slurm_login/jupyterhub-gateway.yml`
to `-i`. ACE has a separate inventory and is not targeted by this play.
On a machine authorized for infrastructure operations (not `k8s-cp-01`):

```bash
cd ansible
ansible-inventory -i inventories/private/hosts.yml --graph
ansible-playbook -i inventories/private/hosts.yml playbooks/research-terminals.yml --limit slurm_login --list-hosts
ansible-playbook -i inventories/private/hosts.yml playbooks/research-terminals.yml --limit slurm_login --check --diff
# After separate human authorization, from this same directory:
ansible-playbook -i inventories/private/hosts.yml playbooks/research-terminals.yml --limit slurm_login
```

This installs binaries and OS utilities only; no Herdr process is started, no shell is switched and no Slurm service is changed.
To opt into ACP terminal-client installation, the operator may set
`research_terminal_clients_acp_cli_enabled: true` in protected inventory,
after verifying `research_terminal_clients_acp_cli_python` is a compatible,
already-installed Python interpreter. The optional isolated venv runs the
**existing** M4g browser-paired ACP CLI; it is not a new login protocol.
This opt-in path requires GitHub/Python package access and is intentionally
separate from the basic Herdr/tmux installation.
From a normal researcher session:

```bash
command -v herdr && herdr --version
command -v tmux && tmux -V
getent passwd "$USER" | cut -d: -f7  # must remain unchanged
command -v zsh
# Only for users who opt in interactively:
zsh
# 'exit' returns to original shell
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
Human acceptance: capture the user's login shell before and after deployment
and confirm it is identical; plain `ssh`, `sbatch`, `squeue`, `sinfo` and
a benign `#!/bin/bash` Slurm job continue to work. The optional `zsh` starts
only on user request; tmux is optional; Herdr
status/panes persist across client disconnect without altering ACP histories.
If Herdr fails, use normal SSH shell or tmux. Roll back by removing the
specific binary through a reviewed Ansible change; do not delete user state.

**No OpenHands/Paperclip orchestrator deployment is implied.** They may run
later in separate restricted, disposable sandboxes with pinned images and a
fine-grained GitHub App, after real authenticated ACP continuity is verified.
