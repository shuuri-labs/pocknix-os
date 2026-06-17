#!/usr/bin/env bash
# sync.sh — refresh the vendored ROCKNIX SM8550 inputs into two destinations:
#
#   kernel/   (COMMITTED)  — the RP6 kernel ENABLEMENT: patches, DTS, kernel
#             config, firmware list, qcom-abl bootloader packaging. This is the
#             RP6-specific kernel work and it lives IN the repo so pocknix-os is
#             self-contained (clone + build; no external ROCKNIX checkout needed
#             to have the kernel sources). `make sync` refreshes it from your
#             distribution/ checkout — review the git diff and commit the result.
#
#   vendor/   (GITIGNORED) — build-time-only material that we do NOT redistribute:
#             ROCKNIX reference scripts to adapt, and the device firmware/overlay
#             (stock firmware comes from linux-firmware at build instead).
#
# Unlike thorch (which syncs the whole kernel from public ROCKNIX at build time,
# gitignored), we commit *our* enablement and fetch only stock upstream Linux +
# stock firmware. Set DISTRIBUTION_DIR to your ROCKNIX 'distribution' checkout.

source "$(dirname "$0")/lib.sh"

[ -d "${ROCKNIX_DEVICE_DIR}" ] || die "ROCKNIX device dir not found: ${ROCKNIX_DEVICE_DIR}
  set DISTRIBUTION_DIR to your 'distribution' checkout, e.g.
  export DISTRIBUTION_DIR=\$HOME/Documents/Coding/distribution"

log "syncing ROCKNIX SM8550 from ${ROCKNIX_PROJECT_DIR}"

# --- committed kernel enablement -> kernel/ --------------------------------
# The full patch stack ROCKNIX applies for SM8550, in order (PKG_PATCH_DIRS=
# "mainline ${DEVICE} ... 7.0"). Stored as numbered subdirs so the build applies
# them in the same order: 10-mainline -> 20-sm8550 -> 30-version.
log "  kernel enablement -> kernel/ (committed)"
mkdir -p "${KERNEL_DIR}/patches/10-mainline" \
         "${KERNEL_DIR}/patches/20-sm8550" \
         "${KERNEL_DIR}/patches/30-version" \
         "${KERNEL_DIR}/dts" "${KERNEL_DIR}/config" "${KERNEL_DIR}/bootloader"
# generic ROCKNIX backports applied BEFORE device patches
rsync -a --delete "${ROCKNIX_PROJECT_DIR}/packages/linux/patches/mainline/" "${KERNEL_DIR}/patches/10-mainline/"
# our SM8550/RP6 device patches
rsync -a --delete "${ROCKNIX_DEVICE_DIR}/patches/linux/"                     "${KERNEL_DIR}/patches/20-sm8550/"
# generic version-specific patches applied AFTER device patches
rsync -a --delete "${ROCKNIX_PROJECT_DIR}/packages/linux/patches/7.0/"       "${KERNEL_DIR}/patches/30-version/"
# dts / config / bootloader packaging
rsync -a --delete "${ROCKNIX_DEVICE_DIR}/linux/dts/"                 "${KERNEL_DIR}/dts/"
rsync -a          "${ROCKNIX_DEVICE_DIR}/linux/linux.aarch64.conf"   "${KERNEL_DIR}/config/"
rsync -a          "${ROCKNIX_DEVICE_DIR}/config/kernel-firmware.dat" "${KERNEL_DIR}/config/"
rsync -a --delete "${ROCKNIX_DEVICE_DIR}/bootloader/"               "${KERNEL_DIR}/bootloader/"

# --- gitignored build-time material -> vendor/ -----------------------------
dst="${VENDOR_DIR}/rocknix-sm8550"
log "  reference scripts + firmware overlay -> vendor/ (gitignored)"
mkdir -p "${dst}/filesystem"
rsync -a --delete "${ROCKNIX_DEVICE_DIR}/filesystem/" "${dst}/filesystem/"
for p in \
    "emulators/standalone/steam" \
    "apps/gamescope" \
    "compat/fex-emu" \
    "hardware/quirks" \
    "linux"; do
  src="${ROCKNIX_PROJECT_DIR}/packages/${p}"
  if [ ! -d "${src}" ]; then
    warn "  (missing) ${src}"
    continue
  fi
  # pre-create nested parents: macOS rsync (2.6.9) won't make implied dirs
  mkdir -p "${dst}/reference/${p}"
  rsync -a --delete "${src}/" "${dst}/reference/${p}/"
done

ok "sync complete:
  kernel/  (committed)  $(find "${KERNEL_DIR}/patches" -name '*.patch' 2>/dev/null | wc -l | tr -d ' ') patches + dts + config
  vendor/  (gitignored) reference scripts + firmware overlay"
