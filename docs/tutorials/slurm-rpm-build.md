# Building vetted Slurm RPMs with Ansible

M1 does not make OpenHPC the Slurm distribution layer. We use the official SchedMD source release, build Rocky Linux 9 RPMs once, collect them on the Ansible control machine, then stage the same artifacts onto controller, login and compute nodes.

This workflow replaces manually SSHing into the controller and running dnf, curl, dnf builddep and rpmbuild.

## Why RPMs

SchedMD recommends building RPM/DEB packages for production rather than installing directly from a source tree. The package build also makes the exact scheduler version portable across CPU, A100, H200 and container/client environments.

M1 pins:

    Slurm       25.11.8
    RPM release 1.el9
    Platform    Rocky Linux 9 x86_64

The source archive is downloaded from SchedMD and checksum-verified before any build starts.

## What the builder role does

`roles/slurm_rpm_builder` performs the complete build workflow:

1. verifies Rocky Linux 9 x86_64;
2. creates an unprivileged `slurm-builder` build identity;
3. installs RPM tooling and enables CRB/EPEL;
4. installs explicit MUNGE/cgroup-v2 feature build dependencies;
5. downloads and checksum-verifies the pinned SchedMD tarball;
6. extracts the official Slurm spec file;
7. runs `dnf builddep` against that spec so the spec remains authoritative for the large BuildRequires set;
8. runs `rpmbuild -ta` as the unprivileged builder user;
9. verifies the core, slurmctld, slurmd and slurmdbd RPMs exist;
10. generates a SHA256 manifest;
11. fetches all RPMs to `ansible/artifacts/slurm/<version>/` on the Ansible control machine.

The artifact directory is gitignored.

## Build

From `ansible/`:

    ansible-playbook \
      -i inventories/private/hosts.yml \
      playbooks/slurm-build-rpms.yml

Node Exporter is installed before the build role, so a future compile is visible in the Slurm host Grafana dashboard once Prometheus is scraping the controller.

Expected local artifacts include:

    slurm-25.11.8-1.el9.x86_64.rpm
    slurm-slurmctld-25.11.8-1.el9.x86_64.rpm
    slurm-slurmd-25.11.8-1.el9.x86_64.rpm
    slurm-slurmdbd-25.11.8-1.el9.x86_64.rpm
    SHA256SUMS

The build also produces optional packages such as slurm-libpmi, slurm-pam_slurm, slurm-devel and slurm-sackd. M1 installs only packages required by each host role.

## Deploy

`playbooks/slurm.yml` first runs `roles/slurm_rpm_stage`, which copies the same collected RPM set to:

    /var/cache/quantum-platform/slurm-rpms/<version>/

on every Slurm host. `slurm_common` then installs the required subset for the node role.

That makes the deployment path:

    official SchedMD source
            ↓
    one RPM build
            ↓
    one collected artifact set
            ↓
    controller / login / CPU compute

rather than rebuilding or selecting packages independently on every machine.

## Future CI

Issue #41 moves the builder into CI, adds signing/SBOM/provenance, publishes an internal DNF/Yum repository, and introduces dev/staging/production promotion channels. The M1 role is deliberately compatible with that future model: the build artifact is already versioned and separated from deployment.

## Upgrade rule

A Slurm upgrade is a deliberate version and checksum change. Build a new version directory; do not overwrite a previous promoted artifact set. Review slurmdbd/controller/compute upgrade ordering before deploying a new scheduler release.