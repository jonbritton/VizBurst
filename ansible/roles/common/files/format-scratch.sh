#!/usr/bin/env bash
# Format and mount local NVMe instance storage as /scratch (asset cache +
# render workspace). Instance store is ephemeral — this runs on every boot.
# Falls back to a plain directory on instance types without instance store.
set -euo pipefail

MOUNT=/scratch
mkdir -p "$MOUNT"

# First unmounted non-root NVMe device, if any.
dev=""
for d in /dev/nvme*n1; do
  [ -e "$d" ] || continue
  mount | grep -q "^$d" && continue
  # Skip the root device (it has partitions).
  [ -e "${d}p1" ] && continue
  dev="$d"
  break
done

if [ -n "$dev" ]; then
  blkid "$dev" >/dev/null 2>&1 || mkfs.ext4 -q -L scratch "$dev"
  mountpoint -q "$MOUNT" || mount "$dev" "$MOUNT"
fi

chown render:render "$MOUNT"
