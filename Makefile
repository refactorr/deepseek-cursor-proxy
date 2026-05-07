# Run from repo root (or: make -f path/to/Makefile -C path/to/repo <target>).
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TF := $(ROOT)/scripts/terraform.sh
SH := $(ROOT)/scripts

.DEFAULT_GOAL := help

.PHONY: help \
	tf-init tf-fmt tf-fmt-check tf-validate tf-plan tf-apply tf-destroy tf-output \
	deploy-https stream-logs

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'

# --- Terraform (Docker wrapper; see README-FORK.md) ---

tf-init: ## ./scripts/terraform.sh init  (pass extra: make tf-init ARGS='-upgrade')
	$(TF) init $(ARGS)

tf-fmt: ## ./scripts/terraform.sh fmt -recursive
	$(TF) fmt -recursive

tf-fmt-check: ## ./scripts/terraform.sh fmt -check -recursive
	$(TF) fmt -check -recursive

tf-validate: ## ./scripts/terraform.sh validate
	$(TF) validate

tf-plan: ## ./scripts/terraform.sh plan  (pass ARGS='-var-file=...')
	$(TF) plan $(ARGS)

tf-apply: ## ./scripts/terraform.sh apply
	$(TF) apply $(ARGS)

tf-destroy: ## ./scripts/terraform.sh destroy
	$(TF) destroy $(ARGS)

tf-output: ## ./scripts/terraform.sh output  (pass ARGS='-raw public_ip')
	$(TF) output $(ARGS)

# --- App / ops scripts ---

deploy-https: ## ./scripts/deploy-ec2-https.sh  (requires CERTBOT_EMAIL=, optional DEPLOY_*)
	@test -n "$(CERTBOT_EMAIL)" || (printf '%s\n' 'Set CERTBOT_EMAIL= for Let'\''s Encrypt' >&2; exit 1)
	CERTBOT_EMAIL="$(CERTBOT_EMAIL)" \
	DEPLOY_EC2_HOST="$(DEPLOY_EC2_HOST)" \
	DEPLOY_EC2_SSH_KEY="$(DEPLOY_EC2_SSH_KEY)" \
	DEPLOY_TERRAFORM_DIR="$(DEPLOY_TERRAFORM_DIR)" \
	TERRAFORM_CHDIR="$(TERRAFORM_CHDIR)" \
	$(SH)/deploy-ec2-https.sh

stream-logs: ## ./scripts/stream-proxy-logs.sh  (optional: ARGS='1.2.3.4' or DEPLOY_EC2_HOST=)
	DEPLOY_EC2_HOST="$(DEPLOY_EC2_HOST)" \
	DEPLOY_EC2_SSH_KEY="$(DEPLOY_EC2_SSH_KEY)" \
	DEPLOY_TERRAFORM_DIR="$(DEPLOY_TERRAFORM_DIR)" \
	TERRAFORM_CHDIR="$(TERRAFORM_CHDIR)" \
	$(SH)/stream-proxy-logs.sh $(ARGS)
