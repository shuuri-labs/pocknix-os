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
  # Register exactly the dts files the SoC tree ships (whatever their prefix —
  # the boot image carries ALL of them; the qcom ABL selects by board id, which
  # is what lets one SoC kernel package serve every device on that SoC).
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

# Vendor downstream trace events (e.g. include/trace/events/qcom_haptics.h) still use the
# pre-6.10 two-argument __assign_str(dst, src); kernel 6.10+ made it one-arg (the src is now
# taken from the __string(dst, src) declaration). These never compiled while tracing was off,
# but enabling FTRACE/BPF_EVENTS (for scx_lavd, see configure()) turns TRACEPOINTS on, so every
# built driver's TRACE_EVENT expands for real and the stale ones break the build with
# "macro '__assign_str' passed 2 arguments, but takes just 1". Apply upstream's mechanical
# migration — drop the redundant 2nd arg — to every trace-event-defining header in the tree.
# Only stale two-arg call sites match; correct one-arg sites (no comma) and __assign_str_len
# are untouched. (__string itself is unchanged and stays two-arg.)
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

  # pocknix kernel config deltas (applied on top of the synced ROCKNIX config, so
  # they survive `make sync`):
  #  - zstd-compressed firmware loading (Arch ships firmware as .zst)
  #  - Android binder + binderfs for Waydroid: the synced config has ANDROID_BINDER_IPC
  #    off, so the container can't start. binderfs creates the binder/hwbinder/vndbinder
  #    devices dynamically.
  #  - USB/IP vhci-hcd =m: InputPlumber's "Valve Steam Deck Controller" target is a
  #    virtual USB device on vhci-hcd; without it the physical gamepad is hidden and no
  #    virtual one appears, so Steam sees no controller.
  #  - sched_ext (SCHED_CLASS_EXT) + BTF (DEBUG_INFO_BTF), so scx_lavd (pocknix-lavd.service)
  #    can load: a sched_ext program attaches only if /sys/kernel/btf/vmlinux exists, which
  #    needs DEBUG_INFO_BTF=y and pahole at compile time. BTF depends on !DEBUG_INFO_REDUCED
  #    (the sm8550 base sets REDUCED), and the whole debug-info choice is hidden without
  #    DEBUG_KERNEL (the sm8250 base disables it, so the choice falls to DEBUG_INFO_NONE).
  #    Either way olddefconfig drops BTF and SCHED_CLASS_EXT silently, with no "is not set"
  #    line: so DEBUG_KERNEL on, REDUCED off, the choice forced onto DWARF_TOOLCHAIN_DEFAULT.
  #  - KALLSYMS_ALL: also DEBUG_KERNEL-gated and missing from the sm8250 base config.
  #    scx_lavd resolves the per-cpu 'runqueues' ksym via kallsyms, and DATA symbols are
  #    only listed with _ALL; without it the prog load dies with "ldimm64 failed to find".
  #  - SCHED_CLUSTER: cluster-aware scheduler topology for the big.LITTLE DynamIQ parts.
  #  - tracing / BPF events (FTRACE, KPROBES, KPROBE_EVENTS, PERF_EVENTS -> BPF_EVENTS):
  #    scx_lavd's BPF objects call bpf_trace_printk and attach tracepoints; with FTRACE off
  #    the helper proto is absent and the verifier rejects the whole scheduler (-EINVAL,
  #    crash-loop). BPF_EVENTS is def_bool y once KPROBE_EVENTS + PERF_EVENTS are on.
  #  - FUNCTION_TRACER + DYNAMIC_FTRACE: scx-scheds attaches fentry programs, which need
  #    the BPF trampoline, and on arm64 that needs dynamic-ftrace direct calls. Without them
  #    the attach fails -ENOTSUPP (524) and the session falls back to EEVDF, where Steam's
  #    nice-19 main thread starves. DYNAMIC_FTRACE NOPs the call sites at boot, so the idle
  #    cost is ~zero. The WITH_CALL_OPS/WITH_DIRECT_CALLS variants are not directly
  #    selectable; they follow from these two via olddefconfig (asserted below).
  #  - default cpufreq governor performance -> schedutil: LAVD does its own per-core DVFS
  #    via scx_bpf_cpuperf_set(), which only schedutil honours; under performance the
  #    clocks pin to max and the thermal headroom is lost. Still runtime-overridable.
  #  - QCOM_Q6V5_PAS =m: built in (as the synced sm8250 config ships it) the adsp/cdsp/slpi
  #    remoteprocs probe before the initramfs-less root holds /usr/lib/firmware, and remoteproc
  #    never retries a failed request_firmware: the DSPs stay offline and the q6 sound card
  #    never assembles. =m loads post-root; no-op on sm8550, which already ships =m.
  #  - UNICODE =y: SteamOS formats SD cards with the ext4 `casefold` feature, and ext4
  #    refuses to mount a casefold filesystem without CONFIG_UNICODE, so a card from another
  #    Deck would never mount here. Built in, not a module: filesystems mount before modules.
  #  - BTRFS_FS =y: the root filesystem, and there is no initramfs, so a `make sync` flipping
  #    it to =m would ship an image that cannot mount its own root. Pinned + asserted below.
  #  - PM_DEBUG + PM_SLEEP_DEBUG: /sys/power/pm_wakeup_irq (which irq woke us) and
  #    /sys/power/pm_test (staged suspend entry that auto-resumes per stage) for
  #    suspend triage on a device with no serial console.
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

  # olddefconfig auto-accepts defaults for any new symbols (no prompts, no stdin).
  # NB: do NOT pipe `yes` into it — `yes` would take SIGPIPE and, under pipefail,
  # abort the script with exit 141.
  kmake olddefconfig >/dev/null

  # Assert the whole scx_lavd chain actually resolved: the fentry/BPF-trampoline
  # symbols (attach fails ENOTSUPP without them) AND BTF + sched_ext themselves —
  # olddefconfig silently drops any of these when a dependency is missing
  # (REDUCED on sm8550, DEBUG_INFO_NONE on sm8250), and the failure only
  # shows up on-device as pocknix-lavd's ConditionPathExists quietly skipping.
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

# `make dtbs` builds ~400 upstream boards; shipping them all adds ~43 MB to the
# boot image and floods the ABL's device model menu with unrelated phones (it
# lists every appended dtb carrying qcom,msm-id). Keep only this SoC's boards.
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
    # We don't use an initramfs (UFS/btrfs are built in). Ship a VALID empty cpio
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
  fixup_trace_events
  configure
  build_kernel
  stage
  case "${BOOTLOADER}" in
    arm-efi)
      # ROCKNIX arm-efi contract (SM8250): the ABL chainloads GRUB, whose
      # "linux /KERNEL" line loads a RAW arm64 Image. The dtb is a separate
      # "devicetree /boot/grub/<board>.dtb" file and the cmdline lives in
      # grub.cfg (shipped by pocknix-bootloader-<soc>). No Android boot image,
      # no mkbootimg, no appended dtbs.
      mkdir -p "${IMAGE_DIR}"
      cp "${KBUILD}/out/Image" "${IMAGE_DIR}/KERNEL"
      ok "raw Image staged -> ${IMAGE_DIR}/KERNEL (arm-efi: cmdline + dtb come from GRUB)"
      ;;
    *)
      assemble_bootimg "$@"
      # Stage the on-device boot-image rebuild inputs into out/ for the linux-pocknix-<soc>
      # package: the mkbootimg tool, so the package's alpm hook can rebuild /flash/KERNEL on the
      # device exactly the way this build does. (The cmdline the hook reads is shipped by the
      # device BSP; out/cmdline is kept as a build record of what the boot image was given.)
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
