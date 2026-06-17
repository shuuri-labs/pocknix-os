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
  log "rendering pacman.conf"
  sed -e "s|@HOLO_RELEASE@|${HOLO_RELEASE}|g" \
      -e "s|@HOLO_REPO_URL@|${HOLO_REPO_URL}|g" \
      -e "s|@LOCAL_REPO_DIR@|${LOCAL_REPO_DIR}|g" \
      "${CONFIG_DIR}/pacman.conf.in" > "${out}"
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

main() {
  # 1. base rootfs
  "${POCKNIX_ROOT}/scripts/bootstrap.sh"

  # 2. pacman config + repos inside the rootfs
  mkdir -p "${LOCAL_REPO_DIR}"
  render_pacman_conf "${ROOTFS_DIR}/etc/pacman.conf"

  trap 'chroot_umount "${ROOTFS_DIR}"' EXIT
  chroot_mount "${ROOTFS_DIR}"
  configure_keyring "${ROOTFS_DIR}"

  # 3. packages: base now; session lists become active in Phase 3/4
  install_packages "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/base.list"
  # install_packages "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/steam.list"     # Phase 3
  # install_packages "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/desktop.list"   # Phase 4

  # 4. kernel (Phase 1) -- builds linux-pocknix into the local repo + /flash/KERNEL
  if [ -x "${POCKNIX_ROOT}/scripts/build-kernel.sh" ]; then
    "${POCKNIX_ROOT}/scripts/build-kernel.sh"
  else
    warn "STUB: kernel build (Phase 1) not implemented yet — image will have no KERNEL"
  fi

  # 5. sessions + quirks (Phase 2/3/4/5) -- install pocknix-* local packages
  warn "STUB: pocknix-bsp / session units (Phase 2-5) not implemented yet"

  chroot_umount "${ROOTFS_DIR}"; trap - EXIT

  # 6. assemble bootable image (Phase 6)
  warn "STUB: image assembly (Phase 6) not implemented yet"

  ok "build-image: base rootfs built at ${ROOTFS_DIR} (later phases stubbed)"
}

main "$@"
