#!/bin/bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Grow the userdata partition (p5) of a disk written with mkimg_gpt.sh so it
# fills the whole disk. Run on a Linux host with the SD card / eMMC attached
# (USB reader or eMMC adapter), or from a Linux system booted on the board.
#
# Usage: sudo ./grow_userdata.sh /dev/sdX
#
set -euo pipefail

DISK=${1:?usage: $0 /dev/sdX (whole disk, not a partition)}
USERDATA_START=7417856   # must match mkimg_gpt.sh

[ -b "${DISK}" ] || { echo "Not a block device: ${DISK}" >&2; exit 1; }
for tool in sgdisk partprobe e2fsck resize2fs lsblk; do
  command -v "${tool}" >/dev/null || { echo "Missing ${tool}" >&2; exit 1; }
done

case "${DISK}" in
  *mmcblk*|*nvme*|*loop*) PART="${DISK}p5" ;;
  *) PART="${DISK}5" ;;
esac

if lsblk -nro MOUNTPOINT "${DISK}" | grep -q .; then
  echo "Unmount all partitions of ${DISK} first." >&2
  exit 1
fi

START=$(sgdisk -i 5 "${DISK}" | awk '/^First sector:/ {print $3}')
NAME=$(sgdisk -i 5 "${DISK}" | sed -n "s/^Partition name: '\(.*\)'$/\1/p")
if [ "${START}" != "${USERDATA_START}" ] || [ "${NAME}" != "userdata" ]; then
  echo "Partition 5 on ${DISK} is not the expected userdata partition (start ${START}, name '${NAME}')." >&2
  exit 1
fi

echo "Moving the backup GPT to the end of ${DISK}..."
sgdisk -e "${DISK}"

echo "Recreating partition 5 (userdata) to the end of the disk..."
sgdisk -d 5 -n 5:${USERDATA_START}:0 -t 5:8300 -c 5:userdata "${DISK}"
partprobe "${DISK}"
sleep 1

echo "Resizing the userdata filesystem..."
e2fsck -fy "${PART}" || [ $? -le 1 ]
resize2fs "${PART}"

sgdisk -p "${DISK}"
echo "Done."
