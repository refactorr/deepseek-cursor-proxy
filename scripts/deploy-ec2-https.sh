#!/usr/bin/env bash
set -euo pipefail

# Push this repo to EC2, apply TCP sysctl, nginx + Let's Encrypt (sslip.io),
# systemd unit (proxy on 127.0.0.1:8000 behind TLS). Heartbeat stays in app
# (stream_keepalive_interval_seconds default 15).
#
# Prereqs: docker (for Terraform output discovery), aws, ssh, rsync; CERTBOT_EMAIL; SSH key.
#
#   export CERTBOT_EMAIL='you@example.com'
#   ./scripts/deploy-ec2-https.sh
#
# Host resolution (first match):
#   1) DEPLOY_EC2_HOST
#   2) ./scripts/terraform.sh output -raw public_ip (Docker; ./terraform if state exists)
#   3) aws: running instance with tag Name=DEPLOY_INSTANCE_NAME (default deepseek-cursor-proxy)
#
# Env: DEPLOY_EC2_SSH_KEY (default ~/deepseek-proxy-key.pem),
#      DEPLOY_AWS_REGION / AWS_REGION, DEPLOY_INSTANCE_NAME

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${TERRAFORM_CHDIR:-${DEPLOY_TERRAFORM_DIR:-$REPO_ROOT/terraform}}"
KEY="${DEPLOY_EC2_SSH_KEY:-${DEEPSEEK_PROXY_SSH_KEY:-$HOME/deepseek-proxy-key.pem}}"
REGION="${DEPLOY_AWS_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"
TAG="${DEPLOY_INSTANCE_NAME:-${DEEPSEEK_PROXY_INSTANCE_NAME:-deepseek-cursor-proxy}}"

if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
  echo "error: set CERTBOT_EMAIL for Let's Encrypt" >&2
  exit 1
fi
if [[ ! -f "$KEY" ]]; then
  echo "error: ssh key not found: $KEY" >&2
  exit 1
fi

discover_ip() {
  if [[ -n "${DEPLOY_EC2_HOST:-}" ]]; then
    printf '%s' "$DEPLOY_EC2_HOST"
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && [[ -f "${TF_DIR}/terraform.tfstate" || -d "${TF_DIR}/.terraform" ]]; then
    local tf_ip
    tf_ip="$(TERRAFORM_CHDIR="$TF_DIR" "$REPO_ROOT/scripts/terraform.sh" output -raw public_ip 2>/dev/null)" || true
    if [[ -n "$tf_ip" && "$tf_ip" != "null" ]]; then
      printf '%s' "$tf_ip"
      return 0
    fi
  fi
  if ! command -v aws >/dev/null 2>&1; then
    echo "error: set DEPLOY_EC2_HOST or install Docker + aws with Terraform state in ${TF_DIR}" >&2
    return 1
  fi
  local out
  out="$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=${TAG}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null)" || true
  if [[ -n "$out" && "$out" != "None" ]]; then
    printf '%s' "$out"
    return 0
  fi
  echo "error: no host (DEPLOY_EC2_HOST, terraform output, or running EC2 with Name=${TAG})" >&2
  return 1
}

IP="$(discover_ip)" || exit 1
SSLIP="${IP//./-}.sslip.io"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ec2-user@${IP}")

echo "deploy target ip=${IP} sslip=${SSLIP}"

TMP_NGINX="$(mktemp)"
sed "s/@SSLIP@/${SSLIP}/g" \
  "${REPO_ROOT}/deploy/nginx-deepseek-proxy.conf.template" \
  >"$TMP_NGINX"

rsync -az --delete \
  --exclude '.git' \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude '.ruff_cache' \
  --exclude 'terraform' \
  --exclude '.terraform' \
  "${REPO_ROOT}/" \
  "ec2-user@${IP}:~/deepseek-cursor-proxy/"

scp -i "$KEY" -o StrictHostKeyChecking=accept-new \
  "${REPO_ROOT}/deploy/99-deepseek-proxy-tcp.conf" \
  "ec2-user@${IP}:/tmp/99-deepseek-proxy-tcp.conf"

scp -i "$KEY" -o StrictHostKeyChecking=accept-new \
  "$TMP_NGINX" \
  "ec2-user@${IP}:/tmp/deepseek-proxy.conf"
rm -f "$TMP_NGINX"

"${SSH[@]}" bash -s <<REMOTE
set -euo pipefail
sudo cp /tmp/99-deepseek-proxy-tcp.conf /etc/sysctl.d/99-deepseek-proxy-tcp.conf
sudo sysctl --system

sudo dnf install -y nginx certbot python3-certbot-nginx

sudo mv /tmp/deepseek-proxy.conf /etc/nginx/conf.d/deepseek-proxy.conf
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

cd ~/deepseek-cursor-proxy
~/.local/bin/uv sync

sudo certbot --nginx -n --agree-tos -m "${CERTBOT_EMAIL}" -d "${SSLIP}" --redirect

sudo tee /etc/systemd/system/deepseek-proxy.service > /dev/null <<'UNIT'
[Unit]
Description=DeepSeek Cursor Proxy (fork + SSE keepalive)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/deepseek-cursor-proxy
ExecStart=/home/ec2-user/.local/bin/uv run deepseek-cursor-proxy --no-ngrok --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=20
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable deepseek-proxy
sudo systemctl restart deepseek-proxy
sleep 2
sudo systemctl is-active deepseek-proxy nginx
REMOTE

echo ""
echo "Cursor base URL: https://${SSLIP}/v1"
echo "Probe: curl -sS \"https://${SSLIP}/v1/models\" | head"
