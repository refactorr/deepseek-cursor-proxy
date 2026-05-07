#!/usr/bin/env bash
# Run Terraform like REDEV: Docker hashicorp/terraform:1.14 + repo + ~/.aws (read-only).
#
# Variable inputs (same as REDEV terraform-local-aws.mdc):
# - Files in the working dir: terraform.tfvars, *.auto.tfvars (Terraform loads these by default).
# - Explicit CLI: -var='key=value' and/or -var-file=... (paths under repo -> use /workspace/... inside Docker).
# - Optional env TERRAFORM_VAR_FILE or TF_VAR_FILE: host path (repo-relative or absolute under repo)
#   is mapped to -var-file=/workspace/... for plan/apply/destroy/import/refresh/console/validate only.
#
# plan/apply/destroy also get -input=false when not already present (REDEV examples use -input=false).
#
# Example (REDEV-style inline -var):
#   ./scripts/terraform.sh apply -input=false -auto-approve -var='key_name=my-ec2-key'
#
# Example (var file):
#   TERRAFORM_VAR_FILE=terraform.tfvars ./scripts/terraform.sh plan
#
# See README-FORK.md and real-estate-development-project-management/.cursor/rules/terraform-local-aws.mdc
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

docker_var_file_path() {
  local f="$1" abs dir base
  if [[ "$f" == /* ]]; then
    abs="$f"
  else
    if [[ -f "$TF_HOST/$f" ]]; then
      dir="$(cd "$TF_HOST" && cd "$(dirname "$f")" && pwd)"
      base="$(basename "$f")"
      abs="$dir/$base"
    elif [[ -f "$REPO_ROOT/$f" ]]; then
      dir="$(cd "$REPO_ROOT" && cd "$(dirname "$f")" && pwd)"
      base="$(basename "$f")"
      abs="$dir/$base"
    else
      echo "error: TERRAFORM_VAR_FILE / TF_VAR_FILE not found: $f (under ${TF_HOST} or ${REPO_ROOT})" >&2
      return 1
    fi
  fi
  case "$abs" in
  "$REPO_ROOT"/*) printf '/workspace%s' "${abs#$REPO_ROOT}" ;;
  *)
    echo "error: var file must be under repo root: $abs" >&2
    return 1
    ;;
  esac
}

argv_contains() {
  local needle="$1"
  shift
  local a
  for a in "$@"; do
    if [[ "$a" == "$needle" || "$a" == "${needle}="* ]]; then
      return 0
    fi
  done
  return 1
}

args=(--rm -v "$REPO_ROOT:/workspace" -v "$HOME/.aws:/root/.aws:ro" -w "$TF_DOCKER")
if [[ "$(uname -s)" == Linux ]]; then
  args+=(-u "$(id -u):$(id -g)")
fi

if [[ $# -eq 0 ]]; then
  exec docker run "${args[@]}" "$IMAGE"
fi

subcmd="$1"
shift
rest=("$@")

inject=()

case "$subcmd" in
plan | apply | destroy)
  if ! argv_contains -input=false "${rest[@]}"; then
    inject+=(-input=false)
  fi
  ;;
esac

vf="${TERRAFORM_VAR_FILE:-${TF_VAR_FILE:-}}"
case "$subcmd" in
plan | apply | destroy | import | refresh | console | validate)
  if [[ -n "$vf" ]]; then
    df="$(docker_var_file_path "$vf")" || exit 1
    inject+=(-var-file="$df")
  fi
  ;;
esac

# Build argv so set -u never trips on an empty inject array (bash 4.x + nounset).
cmd_args=("$subcmd")
((${#inject[@]} > 0)) && cmd_args+=("${inject[@]}")
cmd_args+=("${rest[@]}")
exec docker run "${args[@]}" "$IMAGE" "${cmd_args[@]}"
