#!/usr/bin/env bash
# install.sh — pointer to the ON-DEVICE internal installer.
#
# Installing to internal storage repartitions the device's internal UFS and clones the
# *running* system onto it, so it cannot run on the build host. It ships in the rootfs
# (via pocknix-tools) as /usr/bin/pocknix-install-internal — see its header for details.

source "$(dirname "$0")/lib.sh"
die "Run the installer ON THE DEVICE, not the build host:
    pocknix-install-internal --dry-run     # review the plan
    pocknix-install-internal               # install
See packages/shared/pocknix-tools/pocknix-install-internal."
