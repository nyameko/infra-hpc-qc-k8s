# Hermes federation

## Personal/federation Hermes

`hermes-orchestrator-01` is outside Kubernetes so it survives a Kubernetes control-plane failure. It can read logs, metrics and infrastructure state and generate proposed changes.

Default state is read-only. Changes must pass through a human-approved Git/CI path or another explicitly approved automation mechanism.

## Research Hermes

`research-hermes` is deployed in the Kubernetes research environment after the base cluster, ingress, telemetry and security layers are healthy. It is scoped to research operations.

## No direct commit authority

The orchestration VM must use read-only Git credentials. It may create a local patch or request for review, but it cannot push protected branches. Branch protection and CI are additional enforcement layers outside the VM.
