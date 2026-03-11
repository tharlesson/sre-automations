SHELL := /bin/bash

STACK ?= dev
VAR_FILE ?= ../../env/$(STACK)/terraform.tfvars
LOCAL_VAR_FILE ?= ../../env/$(STACK)/terraform.local.tfvars
REGION ?= us-east-1
PROJECT ?= sreauto
PROFILE ?=

.PHONY: help fmt validate test init plan apply destroy seed-baseline configure-webhooks run-sg-approval

help:
	@echo "Targets:"
	@echo "  make fmt               - terraform fmt recursively"
	@echo "  make validate STACK=dev|stage|prod"
	@echo "  make test              - run python tests"
	@echo "  make init STACK=dev|stage|prod"
	@echo "  make plan STACK=dev|stage|prod"
	@echo "  make apply STACK=dev|stage|prod"
	@echo "  make destroy STACK=dev|stage|prod"
	@echo "  make seed-baseline STACK=dev|stage|prod"
	@echo "  make configure-webhooks STACK=dev|stage|prod CHATOPS_WEBHOOK=... ITSM_WEBHOOK=..."
	@echo "  make run-sg-approval STACK=dev|stage|prod REGION=us-east-1 PROJECT=sreauto PROFILE=my-dev-profile"

fmt:
	terraform fmt -recursive

validate:
	cd stacks/$(STACK) && terraform init -backend=false && terraform validate

test:
	pytest -q tests

init:
	cd stacks/$(STACK) && terraform init -reconfigure -backend-config=../../env/$(STACK)/backend.hcl

plan:
	cd stacks/$(STACK) && VAR_ARGS="-var-file=$(VAR_FILE)"; \
		if [ -f $(LOCAL_VAR_FILE) ]; then VAR_ARGS="$$VAR_ARGS -var-file=$(LOCAL_VAR_FILE)"; fi; \
		terraform plan $$VAR_ARGS

apply:
	cd stacks/$(STACK) && VAR_ARGS="-var-file=$(VAR_FILE)"; \
		if [ -f $(LOCAL_VAR_FILE) ]; then VAR_ARGS="$$VAR_ARGS -var-file=$(LOCAL_VAR_FILE)"; fi; \
		terraform apply $$VAR_ARGS

destroy:
	cd stacks/$(STACK) && VAR_ARGS="-var-file=$(VAR_FILE)"; \
		if [ -f $(LOCAL_VAR_FILE) ]; then VAR_ARGS="$$VAR_ARGS -var-file=$(LOCAL_VAR_FILE)"; fi; \
		terraform destroy $$VAR_ARGS

seed-baseline:
	bash scripts/seed_drift_baseline.sh --environment $(STACK) --enable-publish-on-first-apply

configure-webhooks:
	bash scripts/configure_approval_webhooks.sh --environment $(STACK) --chatops-webhook-url "$(CHATOPS_WEBHOOK)" --itsm-webhook-url "$(ITSM_WEBHOOK)"

run-sg-approval:
	bash scripts/run_sg_remediation_approval.sh --environment $(STACK) --region "$(REGION)" --project "$(PROJECT)" --profile "$(PROFILE)"
