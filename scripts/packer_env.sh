#!/usr/bin/env bash
# Resolve the Packer build inputs from AWS by tag/name so the workflow never
# hardcodes IDs that Terraform owns. Emits KEY=VALUE lines for $GITHUB_ENV.
set -euo pipefail

NAME_PREFIX="${NAME_PREFIX:-render-farm-dev}"

subnet_id=$(aws ec2 describe-subnets \
  --filters "Name=tag:Tier,Values=public" "Name=tag:Name,Values=${NAME_PREFIX}-public-*" \
  --query 'Subnets[0].SubnetId' --output text)

if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
  echo "ERROR: no public subnet tagged ${NAME_PREFIX}-public-* — has terraform applied?" >&2
  exit 1
fi

account_id=$(aws sts get-caller-identity --query Account --output text)

echo "PACKER_SUBNET_ID=${subnet_id}"
echo "INSTALLERS_BUCKET=${NAME_PREFIX}-installers-${account_id}"
