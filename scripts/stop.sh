#!/usr/bin/env bash
set -euo pipefail

# Stop the Terraform EC2 proxy instance if it is running (or pending).
# No-op if already stopped or stopping. Use: `make stop` or `./scripts/stop.sh`.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${TERRAFORM_CHDIR:-${DEPLOY_TERRAFORM_DIR:-$REPO_ROOT/terraform}}"
TF_SH="$REPO_ROOT/scripts/terraform.sh"

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

INSTANCE_ID="$(tf_raw instance_id)"
REGION="$(tf_raw aws_region)"

[[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "null" ]] || {
  echo "error: terraform output instance_id empty (apply in ${TF_DIR})" >&2
  exit 1
}
[[ -n "$REGION" && "$REGION" != "null" ]] || REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

STATE="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || true)"
[[ -n "$STATE" && "$STATE" != "None" ]] || {
  echo "error: cannot read instance state for $INSTANCE_ID" >&2
  exit 1
}

case "$STATE" in
stopped)
  echo "stop: instance $INSTANCE_ID already stopped" >&2
  exit 0
  ;;
stopping)
  echo "stop: instance $INSTANCE_ID already stopping" >&2
  exit 0
  ;;
running|pending)
  aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --output text >/dev/null
  echo "stop: stop requested for $INSTANCE_ID (was $STATE)" >&2
  exit 0
  ;;
*)
  echo "error: instance $INSTANCE_ID is in state '$STATE' (expected running, pending, stopping, or stopped)" >&2
  exit 1
  ;;
esac
