SHELL := /bin/bash
ROOT := $(shell pwd)
TF := terraform -chdir=$(ROOT)/terraform/environments/personal

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

inventory:
	$(ROOT)/scripts/render_inventory.py

ansible-ping:
	ansible all -m ping

ansible-bootstrap:
	ansible-playbook ansible/playbooks/bootstrap.yml

ansible-k8s:
	ansible-playbook ansible/playbooks/kubernetes.yml
