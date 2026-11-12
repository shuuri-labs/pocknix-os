#!/usr/bin/env bash
# sync.sh — refresh the vendored ROCKNIX inputs for the selected device's SoC
# (kernel/${SOC}/, chosen by the device profile) into two destinations:
#
#   kernel/${SOC}/ (COMMITTED) — the full kernel input set: patch stack, DTS,
#             kernel config, firmware list. A PINNED SNAPSHOT of ROCKNIX `next`
#             (nightly) + our delta (lineage: kernel/README.md);
#             committing it makes pocknix-os self-contained and reproducible.
#             `make sync` advances the pin from your distribution/ checkout:
#             review the git diff and commit the result.
#
#   vendor/   (GITIGNORED) — build-time-only material that we do NOT redistribute:
#             ROCKNIX reference scripts to adapt, and the device firmware/overlay
#             (stock firmware comes from linux-firmware at build instead).
#
# Set DISTRIBUTION_DIR to your ROCKNIX 'distribution' checkout (on a `next`-based branch).

source "$(dirname "$0")/lib.sh"

[ -d "${ROCKNIX_DEVICE_DIR}" ] || die "ROCKNIX device dir not found: ${ROCKNIX_DEVICE_DIR}
  set DISTRIBUTION_DIR to your 'distribution' checkout, e.g.
  export DISTRIBUTION_DIR=\$HOME/Documents/Coding/distribution"

log "syncing ROCKNIX ${ROCKNIX_SOC} from ${ROCKNIX_PROJECT_DIR}"

# --- committed kernel enablement -> kernel/${SOC}/ --------------------------
# The SoC's full ROCKNIX patch stack as numbered subdirs, in scripts/unpack order; kernel/common/
# stays outside every rsync. -c: size+mtime misses a same-size edit made within the same second.
log "  kernel enablement -> kernel/${SOC}/ (committed)"
mkdir -p "${KERNEL_DIR}/patches/10-mainline" \
         "${KERNEL_DIR}/patches/20-version" \
         "${KERNEL_DIR}/patches/30-${SOC}" \
         "${KERNEL_DIR}/dts" "${KERNEL_DIR}/config"
rsync -ac --delete "${ROCKNIX_PROJECT_DIR}/packages/linux/patches/mainline/" "${KERNEL_DIR}/patches/10-mainline/"
# version dir name set in kernel.conf: it has lagged KERNEL_VERSION before
rsync -ac --delete "${ROCKNIX_PROJECT_DIR}/packages/linux/patches/${ROCKNIX_VERSION_PATCH_DIR:-${KERNEL_VERSION%.*}}/" "${KERNEL_DIR}/patches/20-version/"
rsync -ac --delete "${ROCKNIX_DEVICE_DIR}/patches/linux/"                     "${KERNEL_DIR}/patches/30-${SOC}/"
# dts / config
rsync -ac --delete "${ROCKNIX_DEVICE_DIR}/linux/dts/"                 "${KERNEL_DIR}/dts/"
rsync -ac          "${ROCKNIX_DEVICE_DIR}/linux/linux.aarch64.conf"   "${KERNEL_DIR}/config/"
rsync -ac          "${ROCKNIX_DEVICE_DIR}/config/kernel-firmware.dat" "${KERNEL_DIR}/config/"

# --- local delta: restore what the rsync --delete above removed or overwrote ---------
# sync-keep: "path" = our edit of an upstream file, "+path" = our file, "-path" = deleted here;
# 1000+ patches are ours by convention. Each warning below is a case to merge by hand.
kernel_rel="${KERNEL_DIR#"${POCKNIX_ROOT}"/}"
in_git() { git -C "${POCKNIX_ROOT}" ls-files --error-unmatch -- "${kernel_rel}/$1" >/dev/null 2>&1; }
differs() { ! git -C "${POCKNIX_ROOT}" diff --quiet HEAD -- "${kernel_rel}/$1"; }
restore() { git -C "${POCKNIX_ROOT}" checkout HEAD -- "${kernel_rel}/$1"; nrestored=$((nrestored + 1)); }
nrestored=0
if [ -f "${KERNEL_DIR}/sync-keep" ]; then
  while IFS= read -r line; do
    case "${line}" in
      ''|'#'*) continue ;;
      -*) rm -f "${KERNEL_DIR}/${line#-}"; continue ;;
      +*) p="${line#+}" ;;
      *) p="${line}" ;;
    esac
    in_git "${p}" || { warn "  sync-keep lists ${p}, which is not in git (stale line?)"; continue; }
    if [ ! -e "${KERNEL_DIR}/${p}" ]; then
      [ "${line}" = "${p}" ] && warn "  upstream no longer ships ${p}; restored our edit"
    elif [ "${line}" != "${p}" ]; then
      differs "${p}" && warn "  upstream now ships ${p} too; kept ours"
    else
      differs "${p}" && warn "  kept our edit of ${p}; merge any upstream change to it by hand"
    fi
    restore "${p}"
  done < "${KERNEL_DIR}/sync-keep"
fi
while IFS= read -r f; do
  p="${f#"${kernel_rel}"/}"
  if [ ! -e "${KERNEL_DIR}/${p}" ]; then restore "${p}"; log "  restored ${p} (ours: 1000+)"
  elif differs "${p}"; then warn "  upstream ships ${p} with different content; kept upstream's"
  fi
done < <(git -C "${POCKNIX_ROOT}" ls-files "${kernel_rel}/patches/30-${SOC}/1[0-9][0-9][0-9]-*")
[ "${nrestored}" -eq 0 ] || log "  restored ${nrestored} local-delta files from git"

# --- gitignored reference material -> vendor/ (no build reads it) ----------
dst="${VENDOR_DIR}/rocknix-${SOC}"
log "  reference scripts + device filesystem -> vendor/ (gitignored)"
mkdir -p "${dst}/filesystem"
rsync -ac --delete "${ROCKNIX_DEVICE_DIR}/filesystem/" "${dst}/filesystem/"
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
  # pre-create nested parents: macOS's old rsync won't make implied dirs
  mkdir -p "${dst}/reference/${p}"
  rsync -ac --delete "${src}/" "${dst}/reference/${p}/"
done

ok "sync complete:
  kernel/${SOC}/  (committed)  $(find "${KERNEL_DIR}/patches" -name '*.patch' 2>/dev/null | wc -l | tr -d ' ') patches + dts + config
  vendor/         (gitignored) reference scripts + device filesystem"
