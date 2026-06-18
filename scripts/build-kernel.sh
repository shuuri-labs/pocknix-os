#!/usr/bin/env bash
# build-kernel.sh — build the linux-pocknix kernel for SM8550/RP6 and assemble the
# qcom-abl boot image. Reproduces ROCKNIX's recipe (packages/linux/package.mk):
#
#   stock kernel.org linux-${KERNEL_VERSION}
#     + patch stack in order: kernel/patches/{10-mainline,20-sm8550,30-version}
#     + RP6 device trees (kernel/dts) with ensured Makefile entries
#     + SM8550 config (kernel/config/linux.aarch64.conf)
#   -> make Image dtbs modules
#   -> boot image = gzip(Image) ++ appended DTBs, dummy ramdisk, mkbootimg (header v0)
#
# We boot a plain ext4 root with NO initramfs (UFS/SCSI/ext4 are built-in), so the
# cmdline uses a standard root= spec (KERNEL_CMDLINE) instead of ROCKNIX's
# LibreELEC boot=/disk=LABEL= convention, and the ramdisk stays a dummy.
#
# Outputs:
#   build/kernel/out/{Image,dtbs/,modroot/lib/modules/<ver>/,kernelrelease}
#   build/image/KERNEL   (the qcom-abl boot image -> deploy to /flash/KERNEL)

source "$(dirname "$0")/lib.sh"
need_linux
for t in curl tar xz gzip make gcc bc flex bison python3 git rsync patch; do need_tool "$t"; done

KBUILD="${BUILD_DIR}/kernel"
KSRC="${KBUILD}/linux-${KERNEL_VERSION}"
JOBS="${JOBS:-$(nproc)}"
MKBOOTIMG=""

# native on aarch64, else require an aarch64 cross toolchain
if [ "$(uname -m)" = "aarch64" ]; then
  CROSS=""
else
  CROSS="${CROSS_COMPILE:-aarch64-linux-gnu-}"
  have "${CROSS}gcc" || die "cross-building on $(uname -m): need ${CROSS}gcc (or set CROSS_COMPILE)"
  log "cross-compiling with ${CROSS}"
fi
kmake() { make -C "${KSRC}" ARCH=arm64 ${CROSS:+CROSS_COMPILE=${CROSS}} "$@"; }

fetch_source() {
  mkdir -p "${CACHE_DIR}" "${KBUILD}"
  local tb="${CACHE_DIR}/linux-${KERNEL_VERSION}.tar.xz"
  if [ ! -f "${tb}" ]; then
    log "downloading kernel source: ${KERNEL_SOURCE_URL}"
    curl -fL --retry 3 -o "${tb}" "${KERNEL_SOURCE_URL}"
  else
    log "using cached kernel source: ${tb}"
  fi
  if [ -n "${KERNEL_SOURCE_SHA256}" ]; then
    echo "${KERNEL_SOURCE_SHA256}  ${tb}" | sha256sum -c - || die "kernel source sha256 mismatch"
    ok "kernel source checksum verified"
  else
    warn "KERNEL_SOURCE_SHA256 unset — build is NOT reproducible (pin it for releases)"
  fi
  log "extracting source -> ${KSRC}"
  rm -rf "${KSRC}"
  tar -C "${KBUILD}" -xf "${tb}"
}

apply_patches() {
  local d p n
  for d in "${KERNEL_DIR}"/patches/*/; do
    [ -d "${d}" ] || continue
    n=0
    for p in "${d}"*.patch; do
      [ -f "${p}" ] || continue
      patch -p1 -d "${KSRC}" < "${p}" >/dev/null || die "patch failed to apply: ${p}"
      n=$((n+1))
    done
    log "applied $(basename "${d}"): ${n} patches"
  done
}

install_dts() {
  log "installing RP6 device trees + ensuring Makefile entries"
  rsync -a "${KERNEL_DIR}/dts/" "${KSRC}/arch/arm64/boot/dts/"
  local mk="${KSRC}/arch/arm64/boot/dts/qcom/Makefile" dts name
  for dts in "${KSRC}"/arch/arm64/boot/dts/qcom/qcs8550-*.dts; do
    [ -f "${dts}" ] || continue
    name="$(basename "${dts}" .dts)"
    if ! grep -q "${name}.dtb" "${mk}"; then
      echo "dtb-\$(CONFIG_ARCH_QCOM) += ${name}.dtb" >> "${mk}"
      log "  registered ${name}.dtb in qcom/Makefile"
    fi
  done
}

configure() {
  log "configuring kernel (.config from linux.aarch64.conf; no embedded initramfs)"
  sed -e "s|@DEVICENAME@|${DEVICE}|g" \
      -e 's|@INITRAMFS_SOURCE@||g' \
      "${KERNEL_DIR}/config/linux.aarch64.conf" > "${KSRC}/.config"

  # pocknix kernel config deltas (applied on top of the synced ROCKNIX config, so
  # they survive `make sync`):
  #  - zstd-compressed firmware loading (Arch ships firmware as .zst)
  #  - DRM_MSM as a MODULE: built-in, it probes before the rootfs is mounted and its
  #    GPU firmware (a740_sqe.fw, on the rootfs) fails to load (-2). As a module it
  #    loads post-root via udev, when /usr/lib/firmware is available. We have no
  #    initramfs, so early firmware must come via a module-load-after-root, not =y.
  "${KSRC}/scripts/config" --file "${KSRC}/.config" \
    --enable FW_LOADER_COMPRESS \
    --enable FW_LOADER_COMPRESS_ZSTD \
    --module DRM_MSM

  # olddefconfig auto-accepts defaults for any new symbols (no prompts, no stdin).
  # NB: do NOT pipe `yes` into it — `yes` would take SIGPIPE and, under pipefail,
  # abort the script with exit 141.
  kmake olddefconfig >/dev/null
}

build_kernel() {
  log "building Image + dtbs + modules (-j${JOBS}) — this takes a while"
  kmake -j"${JOBS}" Image dtbs modules
}

stage() {
  log "staging artifacts -> ${KBUILD}/out"
  rm -rf "${KBUILD}/out"
  mkdir -p "${KBUILD}/out/dtbs"
  cp "${KSRC}/arch/arm64/boot/Image" "${KBUILD}/out/Image"
  find "${KSRC}/arch/arm64/boot/dts" -name '*.dtb' -exec cp {} "${KBUILD}/out/dtbs/" \;
  kmake INSTALL_MOD_PATH="${KBUILD}/out/modroot" modules_install >/dev/null
  rm -f "${KBUILD}/out/modroot"/lib/modules/*/build "${KBUILD}/out/modroot"/lib/modules/*/source
  kmake -s kernelrelease > "${KBUILD}/out/kernelrelease"
  ok "kernel $(cat "${KBUILD}/out/kernelrelease") staged ($(ls "${KBUILD}/out/dtbs" | wc -l | tr -d ' ') dtbs)"
}

fetch_mkbootimg() {
  MKBOOTIMG="${KBUILD}/mkbootimg/mkbootimg.py"
  [ -f "${MKBOOTIMG}" ] && return 0
  log "fetching mkbootimg (${MKBOOTIMG_COMMIT:0:12})"
  rm -rf "${KBUILD}/mkbootimg-src"
  git clone -q "${MKBOOTIMG_URL}" "${KBUILD}/mkbootimg-src" || die "mkbootimg clone failed"
  git -C "${KBUILD}/mkbootimg-src" checkout -q "${MKBOOTIMG_COMMIT}" \
    || warn "mkbootimg: pinned commit unavailable, using clone HEAD"
  mkdir -p "${KBUILD}/mkbootimg"
  cp -r "${KBUILD}/mkbootimg-src/gki" "${KBUILD}/mkbootimg-src/mkbootimg.py" "${KBUILD}/mkbootimg/"
}

# Assemble the qcom-abl boot image. $1 = optional ramdisk path; default is a dummy
# (we have no initramfs). gzip(Image) with all DTBs appended is the "kernel".
assemble_bootimg() {
  fetch_mkbootimg
  mkdir -p "${IMAGE_DIR}"
  local kgz="${KBUILD}/out/kernel.gz" ramdisk="${1:-}" d
  gzip -c "${KBUILD}/out/Image" > "${kgz}"
  for d in "${KBUILD}"/out/dtbs/*.dtb; do [ -f "${d}" ] && cat "${d}" >> "${kgz}"; done
  if [ -z "${ramdisk}" ]; then
    # We don't use an initramfs (UFS/ext4 are built in). Ship a VALID empty cpio
    # so the kernel unpacks it cleanly instead of printing "Initramfs unpacking
    # failed" (harmless, but noisy). Falls back to a dummy string if cpio is absent.
    ramdisk="${KBUILD}/out/ramdisk.empty"
    if have cpio; then
      printf '' | cpio -o -H newc --quiet > "${ramdisk}" 2>/dev/null
    else
      printf 'dummy' > "${ramdisk}"
    fi
  fi
  log "assembling qcom-abl boot image -> ${IMAGE_DIR}/KERNEL"
  python3 "${MKBOOTIMG}" \
    --kernel "${kgz}" --ramdisk "${ramdisk}" \
    --kernel_offset 0x00000000 --ramdisk_offset 0x00000000 --tags_offset 0x00000000 \
    --os_version 12.0.0 --os_patch_level "$(date '+%Y-%m')" --header_version 0 \
    --cmdline "${KERNEL_CMDLINE}" \
    -o "${IMAGE_DIR}/KERNEL" || die "mkbootimg failed"
  ok "boot image ready -> ${IMAGE_DIR}/KERNEL"
  log "cmdline: ${KERNEL_CMDLINE}"
}

main() {
  fetch_source
  apply_patches
  install_dts
  configure
  build_kernel
  stage
  assemble_bootimg "$@"
  ok "linux-pocknix build complete"
}
main "$@"
