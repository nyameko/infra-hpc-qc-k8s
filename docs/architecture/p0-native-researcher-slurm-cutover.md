# P0 — Native researcher Slurm SSH, no privileged gateway

**Status: source migration ready for operator review, NOT deployed or live accepted.**
This is an explicit two-phase cutover; do not apply to production until the
current Quantum Platform `execution_api` dependency on the shared key is
removed or replaced. P0 is not closed by merging this PR.

> **Scientific preparation is cheap; expensive execution is scheduled.**

## Existing risk

The previously deployed `jupyterhub-gateway` forced-command SSH key could
invoke a root-owned helper through passwordless sudo. That helper accepted
a username argument and used `runuser` for `sbatch`/`scancel`. Even though
its most recent cancellation branch checked ownership, it retained a
privileged identity-selection service in the scheduler trust path.

**P0 replacement:** authentication terminates at OpenSSH as the actual
researcher POSIX account. User runs *unmodified* Slurm binaries on the
existing authorized login host:

```text
JupyterHub CPU workbench / researcher SSH client
    -> ssh user@approved-login (researcher's own private key)
    -> login sshd maps user to that exact POSIX identity
    -> sbatch / squeue / sacct / scancel (native Slurm/MUNGE)
    -> Slurm enforces association, ownership, QOS, partition and limits
```

No shared job-management key, no sudo command selector, no
root-run Slurm helper, no browser-based SSH terminal and no new scheduler.

## Source implementation in this PR

- `researcher_slurm_ssh` installs the platform-approved, **public** per-user
  SSH keys in a root-owned allowlist on the login host. The private key is
  held by the researcher (optionally in their 0700 home, for Jupyter use),
  **never** by Quantum Platform's shared API pod.
- Every platform-managed POSIX researcher belongs to a special SSH Match
  group, including revoked users. Disabled researchers have empty root-owned
  key files; no fallback to user-editable `~/.ssh/authorized_keys`.
  Keys must be inventoried from approved active Quantum Platform `SSHKey`
  records in **protected Ansible inventory**. This is a pilot reconciliation
  path; automatic registration/revocation propagation requires a separately
  reviewed trusted synchronizer.
- `research-identities.yml` provisions per-user access after UID/GID/Slurm
  associations. `jupyterhub-slurm.yml` no longer installs the legacy gateway.
- Old helper/templates/defaults/tests are removed from source.
- `slurm-retire-shared-gateway.yml` removes installed sudoers, helper,
  forced entrypoint and service account **only after** operator confirmation
  and a coordinated Quantum Platform API/secret cutover. It is NOT invoked
  by normal provisioning and requires an explicit boolean confirmation.

## Private inventory example (not credentials)

```yaml
research_users:
  - name: <APPROVED_USER>
    uid: <PROVISIONED_UID>
    gid: <PROVISIONED_GID>
    execution_enabled: true
    ssh_public_keys:
      - "ssh-ed25519 <PUBLIC_KEY_BASE64> <comment>"
```

Only real active public keys from the user's account may be installed. Never
generate or store a private researcher key in the platform backend or the
public repo. The researcher may generate their *own* dedicated SSH key in
Jupyter under private `~/.ssh` and register its public half with their
Quantum Platform account. The Jupyter CPU image includes the ordinary OpenSSH client (no shared key). Ensure the Jupyter single-user runtime uses
the same POSIX UID/GID as site SSH, and SSH host-key pinning is verified
out of band. A registered public key alone is **not** proof that it has
reached the login host.

## Deployment/cutover HOLD: operator action in another chat

1. Inventory current direct native Slurm SSH and remote user admission on
   ACE. Confirm research account, UID/GID, Slurm association and network;
   keep recovery/admin SSH out of the Match group.
2. Reconcile **active** research public keys into protected inventory.
   Review `Match Group` SSH block position/compatibility, validate
   `sshd -t`, perform a separate approved `sshd` reload.
3. Authenticate as a dedicated real researcher (not `sudo -u`,
   `runuser`, or shared service user). Do an operator-observed
   own-job submit/status/history/cancel. Test cross-user cancellation
   only against a **disposable** second user's job in an authorized
   maintenance window; verify denial and that job remains active.
4. **Before retiring the service key:** replace or deactivate Quantum
   Platform's existing `_gateway` execution transport and rotate
   the sealed shared credential. Until then, retiring it would break
   existing `/runs/` API submission/history/cancellation. Notebook
   native submission is a working *candidate* path, but not proof that
   portal operations are migrated.
5. With rollback and production deployment explicitly approved, invoke
   the isolated retirement playbook using
   `-e slurm_legacy_gateway_retirement_approved=true`. Check that
   shared key has been removed from K8s Secret/Pod and cannot SSH.
   Do not delete an active account while a job/session depends on it.
6. Verify new user acceptance and monitor for regressions. Record
   who ran each real job, job/account/partition, denial test,
   `sacct` result and exact commit/image revision.

## P0 acceptance script and evidence (manual, researcher session)

The source-controlled `tests/ansible/p0-researcher-slurm-acceptance.sh` is an
**operator-observed** native Slurm test, not a privileged gateway:

```bash
# Inside nlisa's own authenticated SSH session on the ACE login host:
bash tests/ansible/p0-researcher-slurm-acceptance.sh --inspect
bash tests/ansible/p0-researcher-slurm-acceptance.sh --submit-hello
# Inspect the printed Slurm job ID via squeue, sacct and owned result file.
bash tests/ansible/p0-researcher-slurm-acceptance.sh --submit-cancel-test
# Then inspect User ownership, cancel only that disposable job via scancel.
```

The script does not run any tests by default, cannot be executed as the
service/root account and will never cancel an allocation automatically.
Record `JobIDRaw,User,Account,State,ExitCode,Elapsed,AllocTRES`,
researcher UID/GID and operating host. For the **negative** ownership
test, a second cooperating test researcher must create their own disposable
sleep job; `nlisa` then attempts `scancel <other_test_job_id>` and Slurm
must deny the operation while that job remains active. Do not use another
person's real work. The check must be verified by the facility operator.

## P0 evidence packet (manual, researcher session)

Run these as the researcher's *own account* on the site-authorized login
node after checking SSH key and known-host fingerprints:

```bash
id -un
id -u
sacctmgr -nP show association where user=$USER \
  format=Cluster,Account,User,Partition,QOS
sinfo -N -o '%N|%P|%G|%T'
sbatch --parsable --job-name=p0-native-smoke --time=00:05:00 --wrap='/bin/hostname'
squeue -u "$USER" -o '%i|%u|%T|%P'
sacct -X -nP -u "$USER" --format=JobIDRaw,User,State,ExitCode,AllocTRES
```

For cancellation, submit a separate disposable sleep job *as that user*,
then `scancel <own_job_id>`; verify terminal status with `sacct`.
For negative ownership, use a separately created disposable job belonging
to another approved **test** researcher; a cancellation attempt must be
denied by native Slurm and the job remain running. Never test this on a
real research workload. Portal browser parameters must not select the
scheduler identity; platform UID/GID records and login POSIX mapping must
match.

**No H200 GPU configuration is assumed.** P1 inventories the true
ACE/A100 and Axis/H200 schedulers, devices, GRES, cgroups and usage policy.
