# Version policy

As of 2026-08-28:

- Terraform OpenStack provider: 3.4.0, current on the Terraform Registry.
- Kubernetes 1.37.0 is the newest release, published 2026-08-26. For this initial platform build, prefer Kubernetes 1.36 because it is a mature currently supported branch; before deployment, select and pin the exact currently available 1.36.x patch from `pkgs.k8s.io` and record it here.
- Cilium 1.20.1 is the stable chart used in this blueprint.
- Argo CD 3.5.x is the current stable release line as of this blueprint; pin the exact patch selected for deployment rather than using a floating manifest URL.

Do not upgrade Kubernetes, Cilium or Argo CD automatically in production. Promote upgrades as reviewed Git changes.
