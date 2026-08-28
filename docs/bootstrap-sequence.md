# Bootstrap sequence — first implementation

### 1. Verify local tooling

```bash
terraform version
ansible --version
openstack --version
kubectl version --client
helm version
```

### 2. Configure OpenStack

Use `clouds.yaml` or environment variables for authentication. Never put credentials in `terraform.tfvars` committed to Git.

### 3. Select environment values

```bash
cp terraform/environments/personal/example.tfvars terraform/environments/personal/terraform.tfvars
$EDITOR terraform/environments/personal/terraform.tfvars
```

### 4. Provision OpenStack

```bash
make init
make validate
make plan
make apply
```

Expected result: 13 VMs plus the Kubernetes API Octavia load balancer.

### 5. Validate SSH

```bash
make ansible-ping
```

### 6. Base OS

```bash
make bootstrap
```

### 7. Edge, Hermes and Slurm host preparation

```bash
make edge
make hermes
make slurm
```

### 8. Kubernetes prerequisites

```bash
make k8s-prereqs
```

### 9. Kubernetes bootstrap

```bash
make k8s-init
```

Do not deploy Argo or applications until all six Kubernetes nodes are healthy.
