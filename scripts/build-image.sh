#!/usr/bin/env bash
# build-image.sh — full pocknix-os image build.
#
# Pipeline (Phase 0 establishes the skeleton; later phases fill the stubs):
#   bootstrap -> configure pacman -> install packages -> [kernel] -> [sessions] -> assemble
#
# Phase 0 status: bootstrap + pacman configuration + package install are wired.
# Steps that depend on later phases are clearly marked STUB and are no-ops for now.

source "$(dirname "$0")/lib.sh"
need_linux
need_root build
for t in curl tar rsync sed; do need_tool "$t"; done

LOCAL_REPO_DIR="${BUILD_DIR}/localrepo"

render_pacman_conf() {
  local out="$1"
  log "rendering pacman.conf (ALARM base)"
  cp -f "${CONFIG_DIR}/pacman.conf.in" "${out}"
}

# Appended only when their packages are installed (Phase 3+), so the Phase 0 base
# install never depends on an unwired/unreachable repo.
append_holo_repo() {
  local out="$1"
  grep -q "^\[${HOLO_RELEASE}\]" "${out}" && return 0
  log "adding holo repo (${HOLO_RELEASE})"
  cat >> "${out}" <<EOF

[${HOLO_RELEASE}]
SigLevel = Optional TrustAll
Server = ${HOLO_REPO_URL}/${HOLO_RELEASE}/os/aarch64
EOF
}
# The local repo lives on the host; we bind-mount it to /localrepo inside the rootfs
# chroot, so the repo Server is that in-chroot path.
append_local_repo() {
  local out="$1"
  grep -q '^\[pocknix\]' "${out}" && return 0
  log "adding local pocknix repo"
  cat >> "${out}" <<EOF

[pocknix]
SigLevel = Optional TrustAll
Server = file:///localrepo
EOF
}

# Build the local pocknix-* packages and install them into the rootfs:
#   pocknix-bsp (board support) + gamescope (ROCKNIX-patched, epoch=1 -> beats ALARM's;
#   vanilla gamescope can't drive the RP6's rotated msm panel — see plan.md Phase 3).
install_local_packages() {
  local root="$1"
  if [ ! -f "${LOCAL_REPO_DIR}/pocknix.db" ]; then
    warn "no local repo at ${LOCAL_REPO_DIR} (build-packages.sh didn't run?) — skipping local pkgs"
    return 0
  fi
  log "installing local pocknix packages (pocknix-bsp, gamescope, inputplumber, pocknix-steam)"
  append_local_repo "${root}/etc/pacman.conf"
  mkdir -p "${root}/localrepo"
  mount --bind "${LOCAL_REPO_DIR}" "${root}/localrepo"
  chroot "${root}" pacman -Sy --noconfirm
  # gamescope deps (xorg-xwayland, seatd, libdisplay-info, …) resolve from ALARM.
  # inputplumber = gamepad -> Steam Input (RP6 config shipped by pocknix-bsp).
  # pocknix-steam = the Steam session (launcher + installer); pulls local gtk2 + gamescope +
  # pocknix-steamos-shim and ALARM deps (openal, libcups, lsof, noto-fonts*, networkmanager, …).
  # pocknix-steamos-shim = steamos-update/branch/BIOS stubs so the Deck UI OOBE doesn't dead-end.
  # fex-emu + fex-rootfs = x86 game content via Proton (FEX emulator + thunks + the ~1.1 GB Arch x86
  # squashfs the games' libraries resolve from). Validated on hardware 2026-06-22; +~1.1 GB to the image.
  chroot "${root}" pacman -S --noconfirm --needed \
        pocknix-bsp gamescope inputplumber pocknix-steamos-shim mangohud pocknix-steam \
        fex-emu fex-rootfs
  # GUARD: these local builds MUST come from [pocknix], not silently fall back / go missing. gamescope
  # especially: ALARM's vanilla lacks --use-rotation-shader and black-screens on the RP6 (bitten 3x).
  local gs_ver; gs_ver="$(chroot "${root}" pacman -Q gamescope 2>/dev/null | awk '{print $2}')"
  case "${gs_ver}" in
    1:*rocknix*) log "gamescope OK: ${gs_ver} (epoch-1 patched build)" ;;
    *) umount "${root}/localrepo" 2>/dev/null || true
       die "gamescope is '${gs_ver}', NOT the epoch-1 [pocknix] rocknix build. Vanilla gamescope can't drive the RP6 panel (no --use-rotation-shader) -> black screen. Build it first: 'make packages PKG=gamescope' and confirm build/localrepo/gamescope-1:*.pkg.tar.* exists, then re-run." ;;
  esac
  local lp
  for lp in fex-emu fex-rootfs; do
    chroot "${root}" pacman -Q "${lp}" >/dev/null 2>&1 || {
      umount "${root}/localrepo" 2>/dev/null || true
      die "${lp} not installed — its local build wasn't in [pocknix]. Build it: 'make packages PKG=${lp}' (fex-rootfs downloads the ~1.1 GB Arch x86 squashfs once), confirm build/localrepo/${lp}-*.pkg.tar.* exists, then re-run."
    }
  done
  umount "${root}/localrepo"
  rmdir "${root}/localrepo" 2>/dev/null || true
  # drop the build-only [pocknix] repo from the shipped config — its file:///localrepo
  # bind mount doesn't exist on the running device, so it would break `pacman -Sy` there.
  sed -i '/^\[pocknix\]/,+2d' "${root}/etc/pacman.conf"
}

read_pkglist() {
  # One package per line, optional inline "# comment". Strip the comment and take the first
  # token: `sed 's/#.*//'` alone LEAVES the whitespace before the # (e.g. "vulkan-tools     "),
  # which pacman then can't match -> "target not found". awk $1 drops surrounding whitespace and
  # blank/comment-only lines cleanly.
  awk '{ sub(/#.*/, ""); if ($1 != "") print $1 }' "$1"
}

configure_keyring() {
  local root="$1"
  log "initialising pacman keyring (archlinuxarm)"
  chroot "${root}" pacman-key --init
  chroot "${root}" pacman-key --populate archlinuxarm
}

install_packages() {
  local root="$1"; shift
  local lists=("$@")
  local pkgs=()
  for l in "${lists[@]}"; do
    mapfile -t -O "${#pkgs[@]}" pkgs < <(read_pkglist "${l}")
  done
  log "installing ${#pkgs[@]} packages from: ${lists[*]##*/}"
  # -Syy (force DB refresh): a reused rootfs keeps a stale sync DB, and plain -Sy won't
  # re-download a DB pacman thinks is current -> valid extra pkgs (vulkan-tools, alsa-utils,
  # alsa-ucm-conf) show up as "target not found". Safe here: this is a fresh-image -Su anyway.
  chroot "${root}" pacman -Syyu --noconfirm --needed "${pkgs[@]}"
}

# Install the SM8550 device firmware (ath12k wifi board data, adsp/cdsp, vpu, ...)
# from ROCKNIX's synced overlay into the rootfs. It's a large synced vendor blob,
# so installed directly here rather than packaged (could become pocknix-firmware later).
FW_SRC="${VENDOR_DIR}/rocknix-sm8550/filesystem/usr/lib/kernel-overlays/base/lib/firmware"
install_firmware() {
  local root="$1"
  if [ -d "${FW_SRC}" ]; then
    log "installing SM8550 device firmware -> rootfs /usr/lib/firmware ($(du -sh "${FW_SRC}" | cut -f1))"
    mkdir -p "${root}/usr/lib/firmware"
    rsync -a "${FW_SRC}/" "${root}/usr/lib/firmware/"
  else
    warn "ROCKNIX firmware overlay not at ${FW_SRC} — run 'make sync' (wifi/audio firmware will be missing)"
  fi
}

# Install the linux-pocknix modules into the rootfs and remove the generic ALARM
# kernel. Requires `make kernel` to have produced build/kernel/out first.
install_kernel() {
  local root="$1"
  local out="${BUILD_DIR}/kernel/out"
  if [ ! -d "${out}/modroot/lib/modules" ]; then
    warn "no kernel artifacts in ${out} — run 'make kernel' first; skipping kernel integration"
    return 0
  fi
  local kver; kver="$(cat "${out}/kernelrelease" 2>/dev/null)"
  log "installing pocknix kernel modules (${kver}) + removing generic ALARM kernel"
  # the RP6 boots our qcom-abl /flash/KERNEL, not an ALARM initramfs kernel
  chroot "${root}" pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
  rm -rf "${root}/boot/initramfs-linux"*.img 2>/dev/null || true
  rsync -a "${out}/modroot/lib/modules/" "${root}/usr/lib/modules/"
  [ -n "${kver}" ] && chroot "${root}" depmod "${kver}" 2>/dev/null || true
}

main() {
  # 1. base rootfs
  "${POCKNIX_ROOT}/scripts/bootstrap.sh"

  # 1b. build the local pocknix-* packages (own build chroot) -> build/localrepo
  "${POCKNIX_ROOT}/scripts/build-packages.sh"

  # 2. pacman config + repos inside the rootfs
  mkdir -p "${LOCAL_REPO_DIR}"
  render_pacman_conf "${ROOTFS_DIR}/etc/pacman.conf"

  trap 'umount "${ROOTFS_DIR}/localrepo" 2>/dev/null || true; chroot_umount "${ROOTFS_DIR}"' EXIT
  chroot_mount "${ROOTFS_DIR}"
  configure_keyring "${ROOTFS_DIR}"

  # 3. packages: base now; session lists become active in Phase 3/4. gamescope/mangohud are
  #    in ALARM (no holo needed) — see config/packages/steam.list. Activate once GPU is up.
  install_packages "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/base.list"
  install_packages "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/steam.list"        # Phase 3 (ALARM): gamescope
  # install_packages  "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/desktop.list"   # Phase 4 (ALARM)

  # 4. kernel (Phase 1): use artifacts from `make kernel`. Install pocknix modules
  #    into the rootfs and drop the generic ALARM kernel (we boot qcom-abl KERNEL).
  install_kernel "${ROOTFS_DIR}"

  # 5. device support (Phase 2): SM8550 firmware + pocknix-bsp (suspend hooks etc.).
  #    Session packages (Phase 3/4) get added here later.
  install_firmware "${ROOTFS_DIR}"
  install_local_packages "${ROOTFS_DIR}"

  chroot_umount "${ROOTFS_DIR}"; trap - EXIT

  # 6. assemble bootable image (Phase 6)
  warn "STUB: image assembly (Phase 6) not implemented yet"

  ok "build-image: base rootfs built at ${ROOTFS_DIR} (later phases stubbed)"
}

main "$@"
