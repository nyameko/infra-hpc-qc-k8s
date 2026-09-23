#!/usr/bin/env bash
# Read-only release evidence collector. Run from an authenticated operator terminal.
# Do NOT commit captured output without reviewing it for private topology.
set -euo pipefail

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '# Platform snapshot (UTC %s)\n\n' "$stamp"
printf '## Cluster\n'
kubectl version --client
kubectl version -o yaml 2>&1 | sed -n '1,42p'
kubectl get nodes -o wide
printf '\n## GitOps applications\n'
kubectl -n argocd get applications   -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
printf '\n## Portal workload images and resolved image IDs\n'
kubectl -n quantum-platform get pods   -o custom-columns='POD:.metadata.name,IMAGE:.spec.containers[*].image,IMAGE_ID:.status.containerStatuses[*].imageID'
printf '\n## Portal migration status\n'
kubectl -n quantum-platform exec deployment/quantum-platform-user-api --   python manage.py showmigrations portal
printf '\n## API readiness\n'
kubectl -n quantum-platform rollout status deployment/quantum-platform-user-api --timeout=15s
printf '\n## Deployed observability and security workload versions (pod image refs)\n'
kubectl get pods -A -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,IMAGE:.spec.containers[*].image' |
  grep -Ei '(^NAMESPACE|prometheus|grafana|wazuh|suricata|traefik|cilium|argocd)' || true
printf '\n## Local project dev HEADs (if checked out)\n'
for project in infra-hpc-qc-k8s quantum-platform agent-control-plane quantum-workflows; do
  if [[ -d "$HOME/Projects/$project/.git" ]]; then
    git -C "$HOME/Projects/$project" fetch --quiet origin dev
    printf '%s %s\n' "$project" "$(git -C "$HOME/Projects/$project" rev-parse origin/dev)"
  else
    printf '%s not-present\n' "$project"
  fi
done
printf '\n## Manual evidence still required\n'
printf 'Slurm: sinfo, squeue, sacctmgr read-only, scontrol version; Wazuh/Suricata: last controlled event IDs; Cinder/backup: restore exercise; Argo: migration hook history.\n'
