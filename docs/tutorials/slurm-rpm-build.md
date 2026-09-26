# Building vetted Slurm RPMs with Ansible

M1 does **not** make OpenHPC the Slurm distribution layer. We use the official
SchedMD source release, build Rocky Linux 9 RPMs once, collect them on the
Ansible control machine, then stage the same artifacts onto controller, login
and compute nodes.

This workflow is the reproducible replacement for manually SSHing into the
controller and running `dnf`, `curl`, `dnf builddep` and `rpmbuild`.

## Why RPMs

SchedMD recommends building RPM/DEB packages for production rather than
installing directly from a source tree. The package build also makes the exact
scheduler version portable across CPU, A100, H200 and container/client
environments.

M1 pins:

```text
Slurm       25.11.8
RPM release 1.el9
Platform    Rocky Linux 9 x86_64
```

The source archive is downloaded from SchedMD and verified against the
published SHA256 checksum before any build starts.

## What the builder role does

`roles/slurm_rpm_builder` performs the complete build workflow:

1. verifies the builder is Rocky Linux 9 x86_64;
2. creates an unprivileged `slurm-builder` build identity;
3. installs RPM tooling and enables CRB/EPEL;
4. installs explicit MUNGE/cgroup-v2 feature build dependencies;
5. downloads and checksum-verifies the pinned SchedMD tarball;
6. extracts the **official Slurm spec file**;
7. runs `dnf builddep` against that spec so the spec remains authoritative for
   the large BuildRequires set;
8. runs `rpmbuild -ta` as the unprivileged builder user;
9. verifies that the core, slurmctld, slurmd and slurmdbd RPMs exist;
10. produces an artifact SHA256 manifest;
11. fetches all RPMs to the Ansible control machine under
    `ansible/artifacts/slurm/<version>/`.

The local artifact directory is intentionally gitignored.

## Build

From `ansible/`:

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/slurm-build-rpms.yml
```

Node Exporter is installed **before** the build role, so the compile should be
visible in the Slurm host infrastructure Grafana dashboard once Prometheus is
scraping the controller.

Expected local artifacts include:

```text
slurm-25.11.8-1.el9.x86_64.rpm
slurm-slurmctld-25.11.8-1.el9.x86_64.rpm
slurm-slurmd-25.11.8-1.el9.x86_64.rpm
slurm-slurmdbd-25.11.8-1.el9.x86_64.rpm
SHA256SUMS
```

The build also produces optional packages such as `slurm-libpmi`,
`slurm-pam_slurm`, `slurm-devel`, `slurm-sackd` and compatibility
packages. M1 should install only packages required by each host role.

## Deployment contract

`roles/slurm_rpm_stage` copies the collected artifacts from the Ansible
control machine to:

```text
/var/cache/quantum-platform/slurm-rpms/<version>/
```

on each Slurm host. The Slurm installation roles then install their required
RPM subset from that artifact set.

Longer term, issue #41 replaces the workstation artifact hop with CI-built,
signed RPMs in an internal DNF/Yum repository and promotion channels.

## Rebuild / upgrade

A version upgrade is a deliberate variable change, for example:

```yaml
slurm_package_version: "26.05.x"
slurm_source_checksum: "sha256:<SchedMD-published-checksum>"
```

Build a new artifact set; do not overwrite the old version directory.
Controller/database upgrade ordering and rollback must be reviewed separately
before promotion.
