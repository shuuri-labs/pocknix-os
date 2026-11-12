#!/usr/bin/env bash
# build-kernel.sh — build the linux-pocknix kernel for the selected device's SoC
# (kernel/${SOC}/, chosen by the device profile) and stage the boot artifact for
# the SoC's BOOTLOADER style: qcom-abl (mkbootimg Android boot image, sm8550) or
# arm-efi (raw Image loaded by GRUB, sm8250). The recipe:
#
#   stock kernel.org linux-${KERNEL_VERSION}   (pinned in kernel/${SOC}/kernel.conf)
#     + patch stack in numeric subdir order: kernel/${SOC}/patches/*/
#     + the SoC-neutral patches every SoC carries: kernel/common/patches/
#     + the SoC tree's device trees (kernel/${SOC}/dts) with ensured Makefile entries
#     + the SoC config (kernel/${SOC}/config/linux.aarch64.conf)
#   -> make Image dtbs modules
#   -> boot image = gzip(Image) ++ appended DTBs, empty cpio ramdisk, mkbootimg (header v0)
#
# We boot a btrfs root with NO initramfs (UFS/SCSI/btrfs are built-in), so the
# cmdline uses a standard root= spec (KERNEL_CMDLINE), not a
# boot=/disk=LABEL= convention, and the ramdisk stays an empty cpio.
#
# Outputs (per SoC):
#   build/kernel/<soc>/out/{Image,dtbs/,modroot/lib/modules/<ver>/,kernelrelease,soc}
#   build/image/<soc>/KERNEL   (qcom-abl: the boot image; arm-efi: the raw Image
#                               -> either way, deploy to /flash/KERNEL)

source "$(dirname "$0")/lib.sh"
need_linux
# pahole (pkg: dwarves) is required for CONFIG_DEBUG_INFO_BTF; without it olddefconfig
# silently drops BTF and the config gate dies late with a confusing message.
for t in curl tar xz gzip make gcc bc flex bison python3 git rsync pahole; do need_tool "$t"; done

KBUILD="${KERNEL_BUILD_DIR}"   # per-SoC: build/kernel/${SOC} (set in lib.sh)
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

fetch_source() { fetch_kernel_source "${KBUILD}"; }
apply_patches() { apply_kernel_patches "${KSRC}" "${KERNEL_DIR}"; }

install_dts() {
  log "installing ${SOC} device trees + ensuring Makefile entries"
  rsync -a "${KERNEL_DIR}/dts/" "${KSRC}/arch/arm64/boot/dts/"
  # Register every dts the SoC tree ships: the qcom ABL picks by board id among all of them, so
  # one kernel package serves every device on the SoC.
  local mk="${KSRC}/arch/arm64/boot/dts/qcom/Makefile" dts name
  for dts in "${KERNEL_DIR}"/dts/qcom/*.dts; do
    [ -f "${dts}" ] || continue
    name="$(basename "${dts}" .dts)"
    if ! grep -q "${name}.dtb" "${mk}"; then
      echo "dtb-\$(CONFIG_ARCH_QCOM) += ${name}.dtb" >> "${mk}"
      log "  registered ${name}.dtb in qcom/Makefile"
    fi
  done
}

# Vendor trace headers keep the pre-6.10 two-arg __assign_str, which breaks once TRACEPOINTS is
# on (scx_lavd): drop the 2nd arg. One-arg sites and __assign_str_len don't match.
fixup_trace_events() {
  log "fixing stale two-arg __assign_str() in vendor trace events (post-6.10 one-arg API)"
  grep -rlZ --include='*.h' -e 'DECLARE_EVENT_CLASS' -e 'TRACE_EVENT' "${KSRC}" 2>/dev/null \
    | xargs -0 -r sed -i -E 's/__assign_str\(([^,()]+),[^()]*\)/__assign_str(\1)/g'
}

configure() {
  log "configuring kernel (.config from linux.aarch64.conf; no embedded initramfs)"
  sed -e "s|@DEVICENAME@|${DEVICE_HOSTNAME}|g" \
      -e "s|^CONFIG_DEFAULT_HOSTNAME=.*|CONFIG_DEFAULT_HOSTNAME=\"${DEVICE_HOSTNAME}\"|" \
      -e 's|@INITRAMFS_SOURCE@||g' \
      "${KERNEL_DIR}/config/linux.aarch64.conf" > "${KSRC}/.config"

  # Deltas over the synced config (they survive make sync), and what each is for:
  #  FW_LOADER_COMPRESS_ZSTD: Arch ships firmware as .zst. ANDROID_BINDER*: Waydroid.
  #  USBIP_VHCI_HCD =m: InputPlumber's Steam Deck pad is a vhci device; without it Steam sees none.
  #  SCHED_CLASS_EXT + DEBUG_INFO_BTF (scx_lavd): olddefconfig drops both silently unless
  #    DEBUG_KERNEL is on, DEBUG_INFO_REDUCED off and the choice forced to DWARF_TOOLCHAIN_DEFAULT.
  #  KALLSYMS_ALL: scx_lavd resolves the per-cpu 'runqueues' ksym ("ldimm64 failed to find").
  #  SCHED_CLUSTER: cluster-aware topology for the big.LITTLE DynamIQ parts.
  #  FTRACE, KPROBES, KPROBE/UPROBE_EVENTS, PERF_EVENTS (-> BPF_EVENTS): scx_lavd's BPF tracing;
  #    without FTRACE the verifier rejects the whole scheduler.
  #  FUNCTION_TRACER + DYNAMIC_FTRACE: fentry needs the BPF trampoline (else ENOTSUPP, EEVDF).
  #    The WITH_DIRECT_CALLS/WITH_CALL_OPS variants follow via olddefconfig; never --enable them.
  #  schedutil default: LAVD's per-core DVFS (scx_bpf_cpuperf_set) only works under schedutil.
  #  QCOM_Q6V5_PAS =m: built in, the DSPs probe before root holds firmware and never retry.
  #  UNICODE =y: SteamOS-formatted cards use ext4 casefold; built in, as filesystems mount first.
  #  BTRFS_FS =y: the root filesystem, with no initramfs. PM_*DEBUG: suspend triage, no serial.
  "${KSRC}/scripts/config" --file "${KSRC}/.config" \
    --module QCOM_Q6V5_PAS \
    --enable PM_DEBUG \
    --enable PM_SLEEP_DEBUG \
    --enable UNICODE \
    --enable BTRFS_FS \
    --enable FW_LOADER_COMPRESS \
    --enable FW_LOADER_COMPRESS_ZSTD \
    --enable ANDROID \
    --enable ANDROID_BINDER_IPC \
    --enable ANDROID_BINDERFS \
    --set-str ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder" \
    --module USBIP_CORE \
    --module USBIP_VHCI_HCD \
    --enable DEBUG_KERNEL \
    --enable KALLSYMS_ALL \
    --enable SCHED_CLUSTER \
    --disable DEBUG_INFO_NONE \
    --enable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
    --disable DEBUG_INFO_REDUCED \
    --enable DEBUG_INFO_BTF \
    --enable SCHED_CLASS_EXT \
    --enable FTRACE \
    --enable FUNCTION_TRACER \
    --enable DYNAMIC_FTRACE \
    --enable KPROBES \
    --enable KPROBE_EVENTS \
    --enable UPROBE_EVENTS \
    --enable PERF_EVENTS \
    --enable BPF_EVENTS \
    --disable CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
    --enable CPU_FREQ_DEFAULT_GOV_SCHEDUTIL

  # Per-SoC deltas and assertions live beside kernel.conf, where make sync leaves them alone.
  local delta="${KERNEL_DIR}/config-delta" assert="${KERNEL_DIR}/config-assert"
  if [ -f "${delta}" ]; then
    local -a dargs=() words
    local line
    while IFS= read -r line; do
      read -r -a words <<< "${line%%#*}"
      [ "${#words[@]}" -eq 0 ] || dargs+=("${words[@]}")
    done < "${delta}"
    [ "${#dargs[@]}" -eq 0 ] || "${KSRC}/scripts/config" --file "${KSRC}/.config" "${dargs[@]}"
  fi

  # Takes defaults without prompting. Never pipe `yes` in: SIGPIPE under pipefail exits 141.
  kmake olddefconfig >/dev/null

  # olddefconfig drops any of these silently when a dependency is missing, and on the device that
  # only shows as pocknix-lavd's ConditionPathExists skipping.
  local sym
  for sym in FUNCTION_TRACER DYNAMIC_FTRACE DYNAMIC_FTRACE_WITH_DIRECT_CALLS \
             DEBUG_INFO_BTF SCHED_CLASS_EXT KALLSYMS_ALL; do
    grep -q "^CONFIG_${sym}=y" "${KSRC}/.config" \
      || die "kernel config: CONFIG_${sym} did not resolve to =y (scx_lavd would not run — check the dependency olddefconfig dropped it for)"
  done

  # btrfs must be BUILT-IN: there is no initramfs, so =m means the kernel cannot
  # mount its own root on snapshot-capable (btrfs) images.
  grep -q "^CONFIG_BTRFS_FS=y" "${KSRC}/.config" \
    || die "kernel config: CONFIG_BTRFS_FS did not resolve to =y (btrfs root would be unmountable — no initramfs)"

  if [ -f "${assert}" ]; then
    for sym in $(sed 's/#.*//' "${assert}"); do
      grep -q "^CONFIG_${sym}=y" "${KSRC}/.config" \
        || die "kernel config: CONFIG_${sym} did not resolve to =y (listed in kernel/${SOC}/config-assert)"
    done
  fi
}

build_kernel() {
  log "building Image + dtbs + modules (-j${JOBS}) — this takes a while"
  kmake -j"${JOBS}" Image dtbs modules
}

# make dtbs builds ~400 boards: shipped whole they add ~43 MB and flood the ABL's model menu with
# unrelated phones. Keep this SoC's only.
stage_dtbs() {
  local dts name src n=0
  for dts in "${KERNEL_DIR}"/dts/*/*.dts; do
    [ -f "${dts}" ] || continue
    name="$(basename "${dts}" .dts)"
    src="$(find "${KSRC}/arch/arm64/boot/dts" -name "${name}.dtb" -print -quit)"
    [ -n "${src}" ] || die "dtb not built for shipped board ${name}.dts — is it registered in the qcom Makefile? (install_dts)"
    cp "${src}" "${KBUILD}/out/dtbs/"
    n=$((n+1))
  done
  [ "${n}" -gt 0 ] || die "no dtbs staged — ${KERNEL_DIR}/dts ships no .dts files?"
}

stage() {
  log "staging artifacts -> ${KBUILD}/out"
  rm -rf "${KBUILD}/out"
  mkdir -p "${KBUILD}/out/dtbs"
  cp "${KSRC}/arch/arm64/boot/Image" "${KBUILD}/out/Image"
  stage_dtbs
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

# Assemble the qcom-abl boot image. $1 = optional ramdisk path; default is an empty
# cpio (we have no initramfs). gzip(Image) with all DTBs appended is the "kernel".
assemble_bootimg() {
  fetch_mkbootimg
  mkdir -p "${IMAGE_DIR}"
  local kgz="${KBUILD}/out/kernel.gz" ramdisk="${1:-}" d
  gzip -c "${KBUILD}/out/Image" > "${kgz}"
  for d in "${KBUILD}"/out/dtbs/*.dtb; do [ -f "${d}" ] && cat "${d}" >> "${kgz}"; done
  if [ -z "${ramdisk}" ]; then
    # No initramfs (UFS/btrfs built in): a valid empty cpio avoids "Initramfs unpacking failed".
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
  fixup_trace_events
  configure
  build_kernel
  stage
  case "${BOOTLOADER}" in
    arm-efi)
      # arm-efi: GRUB's "linux /KERNEL" loads a raw Image; the dtb and cmdline come from grub.cfg
      # (pocknix-bootloader-<soc>). No Android boot image, no appended dtbs.
      mkdir -p "${IMAGE_DIR}"
      cp "${KBUILD}/out/Image" "${IMAGE_DIR}/KERNEL"
      ok "raw Image staged -> ${IMAGE_DIR}/KERNEL (arm-efi: cmdline + dtb come from GRUB)"
      ;;
    *)
      assemble_bootimg "$@"
      # The package ships mkbootimg so its alpm hook rebuilds /flash/KERNEL the same way on the
      # device; out/cmdline is only a build record (the hook reads the BSP's).
      rm -rf "${KBUILD}/out/mkbootimg"
      cp -r "${KBUILD}/mkbootimg" "${KBUILD}/out/mkbootimg"
      ;;
  esac
  printf '%s' "${KERNEL_CMDLINE}" > "${KBUILD}/out/cmdline"
  # SoC marker: records which SoC produced out/, so downstream checks catch a copied/renamed dir.
  printf '%s' "${SOC}" > "${KBUILD}/out/soc"
  ok "${KERNEL_PKG} build complete"
}
main "$@"
