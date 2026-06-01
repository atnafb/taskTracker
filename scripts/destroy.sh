#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-app-tracker}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
TABLE_NAME="${TABLE_NAME:-AppTrackerTasks}"
DELETE_TABLE="${DELETE_TABLE:-false}"

INSTANCE_IDS="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters "Name=tag:Name,Values=${APP_NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)"

if [[ -n "$INSTANCE_IDS" ]]; then
  echo "Terminating instances: $INSTANCE_IDS"
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $INSTANCE_IDS >/dev/null
  aws ec2 wait instance-terminated --region "$AWS_REGION" --instance-ids $INSTANCE_IDS
fi

if [[ "$DELETE_TABLE" == "true" ]]; then
  echo "Deleting DynamoDB table $TABLE_NAME"
  aws dynamodb delete-table --region "$AWS_REGION" --table-name "$TABLE_NAME" >/dev/null
fi

echo "Done. Security group and IAM resources are left in place for reuse."
