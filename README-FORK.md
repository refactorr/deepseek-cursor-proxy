# REDEV fork of deepseek-cursor-proxy

**Private GitHub fork (same name as upstream):** https://github.com/refactorr/deepseek-cursor-proxy  
Forked from: [yxlao/deepseek-cursor-proxy](https://github.com/yxlao/deepseek-cursor-proxy).

Suggested local clone: `~/dev/deepseek-cursor-proxy` with `origin` = this repo, `upstream` = yxlao.

## Changes in this fork

- **SSE stream keepalive:** while upstream `readline()` blocks, a background thread sends SSE comment lines (`: dcp-keepalive`) on a configurable interval so long gaps between tokens still produce TCP traffic. May reduce idle timeouts through proxies; does not fix intentional client disconnects.
- **Config / CLI:** `stream_keepalive_interval_seconds` in `config.yaml` (default `15`). Set to `0` to disable. CLI: `--stream-keepalive-interval SECONDS`.

## Run / test

```bash
cd ~/dev/deepseek-cursor-proxy
uv sync --extra dev
uv run python -m unittest discover -s tests -q
uv run deepseek-cursor-proxy --help
```

## Deploy to EC2 (HTTPS + sysctl)

From **REDEV** repo root (needs `aws`, `ssh`, `scp`, `rsync`, `CERTBOT_EMAIL`). Deploy script reads this tree from **`DEEPSEEK_CURSOR_PROXY_FORK_ROOT`** (default `~/dev/deepseek-cursor-proxy`).

```bash
export CERTBOT_EMAIL='you@example.com'
./scripts/deploy-deepseek-ec2-https.sh
```

Uses **sslip.io** (`<public-ip-with-dashes>.sslip.io`), **nginx** + **Let’s Encrypt**, binds the app to **127.0.0.1:8000** behind TLS.
