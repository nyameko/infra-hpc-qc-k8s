# Initial architecture — locked for deployment

## VM roles

- `edge`: network/security edge. WireGuard, Pi-hole, nftables, Suricata IDS, SSH bastion, Wazuh agent.
- `hermes-orchestrator-01`: personal/federation Hermes outside Kubernetes; isolated and read/report-only by default.
- `slurm-controller-01`: dedicated Slurm controller (`slurmctld`), accounting (`slurmdbd`) and initial MariaDB. No user login.
- `login1`, `login2`: user SSH + Slurm client nodes. Users submit jobs here; these are not the compute pool.
- `slurm-cpu-01`, `slurm-cpu-02`: pure Slurm compute, exactly 64 CPUs each.
- `k8s-cp-01..03`: Kubernetes control plane.
- `k8s-worker-01..03`: Kubernetes workers.

## Slurm decision

`slurmctld` is **not** placed on `edge`. SchedMD describes `slurmctld` as the central management daemon and recommends single-purpose node roles for production environments. A backup controller can be added later. `slurmdbd` is initially co-located only to keep the first environment small.

## Hermes federation

The VM Hermes is the personal/control-level agent. Kubernetes hosts a separate research Hermes later. The two communicate through explicit, restricted interfaces. The VM Hermes has no Git push token and no unrestricted Kubernetes/OpenStack credentials.
