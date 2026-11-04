# Troubleshooting

Use the sequence **symptom → reproduction → observed state → owning subsystem → reversible fix → regression evidence**. Start with read-only checks and record timestamps; never post credentials, tokens, production environment variables, private IP maps or patient/research data.

## User cannot reach a private service

Check that VPN is connected, the intended route exists and the hostname resolves to the correct private service. On the appropriate authorized host, inspect `wg show`, `ip route`, `getent hosts <HOST>` and provider SG/edge firewall rules. A DNS answer is not proof that TCP routing or authorization works. See [networking tutorial](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/02-networking-and-security.md).

## Jupyter fails to launch

Distinguish account not approved, invalid signed launch, no POSIX UID/GID, Pod configuration error, NFS missing, permission mismatch, unavailable image and scheduler confusion. Inspect hub/workbench Kubernetes events and logs; confirm the assigned UID/GID and real NFS mount. **Do not create a second home directory with a new UID to hide mismatched identity.**

## Slurm job never starts

Use `squeue`, `scontrol show job <JOB_ID>`, `sinfo`, and `sacct` as permitted. Diagnose `Reason`, account/QOS, walltime, partition, association and resource request; do not submit repetitively to bypass access policy. Run the validated `cpu-smoke` offering first. Different site backends may impose specific job names and walltime profiles.

## Argo OutOfSync/Healthy

Treat these as separate signals. Compare the exact resource diff and desired Git commit. Check migration prerequisites and whether a safe rollout is pending. Do not assume the app is broken, and do not force-sync until the drift is understood. See [ACP live conformance gates](https://github.com/nyameko/agent-control-plane/blob/main/docs/conformance/m4c-m4g-live-release-gates.md).

## Scientific result differs

Check seed, backend, shot count, build/image digest, CUDA version, data, units and hardware calibration. Compare simulator reference to analytic limits before attributing mismatch to a QPU or agent. For support: provide command, redacted traceback, expected/actual values, minimal public inputs, timestamps, and job/run IDs.