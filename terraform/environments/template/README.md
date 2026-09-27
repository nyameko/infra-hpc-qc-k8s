# Environment example

This directory is the sanitized starting point for a private environment.

The public repository intentionally documents **logical roles and variable contracts**, not a live address map. Provide actual CIDRs, fixed addresses, API VIPs, DNS resolvers, OpenStack IDs and node counts through protected `.tfvars` and Ansible inventory.

Expected logical shape:

- `edge` → `<EDGE_ADDR>`
- `slurm-controller-N` → `<SLURM_CONTROLLER_ADDR_N>`
- `login-N` → `<SLURM_LOGIN_ADDR_N>`
- `slurm-cpu-N` → `<SLURM_COMPUTE_ADDR_N>`
- `storage-N` → `<STORAGE_ADDR_N>`
- `api-lb-N` → `<K8S_API_VIP>`
- `k8s-cp-01 ... k8s-cp-N` → `<K8S_CP_ADDR_N>`
- `k8s-worker-01 ... k8s-worker-N` → `<K8S_WORKER_ADDR_N>`

Do not commit the private environment `.tfvars`, inventory, SSH/WireGuard private keys, kubeconfigs, provider credentials or actual network map.
