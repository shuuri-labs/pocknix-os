#!/usr/bin/env bash
# sync.sh — refresh the vendored ROCKNIX inputs for the selected device's SoC
# (kernel/${SOC}/, chosen by the device profile) into two destinations:
#
#   kernel/${SOC}/ (COMMITTED) — the full kernel input set: patch stack, DTS,
#             kernel config, firmware list, qcom-abl bootloader packaging. A PINNED
#             SNAPSHOT of ROCKNIX `next` (nightly) + jaewun's suspend branch + our
#             delta. The RP6 is officially supported upstream, so most of this is
#             public ROCKNIX work; committing it makes pocknix-os self-contained
#             and reproducible. `make sync` advances the pin from your
#             distribution/ checkout — review the git diff and commit the result.
#
#   vendor/   (GITIGNORED) — build-time-only material that we do NOT redistribute:
#             ROCKNIX reference scripts to adapt, and the device firmware/overlay
#             (stock firmware comes from linux-firmware at build instead).
#
# Thorch auto-fetches ROCKNIX nightly at build (gitignored); we pin + commit a
# nightly snapshot instead (reproducible, clone-standalone). We track nightly
# (`next`), not stable. Set DISTRIBUTION_DIR to your ROCKNIX 'distribution'
# checkout (expected on a `next`-based branch, e.g. thor-suspend-merge).

source "$(dirname "$0")/lib.sh"

[ -d "${ROCKNIX_DEVICE_DIR}" ] || die "ROCKNIX device dir not found: ${ROCKNIX_DEVICE_DIR}
  set DISTRIBUTION_DIR to your 'distribution' checkout, e.g.
  export DISTRIBUTION_DIR=\$HOME/Documents/Coding/distribution"

log "syncing ROCKNIX ${ROCKNIX_SOC} from ${ROCKNIX_PROJECT_DIR}"

# --- committed kernel enablement -> kernel/${SOC}/ --------------------------
# The full patch stack ROCKNIX applies for this SoC, in order (PKG_PATCH_DIRS=
# "mainline ${DEVICE} ... 7.0"). Stored as numbered subdirs so the build applies
# them in the same order: 10-mainline -> 20-<soc> -> 30-version.
log "  kernel enablement -> kernel/${SOC}/ (committed)"
mkdir -p "${KERNEL_DIR}/patches/10-mainline" \
         "${KERNEL_DIR}/patches/20-${SOC}" \
         "${KERNEL_DIR}/patches/30-version" \
         "${KERNEL_DIR}/dts" "${KERNEL_DIR}/config" "${KERNEL_DIR}/bootloader"
# generic ROCKNIX backports applied BEFORE device patches
rsync -a --delete "${ROCKNIX_PROJECT_DIR}/packages/linux/patches/mainline/" "${KERNEL_DIR}/patches/10-mainline/"
# the SoC device patches
rsync -a --delete "${ROCKNIX_DEVICE_DIR}/patches/linux/"                     "${KERNEL_DIR}/patches/20-${SOC}/"
# generic version-specific patches applied AFTER device patches (dir name set in
# kernel.conf - ROCKNIX keeps using "7.0" for the 7.1.x series)
rsync -a --delete "${ROCKNIX_PROJECT_DIR}/packages/linux/patches/${ROCKNIX_VERSION_PATCH_DIR:-${KERNEL_VERSION%.*}}/" "${KERNEL_DIR}/patches/30-version/"
# dts / config / bootloader packaging
rsync -a --delete "${ROCKNIX_DEVICE_DIR}/linux/dts/"                 "${KERNEL_DIR}/dts/"
rsync -a          "${ROCKNIX_DEVICE_DIR}/linux/linux.aarch64.conf"   "${KERNEL_DIR}/config/"
rsync -a          "${ROCKNIX_DEVICE_DIR}/config/kernel-firmware.dat" "${KERNEL_DIR}/config/"
rsync -a --delete "${ROCKNIX_DEVICE_DIR}/bootloader/"               "${KERNEL_DIR}/bootloader/"

# --- gitignored build-time material -> vendor/ -----------------------------
dst="${VENDOR_DIR}/rocknix-${SOC}"
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
  kernel/${SOC}/  (committed)  $(find "${KERNEL_DIR}/patches" -name '*.patch' 2>/dev/null | wc -l | tr -d ' ') patches + dts + config
  vendor/         (gitignored) reference scripts + firmware overlay"
