# Hybrid HPC / Cloud / AI-ML / Quantum Infrastructure — Documentation & Course Pack

This tutorial pack turns `infra-hpc-qc-k8s` into a practical infrastructure classroom. It follows the same principle as the implementation: build one layer, validate it, understand the failure modes, then proceed.

## Teaching model

Each module uses:

1. **Lecture** — architecture and concepts.
2. **Workshop** — guided implementation.
3. **Tutorial checklist** — self-paced acceptance tasks.
4. **Deliverable** — an artifact, patch, working service or measured result.

The course is designed for students who know Linux and basic networking but do not need prior Kubernetes, Slurm or quantum-computing expertise.

## Reading order

1. Architecture and separation of concerns
2. Networking, WireGuard and edge security
3. Terraform and Ansible
4. Kubernetes, Cilium, storage, Argo CD and observability
5. Wazuh and Siccata security plane
6. Slurm HPC scheduler
7. Private ingress, Pi-hole, Cloudflare and Traefik
8. PostgreSQL and identity/application state
9. JupyterHub
10. Hermes / Heretic
11. Quantum-computing sandbox
12. Astro and platform capstone

## Current validated lessons

The tutorials should explicitly cover these real platform lessons:

- OpenStack security-group scope can make a healthy CNI appear broken.
- HAProxy syntax validation is separate from SELinux authorization.
- API load balancing and application ingress are different HAProxy responsibilities.
- Cilium overlay health does not automatically prove NodePort or every other traffic path.
- Argo `Synced` and `Healthy` mean different things.
- Helm values can be valid YAML while still being at the wrong chart hierarchy.
- Prometheus discovery job names must be read from the actual scrape configuration.
- Grafana queries must follow the actual metric/label schema.
- Git-managed Grafana dashboards should be reconciled through Argo and the dashboard sidecar, not manually imported.
- Temporary GUI tunnels are useful during bootstrap but should not become the final access architecture.
- Wazuh and Prometheus/Grafana have complementary roles rather than competing dashboards.

## Observability tutorial milestone

Prometheus/Grafana is now its own platform module. Students should learn to:

```text
metric endpoint
   ↓
Prometheus scrape configuration
   ↓
Prometheus labels / discovery jobs
   ↓
PromQL
   ↓
Grafana dashboard
   ↓
GitOps reconciliation
```

The lesson is not merely “install Grafana”. It is “prove that what Grafana displays corresponds to the live platform.”

## Security module boundary

Wazuh:

```text
security events / host security / investigation
```

Siccata:

```text
IDS/IPS / network security events
```

Prometheus/Grafana:

```text
operational metrics / platform health / security telemetry
```

## Hermes module boundary

Hermes is a controlled orchestration system. The course must teach:

```text
read
propose
approve
apply
```

rather than “give the agent root”.

Telegram and Discord are planned as external interfaces through controlled liaison services. Prompt injection through attacker-controlled logs/events is a first-class security lesson.

## Capstone

The capstone is to close a real platform gap with a reviewed Git change while preserving:

- separation of concerns
- least privilege
- reproducibility
- observability
- no secrets in Git
- explicit acceptance tests
