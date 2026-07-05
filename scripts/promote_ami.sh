#!/usr/bin/env bash
# Promote an AMI: point the launch-template SSM parameters at it.
# The launch templates resolve these at instance launch, so the next fleet
# the Spot Event Plugin requests boots the new image, Deadline and
# Terraform untouched. 
#
# Rollback = re-run with the previous AMI ID
# (previous values are kept as SSM parameter history).
#
# Usage: promote_ami.sh <ami-id> <worker-class>...
#        promote_ami.sh ami-0abc123 cpu gpu
set -euo pipefail

NAME_PREFIX="${NAME_PREFIX:-render-farm-dev}"

ami_id="${1:?usage: promote_ami.sh <ami-id> <worker-class>...}"
shift
[ $# -gt 0 ] || { echo "ERROR: no worker classes given" >&2; exit 1; }

# Refuse to promote an AMI that doesn't exist / isn't ours.
state=$(aws ec2 describe-images --image-ids "$ami_id" \
  --query 'Images[0].State' --output text)
if [ "$state" != "available" ]; then
  echo "ERROR: $ami_id state is '$state', not 'available'" >&2
  exit 1
fi

for class in "$@"; do
  param="/${NAME_PREFIX}/ami/${class}-worker"
  aws ssm put-parameter --name "$param" --type String \
    --value "$ami_id" --overwrite >/dev/null
  echo "Promoted ${param} -> ${ami_id}"
done
