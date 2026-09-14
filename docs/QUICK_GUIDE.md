# Quick Guide

Command-first reference for the current platform.

## 1. OpenStack / Terraform

```bash
cd terraform/environments/private
terraform init
a
terraform validate
terraform plan
terraform apply
```

Terraform owns OpenStack resources: networks, routers, ports, security groups, VMs and cloud-side load-balancing resources.

## 2. Ansible

```bash
cd ansible
ansible-inventory -i inventories/private/hosts.yml --graph
ansible all -i inventories/private/hosts.yml -m ping
ansible-playbook -i inventories/private/hosts.yml playbooks/bootstrap.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/edge.yml
ansible-playbook -i inventories/private/hosts.yml playbooks/api-lb.yml
```

Ansible owns host configuration and infrastructure services.

## 3. Kubernetes

```bash
ansible-playbook \
  -i inventories/private/hosts.yml \
  playbooks/kubernetes.yml

kubectl get nodes -o wide
kubectl get pods -A
```

## 4. Cilium

```bash
cilium status --wait
cilium connectivity test --debug
```

Advanced Hubble, kube-proxy replacement, ClusterMesh and deeper policy work remain deliberate follow-on exercises.

## 5. Argo CD

Check applications from Kubernetes when the Argo CLI is unavailable:

```bash
kubectl -n argocd get applications
```

Typical application pattern:

```text
argocd/applications/<app>.yml
        ↓
Argo CD
        ↓
Helm / repository resources
        ↓
Kubernetes
```

## 6. Prometheus / Grafana

```bash
kubectl -n monitoring get pods
kubectl -n argocd get applications
kubectl -n monitoring get configmaps -l grafana_dashboard=1
```

Prometheus queries can be tested directly:

```bash
kubectl -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=up'
```

The Grafana dashboard sidecar watches ConfigMaps labelled:

```text
grafana_dashboard=1
```

Do not manually import Git-managed dashboards into Grafana.

## 7. Temporary GUI access during bootstrap

Before application ingress is complete, temporary access may use:

```text
kubectl port-forward
SSH local forwarding
```

These are transitional tools only. The target architecture is:

```text
WireGuard / DNS
   ↓
HAProxy
   ↓
Traefik
   ↓
Kubernetes Service
```

The end-state goal is to stop requiring normal-use port-forwards and SSH tunnels.

## 8. Slurm

```bash
sinfo
squeue
scontrol show nodes
```

Slurm remains authoritative for HPC scheduling. Kubernetes does not replace it.

## 9. Edge health

```bash
sudo nft list ruleset
sudo wg show
systemctl is-active wazuh-manager
systemctl is-active haproxy
sudo ss -lntup
```

## 10. Troubleshooting rule

Classify the failing layer before changing it:

```text
cloud → VM/OS → firewall/SELinux → service → runtime → Kubernetes → Cilium → application → observability
```
