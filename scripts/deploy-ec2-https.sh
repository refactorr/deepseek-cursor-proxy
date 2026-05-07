#!/usr/bin/env bash
set -euo pipefail

# Push this repo to EC2: sysctl, nginx (:80 for ACME + reverse proxy to 127.0.0.1:8000),
# Let's Encrypt via certbot for <ip-dashes>.sslip.io, uv sync, systemd.
# sslip.io is public DNS mapping that hostname to your Elastic IP (no AWS Route53 required for the name).
#
# Prereqs: docker (Terraform output), aws, ssh, rsync; ACME contact email; SSH key.
# CERTBOT_EMAIL: env, ~/.bash_profile (sourced if unset), else terraform output certbot_junk_email.
#
#   export CERTBOT_EMAIL='you@example.com'
#   ./scripts/deploy-ec2-https.sh
#
# Host resolution: DEPLOY_EC2_HOST, terraform output public_ip, or AWS tag Name=...

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${TERRAFORM_CHDIR:-${DEPLOY_TERRAFORM_DIR:-$REPO_ROOT/terraform}}"
KEY="${DEPLOY_EC2_SSH_KEY:-${DEEPSEEK_PROXY_SSH_KEY:-$HOME/deepseek-proxy-key.pem}}"
REGION="${DEPLOY_AWS_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"
TAG="${DEPLOY_INSTANCE_NAME:-${DEEPSEEK_PROXY_INSTANCE_NAME:-deepseek-cursor-proxy}}"

if [[ -z "${CERTBOT_EMAIL:-}" && -f "${HOME}/.bash_profile" ]]; then
  set +eu
  set +o pipefail 2>/dev/null || true
  # shellcheck disable=SC1090
  source "${HOME}/.bash_profile" 2>/dev/null || true
  set -euo pipefail
fi

if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
  tf_email=""
  if tf_email="$(TERRAFORM_CHDIR="$TF_DIR" "$REPO_ROOT/scripts/terraform.sh" output -raw certbot_junk_email 2>/dev/null)" \
    && [[ -n "$tf_email" && "$tf_email" != "null" ]]; then
    CERTBOT_EMAIL="$tf_email"
  fi
fi
if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
  echo "error: CERTBOT_EMAIL unset — export it, add to ~/.bash_profile, or ensure 'terraform output certbot_junk_email' succeeds (Docker + state in ${TF_DIR})" >&2
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

RSYNC_SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new)
RSYNC_RSH="${RSYNC_SSH[*]}"

TMP_NGINX="$(mktemp)"
sed "s/@SSLIP@/${SSLIP}/g" \
  "${REPO_ROOT}/deploy/nginx-deepseek-proxy.conf.template" \
  >"$TMP_NGINX"

rsync -az --delete \
  -e "$RSYNC_RSH" \
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

# TLS (sslip.io + Let's Encrypt; may hit shared sslip.io LE rate limits)
if sudo certbot --nginx -n --agree-tos -m "${CERTBOT_EMAIL}" -d "${SSLIP}" --redirect; then
  echo "certbot: certificate installed for ${SSLIP}"
else
  echo "certbot: failed (e.g. sslip.io Let's Encrypt rate limit). Use HTTP until retry succeeds:" >&2
  echo "  http://${IP}/v1" >&2
fi
REMOTE

HTTPS_BASE="https://${SSLIP}/v1"
HTTP_BASE="http://${IP}/v1"
# Give nginx / LE a moment; probe from this machine (same path Cursor uses).
sleep 3
https_code="000"
https_code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 25 \
  "${HTTPS_BASE}/models" -H "Authorization: Bearer test" 2>/dev/null || true)"
http_code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 15 \
  "${HTTP_BASE}/models" -H "Authorization: Bearer test" 2>/dev/null || true)"

echo ""
echo "================================================================================"
echo "  CURSOR CUSTOM API BASE URL (paste into Cursor → model provider Base URL):"
if [[ "$https_code" == "200" ]]; then
  echo ""
  echo "    ${HTTPS_BASE}"
  echo ""
  echo "  HTTPS OK (sslip + certbot). Use your DeepSeek API key in Cursor; model e.g. deepseek-v4-pro."
elif [[ "$http_code" == "200" ]]; then
  echo ""
  echo "    ${HTTP_BASE}"
  echo ""
  echo "  HTTPS probe returned ${https_code} (not 200). Proxy is up on HTTP; fix certbot/LE then use:"
  echo "    ${HTTPS_BASE}"
else
  echo ""
  echo "    ${HTTPS_BASE}   (preferred once TLS works)"
  echo "    ${HTTP_BASE}    (fallback)"
  echo ""
  echo "  Probes from this machine failed (HTTPS=${https_code} HTTP=${http_code}). Check SG :80/:443, wait for DNS, or SSH ec2-user@${IP}"
fi
echo "================================================================================"
echo ""
echo "Sanity check: curl -sS \"${HTTP_BASE}/models\" -H \"Authorization: Bearer test\" | head -c 200"
echo "HTTPS check:  curl -sS \"${HTTPS_BASE}/models\" -H \"Authorization: Bearer test\" | head -c 200  (expect 200 when TLS up)"
