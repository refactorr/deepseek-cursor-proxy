# Fork: deepseek-cursor-proxy

**Private GitHub fork:** https://github.com/refactorr/deepseek-cursor-proxy  
Upstream: [yxlao/deepseek-cursor-proxy](https://github.com/yxlao/deepseek-cursor-proxy).

## Implemented recommendations

| Recommendation | Where |
|----------------|--------|
| **SSE heartbeat / keepalive** | `server.py` sends `: dcp-keepalive` on `stream_keepalive_interval_seconds` (default **15s**; **0** disables). Config + `--stream-keepalive-interval`. |
| **HTTPS for Cursor** | `scripts/deploy-ec2-https.sh`: nginx reverse proxy + **Let’s Encrypt** on **`<public-ip-dashes>.sslip.io`**. App listens **127.0.0.1:8000** only. |
| **TCP sysctl** | `deploy/99-deepseek-proxy-tcp.conf` copied to `/etc/sysctl.d/` on deploy (`tcp_keepalive_*`). |
| **nginx long streams** | `deploy/nginx-deepseek-proxy.conf.template`: `proxy_read_timeout` / `proxy_send_timeout` **86400s**, `proxy_buffering off`. |
| **Process supervision** | Deploy writes `deepseek-proxy.service`: **`Restart=always`**, `network-online`, burst limits. |

Optional in Cursor: disable HTTP/2 for custom endpoints if you still see stream drops (forum workaround).

---

## 1. Terraform (manage EC2)

Requires **default VPC** in the account (or fork `terraform/main.tf` to your VPC/subnet).

### How to run Terraform (same rules as REDEV)

This repo follows the **local Terraform** rules in sibling checkout **`real-estate-development-project-management/AGENTS.md`** (and its `.cursor/rules/terraform-local-aws.mdc` / `terraform-fmt.mdc`): **do not use the host `terraform` binary** for this stack. Run **every** subcommand (`init`, `fmt`, `plan`, `apply`, `destroy`, `output`, `import`, …) through **`./scripts/terraform.sh`**, which wraps:

- **`docker run`** with image **`hashicorp/terraform:1.14`** (override with `TERRAFORM_DOCKER_IMAGE` if you pin a newer patch).
- **Repo mount:** `-v "$REPO_ROOT:/workspace"` and working dir **`/workspace/terraform`** (or a subdirectory of the repo if you set `TERRAFORM_CHDIR` / `DEPLOY_TERRAFORM_DIR` to an absolute path under the repo root).
- **AWS credentials mount:** `-v "$HOME/.aws:/root/.aws:ro"` so the AWS provider uses the same profile/credential chain as your **`aws` CLI**. Ensure **`aws sts get-caller-identity`** succeeds on the host before `plan`/`apply`.
- **Linux:** the script adds **`-u "$(id -u):$(id -g)"`** so files Terraform writes under `terraform/` are not root-owned.

Required variables **must** be supplied via **`terraform.tfvars`**, **`-var`**, or **`-var-file`** (same as REDEV); do not assume `plan` works without inputs just because state exists.

**Format:** from repo root, match REDEV’s `terraform-fmt` pattern but with this repo’s path:

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  -v "$HOME/.aws:/root/.aws:ro" \
  -w /workspace/terraform \
  hashicorp/terraform:1.14 fmt -recursive
```

Day-to-day (wrapper forwards all args to `terraform`):

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit: key_name = "your-existing-ec2-key-pair-name"

./scripts/terraform.sh init
./scripts/terraform.sh plan
./scripts/terraform.sh apply
./scripts/terraform.sh output -raw cursor_base_url_https
```

`./scripts/deploy-ec2-https.sh` and `./scripts/stream-proxy-logs.sh` call this wrapper for **`terraform output`** when state exists under `terraform/` (respects **`TERRAFORM_CHDIR`** / **`DEPLOY_TERRAFORM_DIR`** like the wrapper).

Creates: **security group** (22/80/443), **Amazon Linux 2023** instance, **Elastic IP**, minimal **user-data** (git + uv for `ec2-user`).

SSH key: use an **existing** AWS EC2 key pair name in `key_name`; PEM path on laptop must match `DEPLOY_EC2_SSH_KEY` (default `~/deepseek-proxy-key.pem`) when you deploy.

**Instance you created outside this Terraform:** set `DEPLOY_EC2_HOST` and run the deploy script. Ensure the instance **security group allows TCP 80 and 443** (and 22 for SSH). Importing that instance into this Terraform state is possible (`./scripts/terraform.sh import aws_instance.proxy i-…`) but you must align SG/EIP in config with what already exists, or expect Terraform to want replacement.

---

## 2. Deploy app + TLS + sysctl

Wait until **user-data** finishes (git + `uv` for `ec2-user`): ~1–2 minutes after first boot (`tail /var/log/user-data.log` on the box).

After `terraform apply` (or for an **already running** instance, set **`DEPLOY_EC2_HOST=<public-ip>`** so discovery skips Terraform):

```bash
export CERTBOT_EMAIL='you@example.com'
export DEPLOY_EC2_SSH_KEY="$HOME/.ssh/your-key.pem"   # if not using default path
./scripts/deploy-ec2-https.sh
```

Script: **rsync** repo → `~/deepseek-cursor-proxy` on the instance, **sysctl**, **nginx + certbot**, **`uv sync`**, **systemd** restart.

Cursor **Base URL**: `./scripts/terraform.sh output -raw cursor_base_url_https`  
(or `https://<ip-with-dashes>.sslip.io/v1`).

---

## 3. Stream logs

Uses **Terraform outputs** when `${REPO_ROOT}/terraform/.terraform` exists: **`public_ip`**, **`ssh_user`**, **`systemd_journal_unit`**. No AWS tag discovery.

```bash
./scripts/stream-proxy-logs.sh
# optional host override (still uses ssh_user + journal unit from Terraform if initialized):
DEPLOY_EC2_HOST=x.x.x.x ./scripts/stream-proxy-logs.sh
# non-default Terraform dir:
TERRAFORM_CHDIR=/path/to/terraform ./scripts/stream-proxy-logs.sh
```

Requires **`./scripts/terraform.sh init`** (and **`apply`**) in `./terraform` unless you pass **`DEPLOY_EC2_HOST`** / first argument (plain IP or `user@host`). Needs **Docker** for Terraform output discovery.

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
