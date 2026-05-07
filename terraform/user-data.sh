#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

# AL2023: avoid replacing curl-minimal with full curl package.
dnf install -y git

# uv for ec2-user (deploy script rsyncs app; uv sync runs on instance).
sudo -u ec2-user bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'

echo "user-data: git + uv installed"
