# Version policy

- OpenStack Terraform provider: 3.4.0 in the starter.
- Kubernetes: use the currently supported `1.36.x` patch selected immediately before deployment; do not hard-code an old patch merely because it was current when this repository started.
- Cilium: pin an exact reviewed 1.20.x version when the cluster phase begins.
- Argo CD: pin an exact reviewed 3.5.x patch when the GitOps phase begins.
- Slurm: pin the distribution/OpenHPC build after the target Rocky 9 repositories are confirmed.

Upgrades happen as reviewed Git changes, not automatic floating upgrades.
