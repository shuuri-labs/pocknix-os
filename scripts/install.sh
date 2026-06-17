#!/usr/bin/env bash
# install.sh — internal-storage installer (Phase 6, STUB).
#
# Target: write the built rootfs to the internal root partition and the
# qcom-abl boot image to /flash/KERNEL, PRESERVING the existing ROCKNIX ABL and
# Android recovery (do NOT touch ABL). Keeps /flash/KERNEL.bak for rollback.
# Will adapt ROCKNIX devices/SM8550/bootloader/update.sh + thorch-install-internal.

source "$(dirname "$0")/lib.sh"

die "install.sh is a Phase 6 stub — not implemented yet.
Planned flow (see plan.md Phase 6):
  1. back up /flash/KERNEL -> /flash/KERNEL.bak
  2. write build/image/KERNEL -> /flash/KERNEL  (FAT boot partition)
  3. write build/rootfs       -> internal root partition (ext4, label ${ROOT_LABEL})
  4. leave qcom-abl bootloader + Android recovery untouched"
