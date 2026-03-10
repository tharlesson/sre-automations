SHELL := /bin/bash

STACK ?= dev

.PHONY: help fmt validate test init plan apply destroy

help:
	@echo "Targets:"
	@echo "  make fmt               - terraform fmt recursively"
	@echo "  make validate STACK=dev|stage|prod"
	@echo "  make test              - run python tests"
	@echo "  make init STACK=dev|stage|prod"
	@echo "  make plan STACK=dev|stage|prod"
	@echo "  make apply STACK=dev|stage|prod"
	@echo "  make destroy STACK=dev|stage|prod"

fmt:
	terraform fmt -recursive

validate:
	cd stacks/$(STACK) && terraform init -backend=false && terraform validate

test:
	pytest -q tests

init:
	cd stacks/$(STACK) && terraform init -reconfigure -backend-config=../../env/$(STACK)/backend.hcl

plan:
	cd stacks/$(STACK) && terraform plan -var-file=../../env/$(STACK)/terraform.tfvars

apply:
	cd stacks/$(STACK) && terraform apply -var-file=../../env/$(STACK)/terraform.tfvars

destroy:
	cd stacks/$(STACK) && terraform destroy -var-file=../../env/$(STACK)/terraform.tfvars