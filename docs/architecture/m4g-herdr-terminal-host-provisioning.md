# M4g — Herdr/tmux/optional-zsh terminal host provisioning through Ansible

**Status:** Herdr v0.9.5, tmux and zsh are operator-verified on `login1`
and `login2`; **the optional ACP CLI is not installed** and the M4g
cross-client continuity acceptance is still outstanding. This is
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

**ACP installation is the missing M4g link.** The role's default remains
`research_terminal_clients_acp_cli_enabled: false`; it now pins the
promoted ACP #93 source commit (`583de1600e540e0907e8d7a746a62884b97e3195`)
and publishes a guarded `/usr/bin/acp` symlink (the `/usr/local/bin`
directory is **not** in the research login PATH). First check available
interpreters without changing hosts:

```bash
ansible -i inventories/private/hosts.yml slurm_login \
  -m shell -a 'command -v python3.14 || command -v python3.13 || python3 --version'
```

The optional client requires Python 3.13 or 3.14. **Do not enable** the role
until an authorized, compatible interpreter exists on each target; Python
3.9's system executable does not satisfy the package's pinned requirements.
Set the interpreter absolute path via `research_terminal_clients_acp_cli_python`
if different from the default, then preview the explicit opt-in:

```bash
ansible-playbook -i inventories/private/hosts.yml \
  playbooks/research-terminals.yml --limit slurm_login \
  -e research_terminal_clients_acp_cli_enabled=true --check --diff
```

After an operator has reviewed the target/runtime and granted installation
approval, run the same command without `--check --diff`. This installs the
existing CLI in an isolated `/opt/acp-terminal-client` virtual environment;
it does not alter anyone's login shell or Slurm services. Verify:

```bash
ssh login1 'command -v acp && acp --help'
ssh login2 'command -v acp && acp --help'
```

**Actual command** (inside an authorized login terminal or Herdr pane):

```bash
acp --url https://quantum.nyameko.com --browser-pair session
```

The resulting interactive prompt is `acp>`. Type `chats`, `memories`,
`show <real-uuid>` **only inside that prompt**. Do not paste `acp>`
into Bash, and do not paste angle-bracket placeholder values literally.
Approval lasts about 300 seconds and must be renewed explicitly using
`connect` when expired. Current memories are retrieved from ACP after
an owner-scoped authorization check; the terminal cannot itself create
private memories or override owner permissions.


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

## Shared storage versus shell home

The existing `storage-nfs-01` exports shared research data and user homes
under `/home/research`, `/datasets`, and `/staging`. An NFS mount at
`/home/research` does **not** mean an administrative user's `/home/nyameko`
is also NFS-backed. The actual mount for each account must be checked with
`findmnt -T "$HOME"` after login. Keep research home ownership and POSIX
permissions unchanged, even if admins cannot inspect another researcher's
private directory.

Herdr is installed at `/usr/local/bin/herdr` and published via a guarded
`/usr/bin/herdr` symlink to support Rocky login environments that do not
include `/usr/local/bin` in the default `PATH`. No user or global shell
configuration is changed. If `/usr/bin/herdr` is an unrelated binary, Ansible
fails instead of overwriting it. Verify with:

```bash
ls -l /usr/local/bin/herdr /usr/bin/herdr
command -v herdr && herdr --version
getent passwd "$USER" | cut -d: -f7
findmnt -T "$HOME" -o SOURCE,TARGET,FSTYPE
findmnt -T /home/research -o SOURCE,TARGET,FSTYPE
```

`zsh` and Zim remain **explicit per-user opt-in**. A user who installed Zim
on login2's local `/home/nyameko` will not automatically get it on login1.
To share the same config while retaining separate home directories, use a
reviewed per-user synchronization of `~/.zshrc`, `~/.zimrc` and `~/.zim`;
do not modify `/etc/profile`, account login shells, Slurm or private research
homes. The same NFS mount can be visible to compute nodes; avoid shared
automatic shell-switching logic.

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
