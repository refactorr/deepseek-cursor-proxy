#!/usr/bin/env bash
# Run Terraform like REDEV: Docker hashicorp/terraform:1.14 + repo + ~/.aws (read-only).
# See README-FORK.md "Terraform" and real-estate-development-project-management AGENTS.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_HOST="${TERRAFORM_CHDIR:-${DEPLOY_TERRAFORM_DIR:-$REPO_ROOT/terraform}}"
TF_HOST="$(cd "$TF_HOST" && pwd)"
case "$TF_HOST" in
"$REPO_ROOT"/*) ;;
*)
  echo "error: Terraform directory must be inside repo root: $REPO_ROOT (got $TF_HOST)" >&2
  exit 1
  ;;
esac

REL="${TF_HOST#"$REPO_ROOT"/}"
TF_DOCKER="/workspace/${REL}"
IMAGE="${TERRAFORM_DOCKER_IMAGE:-hashicorp/terraform:1.14}"

args=(--rm -v "$REPO_ROOT:/workspace" -v "$HOME/.aws:/root/.aws:ro" -w "$TF_DOCKER")
if [[ "$(uname -s)" == Linux ]]; then
  args+=(-u "$(id -u):$(id -g)")
fi

exec docker run "${args[@]}" "$IMAGE" "$@"
