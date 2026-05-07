#!/usr/bin/env bash
set -euo pipefail

# Stream proxy journal over SSH. When host not overridden, uses Terraform outputs
# (public_ip, ssh_user, systemd_journal_unit). With DEPLOY_EC2_HOST=<ip>, still
# reads ssh_user + journal unit from Terraform if ${TF_DIR}/.terraform exists.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${TERRAFORM_CHDIR:-${DEPLOY_TERRAFORM_DIR:-$REPO_ROOT/terraform}}"
KEY="${DEPLOY_EC2_SSH_KEY:-${DEEPSEEK_PROXY_SSH_KEY:-$HOME/deepseek-proxy-key.pem}}"
HOST_OVERRIDE="${1:-${DEPLOY_EC2_HOST:-}}"

tf_raw() {
  TERRAFORM_CHDIR="$TF_DIR" "$REPO_ROOT/scripts/terraform.sh" output -raw "$1" 2>/dev/null || true
}

tf_initialized() {
  command -v docker >/dev/null 2>&1 && [[ -d "$TF_DIR/.terraform" ]]
}

SSH_USER=ec2-user
JUNIT=deepseek-proxy
if tf_initialized; then
  s="$(tf_raw ssh_user)"
  [[ -n "$s" ]] && SSH_USER="$s"
  u="$(tf_raw systemd_journal_unit)"
  [[ -n "$u" ]] && JUNIT="$u"
fi

if [[ -n "$HOST_OVERRIDE" ]]; then
  if [[ "$HOST_OVERRIDE" == *@* ]]; then
    SSH_TARGET="$HOST_OVERRIDE"
  else
    SSH_TARGET="${SSH_USER}@${HOST_OVERRIDE}"
  fi
else
  if ! tf_initialized; then
    echo "error: no host; run Docker Terraform init/apply (README-FORK.md) in ${TF_DIR}, or set DEPLOY_EC2_HOST / pass <ip>" >&2
    exit 1
  fi
  IP="$(tf_raw public_ip)"
  if [[ -z "$IP" || "$IP" == "null" ]]; then
    echo "error: terraform output public_ip empty (apply in ${TF_DIR} via ./scripts/terraform.sh; see README-FORK.md)" >&2
    exit 1
  fi
  SSH_TARGET="${SSH_USER}@${IP}"
fi

[[ -f "$KEY" ]] || { echo "error: missing key $KEY" >&2; exit 1; }

exec ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$SSH_TARGET" \
  sudo journalctl -fu "$JUNIT"
