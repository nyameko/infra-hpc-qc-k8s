# Security and recovery

## Rules

Keep private keys, SSH/WireGuard credentials, cloud tokens, PostgreSQL passwords, signing keys, vault backups, provider API keys, raw Secrets and live private topology **out of public GitHub, Issues, PRs, wikis, agent prompts and logs**. Git history can retain accidentally committed values: revoke and rotate exposures, not merely delete a current file.

Canonical recoverable credentials belong in a trusted encrypted vault with separate offline recovery. Protected local inventory and Kubernetes Secret objects are *working/runtime copies*, not a backup. Committed SealedSecret ciphertext requires protected recovery of controller keys; losing those may make a clean restore impossible.

## Separation of duties

OpenStack security groups filter cloud ingress; edge nftables filters host ingress/forwarding; Cilium policies govern Kubernetes traffic; SSH/WireGuard establish independent identities; Quantum Platform authorizes resources; Slurm enforces scheduler allocations; ACP validates signed assertions and scopes. Do not use an LLM response or a POSIX UID as an administrator authorization token.

## Recommended incident sequence

Contain affected key/account, record minimal non-secret forensic data, rotate at the credential source, deploy fresh sealed material through a reviewed GitOps change, test restored access with least privilege, and verify old credentials are rejected. For ransomware or data loss, recover **both** persistent PostgreSQL/storage data and their corresponding credential/encryption escrow from tested backups.

## Safety for agents

An agent may retrieve public documentation and propose diagnostics. Writing Secrets, editing deployment state, database migrations, resource grants, GPU/QPU charges and destructive cleanup require explicit policy-checked human approval. Evidence from a source file must not be confused with observed runtime state.

See [credential stores and recovery](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/credential-stores-and-recovery.md), [private state disaster recovery](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/private-state-disaster-recovery.md) and [security drills](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/wazuh-suricata-operational-drills.md).