# M3c — Quantum Platform to Slurm cpu-smoke

## Existing trust boundary reused

M3c uses the existing restricted SSH gateway on the Slurm login tier:

```text
Quantum Platform user-api
  -> dedicated SSH service key
  -> forced command as jupyterhub-gateway
  -> root-owned helper
  -> runuser -u <researcher>
  -> sbatch
```

The key cannot obtain an interactive shell. The forced command accepts only
`submit <user>`, `query <jobid>` and `cancel <jobid>`.

## Private configuration

1. Generate a dedicated service key pair.
2. Put only its public key in protected Ansible inventory as
   `jupyterhub_gateway_public_key`.
3. Seal the private key into `quantum-platform-secrets` as
   `SLURM_GATEWAY_PRIVATE_KEY`.
4. Record the login host key as `SLURM_GATEWAY_KNOWN_HOSTS`.
5. Add private DNS for `slurm-login.internal` to the intended login node.

Do not commit the private key, host address, or private DNS mapping.

## Research entitlement

A protected research-user record opts into execution explicitly:

```yaml
research_users:
  - name: <user>
    uid: <uid>
    gid: <gid>
    execution_enabled: true
```

The identity playbook then:

- adds the user to `jupyterhub-users` on login/compute tiers;
- creates `~/.quantum-platform/runs` on authoritative NFS storage;
- creates a bootstrap Slurm association under `quantum-platform`.

Programme-specific accounts and budgets replace the bootstrap Slurm account
later.

## Runner

The compute-node preparation role stages
`quantum-workflows-qiskit-cpu` as an immutable/read-only Apptainer SIF. For
production, override the public `:dev` default with an immutable
`sha-<commit>` image in protected vars.

## Acceptance

1. Researcher has an approved Quantum Platform programme membership.
2. Researcher POSIX identity is provisioned and `execution_enabled`.
3. Submit `cpu-smoke` from `/runs/`.
4. Platform receives a numeric Slurm job ID.
5. `squeue` reports queued/running state.
6. After the job leaves `squeue`, gateway query falls back to `sacct`.
7. ExecutionRecord reaches `completed`.
8. The UUID run directory under `~/.quantum-platform/runs/` contains a
   completed quantum-workflows manifest and summary.
9. Closing Jupyter does not affect the run.
