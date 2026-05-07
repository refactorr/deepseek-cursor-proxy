#!/usr/bin/env bash
set -euo pipefail

# Dev "run" loop: start the Terraform EC2 instance (if stopped), deploy-ec2-https.sh,
# stream deepseek-proxy journal over SSH, then stop the instance on exit (Ctrl+C).
# Invoke via `make run`, `make start`, or `./scripts/run.sh`.
#
# Prereqs: aws, ssh, rsync, docker (terraform.sh outputs), same as deploy-ec2-https.sh.
# Env: same as deploy / stream (TERRAFORM_CHDIR, DEPLOY_EC2_SSH_KEY, CERTBOT_EMAIL, etc.).
#
# By default the instance is stopped when you leave (Ctrl+C ends the SSH log stream).
# Set SKIP_STOP_ON_EXIT=1 to leave it running (e.g. you only wanted deploy + logs).

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${TERRAFORM_CHDIR:-${DEPLOY_TERRAFORM_DIR:-$REPO_ROOT/terraform}}"
TF_SH="$REPO_ROOT/scripts/terraform.sh"
KEY="${DEPLOY_EC2_SSH_KEY:-${DEEPSEEK_PROXY_SSH_KEY:-$HOME/deepseek-proxy-key.pem}}"

tf_raw() {
  TERRAFORM_CHDIR="$TF_DIR" "$TF_SH" output -raw "$1" 2>/dev/null || true
}

if ! command -v aws >/dev/null 2>&1; then
  echo "error: aws CLI required" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1 || [[ ! -d "$TF_DIR/.terraform" ]]; then
  echo "error: docker + ${TF_DIR}/.terraform required for terraform outputs (see README-FORK.md)" >&2
  exit 1
fi
if [[ ! -f "$KEY" ]]; then
  echo "error: ssh key not found: $KEY" >&2
  exit 1
fi

INSTANCE_ID="$(tf_raw instance_id)"
REGION="$(tf_raw aws_region)"
IP="$(tf_raw public_ip)"
SSH_USER="$(tf_raw ssh_user)"
JUNIT="$(tf_raw systemd_journal_unit)"

[[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "null" ]] || {
  echo "error: terraform output instance_id empty (apply in ${TF_DIR})" >&2
  exit 1
}
[[ -n "$REGION" && "$REGION" != "null" ]] || REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
[[ -n "$IP" && "$IP" != "null" ]] || {
  echo "error: terraform output public_ip empty" >&2
  exit 1
}
[[ -n "$SSH_USER" && "$SSH_USER" != "null" ]] || SSH_USER="ec2-user"
[[ -n "$JUNIT" && "$JUNIT" != "null" ]] || JUNIT="deepseek-proxy"

read_state() {
  aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || true
}

STATE="$(read_state)"
[[ -n "$STATE" && "$STATE" != "None" ]] || {
  echo "error: cannot read instance state for $INSTANCE_ID" >&2
  exit 1
}

if [[ "$STATE" == "running" ]]; then
  :
elif [[ "$STATE" == "stopped" ]]; then
  echo "run: starting instance $INSTANCE_ID..." >&2
  aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --output text >/dev/null
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
elif [[ "$STATE" == "stopping" ]]; then
  echo "run: waiting for instance to stop..." >&2
  aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$INSTANCE_ID"
  echo "run: starting instance $INSTANCE_ID..." >&2
  aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --output text >/dev/null
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
else
  echo "error: instance $INSTANCE_ID is in state '$STATE' (need running, stopped, or stopping)" >&2
  exit 1
fi

CLEANING=""
cleanup() {
  if [[ -n "$CLEANING" ]]; then
    return 0
  fi
  CLEANING=1
  if [[ "${SKIP_STOP_ON_EXIT:-}" == "1" ]]; then
    echo "run: SKIP_STOP_ON_EXIT=1 — leaving instance running" >&2
    return 0
  fi
  echo "run: stopping instance $INSTANCE_ID..." >&2
  aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --output text >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

wait_for_ssh() {
  local attempt max=40
  for ((attempt = 1; attempt <= max; attempt++)); do
    if ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
      -o BatchMode=yes "${SSH_USER}@${IP}" "echo ok" >/dev/null 2>&1; then
      return 0
    fi
    echo "run: waiting for SSH (${attempt}/${max})..." >&2
    sleep 3
  done
  echo "error: SSH not ready after $max attempts" >&2
  return 1
}

wait_for_ssh

echo "run: deploying..." >&2
TERRAFORM_CHDIR="$TF_DIR" "$REPO_ROOT/scripts/deploy-ec2-https.sh"

cursor_http="$(tf_raw cursor_base_url_http)"
cursor_https="$(tf_raw cursor_base_url_https)"
if [[ -z "$cursor_http" || "$cursor_http" == "null" ]]; then
  cursor_http="http://${IP}/v1"
fi
if [[ -z "$cursor_https" || "$cursor_https" == "null" ]]; then
  cursor_https="https://${IP//./-}.sslip.io/v1"
fi

echo "" >&2
echo "================================================================================" >&2
echo "  Cursor Base URL — use on this machine (via EC2 / nginx):" >&2
echo "" >&2
echo "      ${cursor_http}" >&2
echo "      ${cursor_https}" >&2
echo "" >&2
echo "  (Journal lines showing 127.0.0.1:8000 are the app bind on the instance only.)" >&2
echo "================================================================================" >&2
echo "" >&2

echo "run: streaming journalctl -fu $JUNIT (Ctrl+C stops stream and instance)..." >&2
set +e
ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${IP}" \
  sudo journalctl -fu "$JUNIT"
ssh_status=$?
set -e
exit "$ssh_status"
