#!/usr/bin/env bash
# install.sh — pointer to the ON-DEVICE internal installer.
#
# Installing to internal storage repartitions the device's internal UFS and clones the *running*
# system onto it (like ROCKNIX installtointernal / armada-installer), so it cannot run on the build
# host — it runs on the SD-booted device. The installer ships in the rootfs (via the overlay) as:
#
#     /usr/local/bin/pocknix-install-internal
#
# On the device (the SD-booted pocknix), as root:
#     pocknix-install-internal --dry-run      # print the exact parted plan; make no changes
#     pocknix-install-internal                # interactive: choose the Android userdata size, confirm
#
# It shrinks Android `userdata` on /dev/sda, creates a FAT boot partition named ROCKNIX (the existing
# ROCKNIX ABL boots it) + an ext4 POCKNIX_ROOT, copies the current KERNEL, and clones the rootfs.
# ABL/xbl/modem/persist and everything before `userdata` are never touched. After it finishes: power
# off, remove the SD, boot — internal boots first. Iterate in place afterwards (scp + pacman -U, etc.).

source "$(dirname "$0")/lib.sh"
die "Run the installer ON THE DEVICE, not the build host:
    pocknix-install-internal --dry-run     # review the plan
    pocknix-install-internal               # install
See the header of this file (scripts/install.sh) and overlay/usr/local/bin/pocknix-install-internal."
