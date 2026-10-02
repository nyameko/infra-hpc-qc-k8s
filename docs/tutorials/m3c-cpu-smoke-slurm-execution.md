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

The established split is the same as other Sealed Secrets workflows:

```text
blackmyth
  git + ssh-keygen + ssh-keyscan + kubeseal
  cwd: ~/Projects/infra-hpc-qc-k8s/ansible
  cert: inventories/private/infra-hpc-qc-k8s.cert
  plaintext: ../secrets/slurm/
  sealed output: ../argocd/resources/quantum-platform/

k8s-cp-01
  kubectl / Argo / runtime verification only
```

1. Generate a dedicated Ed25519 service key pair on blackmyth.
2. Put only its public key in protected Ansible inventory as
   `jupyterhub_gateway_public_key`.
3. Add private DNS for `slurm-login.internal` to the intended login node.
4. Run `ansible/playbooks/jupyterhub-slurm.yml` against the Slurm tiers so the
   forced-command gateway is installed.
5. Capture the login host Ed25519 key with `ssh-keyscan` using the semantic
   hostname `slurm-login.internal`.
6. Create a plaintext Secret outside Git named
   `../secrets/slurm/quantum-platform-slurm-gateway.yaml` containing
   `SLURM_GATEWAY_PRIVATE_KEY` and `SLURM_GATEWAY_KNOWN_HOSTS`.
7. Seal it locally on blackmyth with the checked-in public certificate and write
   only the resulting SealedSecret into
   `../argocd/resources/quantum-platform/quantum-platform-slurm-gateway-sealed.yaml`.

Do not commit the private key, plaintext Secret, host address, or private DNS
mapping.

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
