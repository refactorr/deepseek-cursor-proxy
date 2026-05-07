# Fork: deepseek-cursor-proxy

**Private GitHub fork:** https://github.com/refactorr/deepseek-cursor-proxy  
Upstream: [yxlao/deepseek-cursor-proxy](https://github.com/yxlao/deepseek-cursor-proxy).

## Implemented recommendations

| Recommendation | Where |
|----------------|--------|
| **SSE heartbeat / keepalive** | `server.py` sends `: dcp-keepalive` on `stream_keepalive_interval_seconds` (default **15s**; **0** disables). Config + `--stream-keepalive-interval`. |
| **HTTPS for Cursor** | `scripts/deploy-ec2-https.sh`: **nginx** + **Let’s Encrypt** (certbot) for **`<public-ip-dashes>.sslip.io`** — public DNS maps that name to your Elastic IP without Route53. App listens **127.0.0.1:8000** behind nginx. |
| **TCP sysctl** | `deploy/99-deepseek-proxy-tcp.conf` copied to `/etc/sysctl.d/` on deploy (`tcp_keepalive_*`). |
| **nginx long streams** | `deploy/nginx-deepseek-proxy.conf.template`: `server_name` includes **sslip + raw public IP** so `http://<ip>/v1` and `https://<sslip>/v1` both hit the proxy; `proxy_read_timeout` / `proxy_send_timeout` **86400s**, `proxy_buffering off`. |
| **Process supervision** | Deploy writes `deepseek-proxy.service`: **`Restart=always`**, `network-online`, burst limits. |

**sslip.io** is third-party DNS (not AWS); **Let’s Encrypt** is third-party CA. If sslip’s shared zone hits LE rate limits, retry later or use HTTP (`cursor_base_url_http` output) until certbot succeeds.

Optional in Cursor: disable HTTP/2 for custom endpoints if you still see stream drops (forum workaround).

### HTTPS entirely on AWS (optional later)

**ACM + ALB** in front of EC2 avoids sslip/LE on the VM but needs **your domain** in Route 53 (or elsewhere) and adds **~tens USD/month** for a typical ALB. ACM certs for ALB use are free.

---

## 1. Terraform (manage EC2)

Requires **default VPC** in the account (or fork `terraform/main.tf` to your VPC/subnet).

### How to run Terraform (same rules as REDEV)

This repo follows the **local Terraform** rules in sibling checkout **`real-estate-development-project-management/AGENTS.md`** (and its `.cursor/rules/terraform-local-aws.mdc` / `terraform-fmt.mdc`): **do not use the host `terraform` binary** for this stack. Run **every** subcommand through **`./scripts/terraform.sh`** (Docker **`hashicorp/terraform:1.14`**, repo + **`~/.aws`**:ro mount).

Required inputs: **`terraform.tfvars`**, **`TERRAFORM_VAR_FILE`**, and/or **`-var`** (REDEV-style: **`-var='key_name=my-key'`**). **`plan` / `apply` / `destroy`** get **`-input=false`** when omitted. See **`scripts/terraform.sh`** header comments.

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit: key_name = "your-existing-ec2-key-pair-name"

./scripts/terraform.sh init
./scripts/terraform.sh plan
./scripts/terraform.sh apply
./scripts/terraform.sh output -raw cursor_base_url_https
./scripts/terraform.sh output -raw cursor_base_url_http
./scripts/terraform.sh output -raw certbot_junk_email   # ACME contact (default acme-le-junk@daggrai.com)
```

Junk **CERTBOT_EMAIL** is defined in Terraform only as a string (`certbot_junk_domain` + `certbot_junk_local_part`); **no mailbox** is created in AWS. Point real MX at that address elsewhere if you want to receive LE mail.

Creates: **security group** (22, **80**, **443**) — **ingress from `0.0.0.0/0`** (no IP allowlist). The Terraform **`description`** field is left unchanged on purpose: in the AWS provider, changing it **replaces the whole security group** (slow and can appear stuck while ENIs update). Anyone on the internet can attempt SSH and hit nginx; use a strong key, keep the proxy patched, and tighten rules in production if you need to.

**Instance outside Terraform:** set **`DEPLOY_EC2_HOST`** and deploy; open **80** / **443** / **22** on that instance’s SG from the networks you use (this Terraform stack uses **0.0.0.0/0** for those ports).

---

## 2. Deploy app + TLS (sslip + certbot)

```bash
export DEPLOY_EC2_SSH_KEY="$HOME/.ssh/your-key.pem"   # if not ~/deepseek-proxy-key.pem
# CERTBOT_EMAIL: optional — export, ~/.bash_profile, or omit if terraform output certbot_junk_email works
./scripts/deploy-ec2-https.sh
# or: make deploy-https   (optional: CERTBOT_EMAIL=... to override)
```

Script: **rsync** → `~/deepseek-cursor-proxy`, **sysctl**, **nginx** + **certbot** + **python3-certbot-nginx**, **`uv sync`**, **systemd**, then **certbot** for **`https://<ip-dashes>.sslip.io`**.

Cursor **Base URL** (HTTPS): `./scripts/terraform.sh output -raw cursor_base_url_https`  
Fallback (HTTP): **`cursor_base_url_http`**.

---

## 3. Stream logs

Uses **Terraform outputs** when `terraform/.terraform` exists: **`public_ip`**, **`ssh_user`**, **`systemd_journal_unit`**.

```bash
./scripts/stream-proxy-logs.sh
DEPLOY_EC2_HOST=x.x.x.x ./scripts/stream-proxy-logs.sh
```

**Dev “run” loop (save compute when idle):** start the Terraform instance if it is stopped, deploy, stream `journalctl`, then **stop the instance** when you exit the stream (Ctrl+C). Leave it running with **`SKIP_STOP_ON_EXIT=1`**.

```bash
make run
# or: make start   (same)
# or: ./scripts/run.sh

make stop   # stop the instance if running (Terraform outputs + aws CLI)
```

---

## Run / test (local)

```bash
uv sync --extra dev
uv run python -m unittest discover -s tests -q
uv run deepseek-cursor-proxy --help
```

## Fork-only behavior

- **SSE stream keepalive** (see table above).
- **Config / CLI:** `stream_keepalive_interval_seconds` in `~/.deepseek-cursor-proxy/config.yaml`; CLI `--stream-keepalive-interval SECONDS`.
