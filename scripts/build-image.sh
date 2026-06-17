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
append_local_repo() {
  local out="$1"
  grep -q '^\[pocknix\]' "${out}" && return 0
  log "adding local pocknix repo"
  cat >> "${out}" <<EOF

[pocknix]
SigLevel = Optional TrustAll
Server = file://${LOCAL_REPO_DIR}
EOF
}

read_pkglist() {
  # strip comments/blank lines from a package list file
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"
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
  chroot "${root}" pacman -Syu --noconfirm --needed "${pkgs[@]}"
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

  # 2. pacman config + repos inside the rootfs
  mkdir -p "${LOCAL_REPO_DIR}"
  render_pacman_conf "${ROOTFS_DIR}/etc/pacman.conf"

  trap 'chroot_umount "${ROOTFS_DIR}"' EXIT
  chroot_mount "${ROOTFS_DIR}"
  configure_keyring "${ROOTFS_DIR}"

  # 3. packages: base now (ALARM only); session lists become active in Phase 3/4,
  #    each adding its repo to pacman.conf first.
  install_packages "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/base.list"
  # append_holo_repo  "${ROOTFS_DIR}/etc/pacman.conf"                          # Phase 3
  # install_packages  "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/steam.list"     # Phase 3
  # install_packages  "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/desktop.list"   # Phase 4
  # append_local_repo "${ROOTFS_DIR}/etc/pacman.conf"                          # Phase 2/5 (pocknix-* pkgs)

  # 4. kernel (Phase 1): use artifacts from `make kernel`. Install pocknix modules
  #    into the rootfs and drop the generic ALARM kernel (we boot qcom-abl KERNEL).
  install_kernel "${ROOTFS_DIR}"

  # 5. sessions + quirks (Phase 2/3/4/5) -- install pocknix-* local packages
  warn "STUB: pocknix-bsp / session units (Phase 2-5) not implemented yet"

  chroot_umount "${ROOTFS_DIR}"; trap - EXIT

  # 6. assemble bootable image (Phase 6)
  warn "STUB: image assembly (Phase 6) not implemented yet"

  ok "build-image: base rootfs built at ${ROOTFS_DIR} (later phases stubbed)"
}

main "$@"
