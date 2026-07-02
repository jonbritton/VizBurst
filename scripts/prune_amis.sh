#!/usr/bin/env bash
# Deregister old worker AMIs and their snapshots, keeping the newest N.
# AMIs are cheap but not free (snapshot storage), and stale ones are clutter
# nobody should ever launch.
#
# Usage: prune_amis.sh [keep-count]   (default 3)
set -euo pipefail

NAME_PREFIX="${NAME_PREFIX:-render-farm-dev}"
keep="${1:-3}"

# Newest first, skip the ones we keep.
mapfile -t old_amis < <(aws ec2 describe-images --owners self \
  --filters "Name=name,Values=${NAME_PREFIX}-worker-*" \
  --query 'sort_by(Images, &CreationDate) | reverse(@) | [].ImageId' \
  --output text | tr '\t' '\n' | tail -n "+$((keep + 1))")

if [ ${#old_amis[@]} -eq 0 ]; then
  echo "Nothing to prune (<= ${keep} worker AMIs exist)."
  exit 0
fi

for ami in "${old_amis[@]}"; do
  [ -n "$ami" ] || continue
  mapfile -t snapshots < <(aws ec2 describe-images --image-ids "$ami" \
    --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text | tr '\t' '\n')
  echo "Deregistering ${ami}"
  aws ec2 deregister-image --image-id "$ami"
  for snap in "${snapshots[@]}"; do
    [ -n "$snap" ] && [ "$snap" != "None" ] || continue
    echo "  deleting ${snap}"
    aws ec2 delete-snapshot --snapshot-id "$snap"
  done
done
