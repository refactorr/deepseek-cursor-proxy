# Run from repo root (or: make -f path/to/Makefile -C path/to/repo <target>).
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TF := $(ROOT)/scripts/terraform.sh
SH := $(ROOT)/scripts

.DEFAULT_GOAL := help

.PHONY: help \
	tf-init tf-fmt tf-fmt-check tf-validate tf-plan tf-apply tf-destroy tf-output \
	deploy-https stream-logs run start stop

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'

# --- Terraform (Docker wrapper; see README-FORK.md) ---

tf-init: ## ./scripts/terraform.sh init  (pass extra: make tf-init ARGS='-upgrade')
	$(TF) init $(ARGS)

tf-fmt: ## ./scripts/terraform.sh fmt -recursive
	$(TF) fmt -recursive

tf-fmt-check: ## ./scripts/terraform.sh fmt -check -recursive
	$(TF) fmt -check -recursive

tf-validate: ## validate; optional TERRAFORM_VAR_FILE=
	TERRAFORM_VAR_FILE="$(TERRAFORM_VAR_FILE)" $(TF) validate

tf-plan: ## plan; optional TERRAFORM_VAR_FILE=; ARGS for extra flags (e.g. -var key_name=my-key)
	TERRAFORM_VAR_FILE="$(TERRAFORM_VAR_FILE)" $(TF) plan $(ARGS)

tf-apply: ## apply; optional TERRAFORM_VAR_FILE=; ARGS e.g. -auto-approve -var key_name=my-key
	TERRAFORM_VAR_FILE="$(TERRAFORM_VAR_FILE)" $(TF) apply $(ARGS)

tf-destroy: ## destroy; optional TERRAFORM_VAR_FILE=; ARGS e.g. -auto-approve
	TERRAFORM_VAR_FILE="$(TERRAFORM_VAR_FILE)" $(TF) destroy $(ARGS)

tf-output: ## ./scripts/terraform.sh output  (e.g. ARGS='-raw cursor_base_url_https')
	$(TF) output $(ARGS)

# --- App / ops scripts ---

deploy-https: ## nginx + TLS on sslip.io; optional CERTBOT_EMAIL= (else terraform output certbot_junk_email)
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

run: ## EC2 dev: start if stopped, deploy HTTPS, stream journal; stop instance on exit
	CERTBOT_EMAIL="$(CERTBOT_EMAIL)" \
	SKIP_STOP_ON_EXIT="$(SKIP_STOP_ON_EXIT)" \
	DEPLOY_EC2_SSH_KEY="$(DEPLOY_EC2_SSH_KEY)" \
	DEPLOY_TERRAFORM_DIR="$(DEPLOY_TERRAFORM_DIR)" \
	TERRAFORM_CHDIR="$(TERRAFORM_CHDIR)" \
	$(SH)/run.sh

start: run ## Alias for `make run`

stop: ## Stop Terraform EC2 instance if running (no-op if already stopped/stopping)
	DEPLOY_TERRAFORM_DIR="$(DEPLOY_TERRAFORM_DIR)" \
	TERRAFORM_CHDIR="$(TERRAFORM_CHDIR)" \
	$(SH)/stop.sh
