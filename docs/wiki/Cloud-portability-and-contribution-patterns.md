# Porting the reference site and contributing infrastructure

## Separate architecture from site configuration

The reference uses OpenStack with Neutron, Cinder, Rocky Linux, Kubeadm, Cilium, Argo CD, Slurm and private edge services. A new site should choose its own CIDRs, DNS, image versions, cloud credentials, identity authorities and backup plans. Avoid copying hardcoded production hostnames or assuming a second cloud shares a tenant, trust root or router.

The `terraform/environments/template/` directory is the public onboarding reference. Protected `terraform/environments/private` state and Ansible inventory are not reusable project assets. An adapted provider may replace OpenStack and Cinder while retaining higher-level GitOps/product contracts.

## Reproduce in acceptance-gated layers

Plan cloud changes, establish remote recovery, configure hosts, validate private networking, build Kubernetes/Cilium/storage, then reconcile GitOps apps, HPC accounts, research homes, Slurm and user-facing products. Record both successful paths and failures; do not hide manual repairs that are not encoded in IaC.

## Review discipline

One PR should name its ownership layer, exact changed files, drift/rollback risk, environment and secret impact, tests and planned maintenance window. Do not merge and auto-apply infrastructure from an AI suggestion without an authorised review. Capture live evidence separately after deployment and keep tutorial historical failures distinct from current implementation.

See [Terraform template](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/terraform/environments/template/README.md), [install guide](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/INSTALLATION.md), [developer guide](Developer-guide.md) and [release notes](https://github.com/nyameko/infra-hpc-qc-k8s/tree/main/docs/releases).