# Quick Guide

## Terraform

```bash
cd terraform/environments/private
terraform init
terraform validate
terraform plan
terraform apply
```

Terraform owns OpenStack infrastructure.

## Ansible

```bash
cd ansible
ansible-inventory -i inventories/private/hosts.yml --graph
ansible all -m ping
ansible-playbook -i inventories/private/hosts.yml playbooks/bootstrap.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/edge.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/api-lb.yml
```

Ansible owns host configuration and infrastructure services.

## Kubernetes

```bash
ansible-playbook -i inventories/private/hosts.yml playbooks/kubernetes.yml
kubectl get nodes -o wide
```

## Operating model

```text
Terraform -> OpenStack infrastructure
Ansible  -> operating systems and infrastructure services
kubeadm  -> Kubernetes bootstrap
Argo CD  -> Kubernetes application deployment
```
