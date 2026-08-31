# infra-hpc-qc-k8s Documentation Pack

This documentation pack explains the operating model for the infrastructure repository.

```text
Terraform
  |
  +--> OpenStack networks, routers, security groups, ports, VMs
  |
Ansible
  |
  +--> operating system, SSH, time, edge services, Slurm, Kubernetes prerequisites
  |
kubeadm
  |
  +--> Kubernetes cluster
  |
Argo CD
  |
  +--> Kubernetes applications
```

The platform is designed to be reproducible and suitable for teaching cloud, Linux, automation, Kubernetes, HPC, AI/ML and quantum-computing infrastructure.
