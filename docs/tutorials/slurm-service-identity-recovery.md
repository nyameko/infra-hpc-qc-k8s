# Recovering a Slurm fabric from inconsistent service UID/GID allocation

This tutorial documents a **recovery procedure for an already-installed Slurm
cluster** whose service accounts were created independently on different hosts
and therefore received different numeric UID/GID values.

It is intentionally **not** part of the normal installation or deployment
procedure. New or rebuilt hosts should receive deterministic service IDs during
bootstrap. Use this recovery only when an existing cluster has already drifted.

## Failure signature

The scheduler may appear mostly healthy:

```text
scontrol ping
Slurmctld(primary) at slurm-controller-01 is UP

sinfo -N -l
slurm-cpu-01  idle
slurm-cpu-02  idle
slurm-cpu-03  idle
slurm-cpu-04  idle
```

but task launch fails:

```text
srun: error: Task launch ... failed on node ...:
Header lengths are longer than data received
srun: error: Application launch failed:
Header lengths are longer than data received
```

The compute-node `slurmd` log reveals the real cause:

```text
cred/munge: Unexpected uid (989) != Slurm uid (991)
_verify_signature: failed decode
Malformed RPC of type REQUEST_LAUNCH_TASKS(6001) received
Security violation: REQUEST_PING req from uid 989
```

The important line is the numeric identity mismatch. Slurm and MUNGE
authentication carries numeric credentials. Matching account names are not
enough when `slurm` resolves to different UIDs on different hosts.

## First rule: prove the cause before changing identities

Before performing any migration, rule out the other common causes.

### Check clocks

MUNGE credentials are time bounded. Verify Chrony before changing users:

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_compute' \
  -b \
  -m shell \
  -a '
    echo === $(hostname) ===
    date -Ins
    chronyc tracking
    chronyc sources -v
  '
```

Healthy nodes should report `Leap status: Normal` and small offsets. If nodes
are seconds or minutes apart, repair time synchronization first.

### Check the MUNGE key

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a 'sha256sum /etc/munge/munge.key'
```

Every host must report the same hash. Do not print or copy the actual key.

### Inspect current numeric identities

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    echo === $(hostname) ===
    id slurm
    id munge
    id node_exporter
    id slurm-builder 2>/dev/null || true
  '
```

A real M1 failure looked like:

```text
controller:
  slurm         989:986
  munge         990:987
  slurm-builder 991:988
  node_exporter 992:989

login/compute:
  slurm         991:988
  munge         992:989
  node_exporter 990:987
```

This happened because distro system-user auto-allocation was allowed to choose
the next free IDs independently on each VM.

## Reserved M1 infrastructure service IDs

The M1 fabric reserves the following deterministic identities:

```text
5000:5000  slurm
5001:5001  munge
5002:5002  node_exporter
5003:5003  slurm-builder
```

Slurm and MUNGE equality is protocol-critical. Node Exporter and the RPM builder
do not require matching IDs for their protocols, but deterministic IDs prevent
ownership surprises and make rebuilt hosts reproducible.

Before using a reserved block, verify it is unused:

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    echo === $(hostname) ===
    for id in 5000 5001 5002 5003; do
      echo "--- ID ${id} ---"
      getent passwd "${id}" || true
      getent group "${id}" || true
    done
  '
```

Do not continue if one of the target IDs belongs to an unrelated account.

## Recovery sequence

The recovery is deliberately ordered:

```text
stop Slurm and affected services
        ↓
change numeric groups/users
        ↓
repair filesystem ownership
        ↓
verify no stale ownership remains
        ↓
start MUNGE
        ↓
start slurmdbd
        ↓
start slurmctld
        ↓
start slurmd
        ↓
validate scheduler and task launch
```

MariaDB itself does not need to be stopped for this service-identity migration.

### 1. Stop Slurm compute daemons

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_compute \
  -b \
  -m systemd \
  -a 'name=slurmd state=stopped'
```

### 2. Stop controller daemons

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m shell \
  -a '
    systemctl stop slurmctld slurmdbd
  '
```

### 3. Stop MUNGE everywhere

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m systemd \
  -a 'name=munge state=stopped'
```

While MUNGE is stopped, this error is expected and does not mean the key is
broken:

```text
munge: Error: Failed to access "/var/run/munge/munge.socket.2":
No such file or directory
```

The socket is created by `munged` when the service starts.

### 4. Stop Node Exporter before changing its UID

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m systemd \
  -a 'name=node_exporter state=stopped'
```

If this step is omitted, `usermod` can fail with:

```text
usermod: user node_exporter is currently used by process ...
```

A preceding `groupmod` may already have succeeded, leaving Node Exporter in a
temporary half-migrated state. Stop the service and complete the UID change;
do not attempt to undo the group change.

### 5. Normalize Slurm

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    groupmod -g 5000 slurm
    usermod -u 5000 -g 5000 slurm
  '
```

### 6. Normalize MUNGE

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    groupmod -g 5001 munge
    usermod -u 5001 -g 5001 munge
  '
```

### 7. Normalize Node Exporter

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    groupmod -g 5002 node_exporter
    usermod -u 5002 -g 5002 node_exporter
    if [ -d /home/node_exporter ]; then
      chown -R node_exporter:node_exporter /home/node_exporter
    fi
  '
```

Node Exporter is effectively stateless in this deployment; its binary and
systemd unit are root-owned.

### 8. Normalize the RPM builder on its builder host

For M1 the builder is the Slurm controller:

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m shell \
  -a '
    groupmod -g 5003 slurm-builder
    usermod -u 5003 -g 5003 slurm-builder
  '
```

Repair build-workspace ownership:

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m shell \
  -a '
    [ -d /home/slurm-builder ] &&
      chown -R slurm-builder:slurm-builder /home/slurm-builder
    [ -d /var/lib/slurm-builder ] &&
      chown -R slurm-builder:slurm-builder /var/lib/slurm-builder
    [ -d /var/tmp/slurm-rpm-builder ] &&
      chown -R slurm-builder:slurm-builder /var/tmp/slurm-rpm-builder
    [ -d /var/tmp/slurm-rpmbuild ] &&
      chown -R slurm-builder:slurm-builder /var/tmp/slurm-rpmbuild
    true
  '
```

## Repair ownership

Changing an account's UID/GID does not automatically rewrite every inode that
was owned by the old numeric identity.

### Slurm controller state

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m shell \
  -a '
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    chown -R slurm:slurm /var/spool/slurmctld
    if [ -d /var/log/slurm ]; then
      chown -R slurm:slurm /var/log/slurm
    fi

    stat -c "%U:%G %u:%g %a %n" \
      /etc/slurm/slurmdbd.conf \
      /var/spool/slurmctld
  '
```

Expected ownership includes:

```text
slurm:slurm 5000:5000 600 /etc/slurm/slurmdbd.conf
slurm:slurm 5000:5000 750 /var/spool/slurmctld
```

Do not recursively change MariaDB data ownership. MariaDB has its own service
identity.

### Slurm logs

Some login hosts may not have `/var/log/slurm`. Use an `if` rather than
`[ -d ... ] && ...` as the entire shell command, because the latter returns
exit status 1 when the directory is absent and makes an Ansible ad-hoc task
look like a failure.

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    if [ -d /var/log/slurm ]; then
      chown -R slurm:slurm /var/log/slurm
    fi
  '
```

### MUNGE state

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    chown -R munge:munge /etc/munge
    [ -d /var/lib/munge ] && chown -R munge:munge /var/lib/munge
    [ -d /var/log/munge ] && chown -R munge:munge /var/log/munge
    [ -d /run/munge ] && chown -R munge:munge /run/munge
    chown munge:munge /etc/munge/munge.key
    chmod 0400 /etc/munge/munge.key
    true
  '
```

## Verify the identity namespace

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    echo === $(hostname) ===
    id slurm
    id munge
    id node_exporter
  '
```

Expected on every host:

```text
uid=5000(slurm) gid=5000(slurm)
uid=5001(munge) gid=5001(munge)
uid=5002(node_exporter) gid=5002(node_exporter)
```

Builder host:

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m command \
  -a 'id slurm-builder'
```

Expected:

```text
uid=5003(slurm-builder) gid=5003(slurm-builder)
```

## Find stale ownership before restart

Use the actual old IDs observed during the incident:

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    echo === $(hostname) ===
    find /etc/slurm /etc/munge /var/log/slurm \
         /var/lib/munge /var/log/munge /run/munge \
      -xdev \
      \( -uid 989 -o -uid 990 -o -uid 991 -o -uid 992 \
         -o -gid 986 -o -gid 987 -o -gid 988 -o -gid 989 \) \
      -ls 2>/dev/null || true
  '
```

No relevant stale Slurm/MUNGE ownership should remain.

## Restart in dependency order

### 1. MUNGE

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m systemd \
  -a 'name=munge state=started'
```

Validate:

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    systemctl is-active munge
    munge -n | unmunge | grep -E "STATUS|ENCODE_HOST|DECODE_HOST"
  '
```

### 2. Node Exporter

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m systemd \
  -a 'name=node_exporter state=started'
```

Validate both process health and the HTTP endpoint:

```bash
ansible \
  -i inventories/private/hosts.yml \
  'slurm_controller:slurm_login:slurm_compute' \
  -b \
  -m shell \
  -a '
    systemctl is-active node_exporter
    curl -fsS http://127.0.0.1:9100/metrics >/dev/null &&
      echo "node_exporter metrics OK"
  '
```

### 3. SlurmDBD

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m systemd \
  -a 'name=slurmdbd state=started'
```

Validate:

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m shell \
  -a '
    systemctl is-active slurmdbd
    journalctl -u slurmdbd -n 30 --no-pager
  '
```

An active daemon can still emit a separate pidfile-permission warning or
database-tuning recommendation. Treat those as follow-up issues unless they
prevent accounting queries.

### 4. Slurm controller

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m systemd \
  -a 'name=slurmctld state=started'
```

Validate:

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_controller \
  -b \
  -m shell \
  -a '
    systemctl is-active slurmctld
    scontrol ping
    sacctmgr -nP show cluster format=Cluster
  '
```

### 5. Compute daemons

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_compute \
  -b \
  -m systemd \
  -a 'name=slurmd state=started'
```

Inspect only fresh logs:

```bash
ansible \
  -i inventories/private/hosts.yml \
  slurm_compute \
  -b \
  -m shell \
  -a '
    echo === $(hostname) ===
    systemctl is-active slurmd
    journalctl -u slurmd --since "-2 minutes" --no-pager
  '
```

The recovery is not complete if new logs still contain:

```text
Unexpected uid (...) != Slurm uid (...)
Security violation: REQUEST_PING
_verify_signature: failed decode
```

Warnings about an optional HTTP parser plugin are a separate packaging issue
and are not the cause of the MUNGE UID failure.

## Clear stale scheduler state

Failed authenticated RPCs can leave old jobs in `COMPLETING` or nodes carrying
stale drain state.

Inspect first:

```bash
squeue -a
sinfo -N -l
```

Cancel stale jobs if needed:

```bash
scancel -u "$USER"
```

For nodes whose only remaining state is stale incident state, an administrator
can deliberately cycle them through DOWN/RESUME after verifying `slurmd` is
healthy:

```bash
sudo scontrol update NodeName=slurm-cpu-[01-04] \
  State=DOWN Reason="clear stale pre-UID-migration state"
sudo scontrol update NodeName=slurm-cpu-[01-04] State=RESUME
```

Do not use RESUME to hide a genuine hardware, memory, authentication or daemon
failure.

## Acceptance

Start with scheduler state:

```bash
scontrol ping
sacctmgr -nP show cluster format=Cluster
sinfo -N -l
squeue -a
```

All M1 compute nodes should reach a clean `IDLE` state with no unexpected
drain reason.

Then test actual task launch:

```bash
srun --partition=cpu-small \
  --nodes=1 \
  --ntasks=1 \
  hostname
```

and:

```bash
srun --partition=cpu-large \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=32 \
  --mem=128G \
  bash -lc 'hostname; nproc; free -h'
```

A scheduler that reports `IDLE` nodes but cannot execute these commands has
not passed acceptance.

If allocation succeeds but the task still hangs, inspect the fresh
`slurmd`/step logs and verify the submitting POSIX identity is resolvable
with the expected numeric UID/GID on the execution node. Do **not** provision
future research identities manually as a workaround; Quantum Platform owns the
future research-user lifecycle.

## Lessons from the incident

1. Matching Linux usernames do not imply matching numeric identities.
2. Auto-allocated system IDs are local state unless explicitly managed.
3. Slurm/MUNGE service IDs are part of the distributed authentication contract.
4. MUNGE key equality and clock synchronization should be checked before
   changing identities.
5. Stop a daemon before changing the UID of the account running it.
6. A successful `groupmod` followed by a failed `usermod` can leave a
   service half-migrated.
7. Changing UID/GID does not repair every existing inode automatically.
8. Start authentication first, then accounting, then control, then compute.
9. `sinfo` being healthy is not equivalent to successful `srun`.
10. Recovery procedures belong in an operational tutorial; bootstrap should
    prevent the condition from occurring in the first place.
