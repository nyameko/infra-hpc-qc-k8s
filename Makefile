SHELL := /bin/bash
TF := terraform -chdir=terraform/environments/personal
INV := ansible/inventories/personal/hosts.yml

fmt:
	terraform fmt -recursive terraform

init:
	$(TF) init

validate:
	$(TF) validate

plan:
	$(TF) plan

apply:
	$(TF) apply

ansible-ping:
	ansible all -i $(INV) -m ping

bootstrap:
	ansible-playbook -i $(INV) ansible/playbooks/bootstrap.yml

edge:
	ansible-playbook -i $(INV) ansible/playbooks/edge.yml

slurm:
	ansible-playbook -i $(INV) ansible/playbooks/slurm.yml

hermes:
	ansible-playbook -i $(INV) ansible/playbooks/hermes.yml

k8s-prereqs:
	ansible-playbook -i $(INV) ansible/playbooks/kubernetes-prereqs.yml

k8s-init:
	ansible-playbook -i $(INV) ansible/playbooks/kubernetes.yml
