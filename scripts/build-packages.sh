#!/usr/bin/env bash
# build-packages.sh — build the local pocknix-* packages with makepkg.
#
# The host (Fedora) has no makepkg, so we build inside a dedicated Arch Linux ARM
# build chroot (base-devel). Results + a pacman repo DB land in build/localrepo,
# which build-image.sh consumes via the [pocknix] repo.
#
# Standalone: `sudo make packages` (test this in isolation first).
# Needs a Linux host + root (chroot/mount); native makepkg on aarch64, qemu on x86.

source "$(dirname "$0")/lib.sh"
need_linux
need_root build-packages
for t in curl tar rsync; do need_tool "$t"; done

BROOT="${BUILD_DIR}/pkgbuild-root"     # the makepkg build chroot (reused across runs)
LOCALREPO="${BUILD_DIR}/localrepo"
TARBALL="${CACHE_DIR}/${ALARM_TARBALL}"
REPO_DB="pocknix.db.tar.gz"

cleanup() { chroot_umount "${BROOT}" 2>/dev/null || true
            mountpoint -q "${BROOT}/localrepo" && umount "${BROOT}/localrepo" 2>/dev/null || true; }
trap cleanup EXIT

setup_chroot() {
  if [ -x "${BROOT}/usr/bin/makepkg" ]; then
    log "reusing build chroot: ${BROOT}"
    return 0
  fi
  mkdir -p "${CACHE_DIR}"
  [ -f "${TARBALL}" ] || { log "downloading ALARM tarball for build chroot"; \
    curl -fL --retry 3 -o "${TARBALL}" "${ALARM_MIRROR}/${ALARM_TARBALL}"; }
  log "creating build chroot -> ${BROOT} (one-time; ~1.5 GB with base-devel)"
  rm -rf "${BROOT}"; mkdir -p "${BROOT}"
  if have bsdtar; then bsdtar -xpf "${TARBALL}" -C "${BROOT}"
  else tar -xpf "${TARBALL}" -C "${BROOT}" --numeric-owner; fi
  maybe_install_qemu "${BROOT}"
  cp -f "${CONFIG_DIR}/pacman.conf.in" "${BROOT}/etc/pacman.conf"   # ALARM-only base
  chroot_mount "${BROOT}"
  chroot "${BROOT}" pacman-key --init
  chroot "${BROOT}" pacman-key --populate archlinuxarm
  chroot "${BROOT}" pacman -Syu --noconfirm --needed base-devel sudo
  chroot "${BROOT}" id builder >/dev/null 2>&1 || chroot "${BROOT}" useradd -m builder
  # makepkg -s installs makedepends via `sudo pacman` as the builder user.
  printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > "${BROOT}/etc/sudoers.d/builder"
  chmod 0440 "${BROOT}/etc/sudoers.d/builder"
  chroot_umount "${BROOT}"
}

build_one() {
  local pkgdir="$1" name; name="$(basename "${pkgdir}")"
  log "makepkg: ${name}"
  rm -rf "${BROOT}/build/${name}"
  mkdir -p "${BROOT}/build"
  cp -r "${pkgdir}" "${BROOT}/build/${name}"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  # makepkg refuses to run as root; build as the 'builder' user.
  # -s syncs makedepends (gamescope needs many); pocknix-bsp has none so it's a no-op.
  chroot "${BROOT}" runuser -u builder -- \
    bash -lc "cd /build/${name} && makepkg -s -f --noconfirm --nocheck --skippgpcheck"
  cp "${BROOT}/build/${name}"/*.pkg.tar.* "${LOCALREPO}/" 2>/dev/null \
    || { warn "no .pkg.tar.* produced for ${name}"; return 1; }
}

main() {
  mkdir -p "${LOCALREPO}"
  setup_chroot

  chroot_mount "${BROOT}"
  local built=0
  for pkgdir in "${PACKAGES_DIR}"/*/; do
    [ -f "${pkgdir}/PKGBUILD" ] || continue
    build_one "${pkgdir}" && built=$((built+1)) || true
  done
  chroot_umount "${BROOT}"

  [ "${built}" -gt 0 ] || die "no packages built"

  # index the repo (repo-add lives in the chroot's pacman); bind-mount localrepo in
  log "indexing local repo (${built} package(s))"
  chroot_mount "${BROOT}"
  mkdir -p "${BROOT}/localrepo"
  mount --bind "${LOCALREPO}" "${BROOT}/localrepo"
  chroot "${BROOT}" bash -lc "cd /localrepo && rm -f ${REPO_DB} pocknix.db && repo-add -q ${REPO_DB} *.pkg.tar.*"
  umount "${BROOT}/localrepo"
  chroot_umount "${BROOT}"
  trap - EXIT

  ok "local repo ready -> ${LOCALREPO}"
  ls -1 "${LOCALREPO}"/*.pkg.tar.* 2>/dev/null | sed 's#.*/#  #'
}

main "$@"
