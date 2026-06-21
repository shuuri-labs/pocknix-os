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
  else
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
    chroot_umount "${BROOT}"
  fi

  # Idempotent: ensure the 'builder' user, sudo, and passwordless sudoers exist — this
  # also repairs chroots created by older versions of this script (which had no sudo),
  # so `makepkg -s` (deps installed via `sudo pacman` as builder) works without a rebuild.
  chroot "${BROOT}" id builder >/dev/null 2>&1 || chroot "${BROOT}" useradd -m builder
  if [ ! -x "${BROOT}/usr/bin/sudo" ]; then
    chroot_mount "${BROOT}"
    chroot "${BROOT}" pacman -Sy --noconfirm --needed sudo
    chroot_umount "${BROOT}"
  fi
  printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > "${BROOT}/etc/sudoers.d/builder"
  chmod 0440 "${BROOT}/etc/sudoers.d/builder"

  # Local [pocknix] repo so a package can depend on another locally-built one
  # (e.g. pocknix-steam -> gamescope, gtk2). Points at the bind-mounted /localrepo.
  if ! grep -q '^\[pocknix\]' "${BROOT}/etc/pacman.conf"; then
    printf '\n[pocknix]\nSigLevel = Optional TrustAll\nServer = file:///localrepo\n' \
      >> "${BROOT}/etc/pacman.conf"
  fi
}

build_one() {
  local pkgdir="$1" name; name="$(basename "${pkgdir}")"
  log "makepkg: ${name}"
  rm -rf "${BROOT}/build/${name}"
  mkdir -p "${BROOT}/build"
  cp -r "${pkgdir}" "${BROOT}/build/${name}"
  # Persistent source cache: SRCDEST lives OUTSIDE the per-package build dir (which is wiped
  # every run), so makepkg downloads each source ONCE and reuses it. File sources (e.g.
  # fex-emu's pinned x86 sysroot .pkg.tar.zst, ~70 MB) are kept by name; the git source becomes
  # a cached clone that only `git fetch`es deltas instead of re-cloning 100k+ objects each build.
  mkdir -p "${BROOT}/build/srccache"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  chroot "${BROOT}" chown builder:builder /build/srccache
  # makepkg refuses to run as root; build as the 'builder' user.
  # -s syncs makedepends (gamescope needs many); pocknix-bsp has none so it's a no-op.
  chroot "${BROOT}" runuser -u builder -- \
    bash -lc "cd /build/${name} && SRCDEST=/build/srccache makepkg -s -f --noconfirm --nocheck --skippgpcheck"
  # keep only the freshly built version in the repo (avoids stale dupes accumulating,
  # which otherwise break `pacman -U pkg-*.tar` with "duplicate target").
  rm -f "${LOCALREPO}/${name}"-[0-9]*.pkg.tar.* "${LOCALREPO}/${name}"-*:*.pkg.tar.* 2>/dev/null || true
  # Copy ONLY the built package(s), matched by pkgname — NOT every *.pkg.tar.* in the
  # build dir, which would also sweep up any .pkg.tar.* files a PKGBUILD downloads as
  # *sources* (e.g. fex-emu's pinned x86 sysroot pkgs). That both polluted the repo
  # and masked build failures as success.
  cp "${BROOT}/build/${name}/${name}"-*.pkg.tar.* "${LOCALREPO}/" 2>/dev/null \
    || { warn "no .pkg.tar.* produced for ${name}"; return 1; }
}

main() {
  # Optional args = package names to build (subset); no args = build all in packages/.
  # e.g. `make packages PKG="inputplumber pocknix-bsp"` to skip the slow gamescope rebuild.
  local want=("$@")
  mkdir -p "${LOCALREPO}"
  setup_chroot

  chroot_mount "${BROOT}"
  # Keep the local repo bind-mounted throughout so makepkg -s can resolve inter-package
  # local deps (pocknix-steam -> gamescope, gtk2) from the [pocknix] repo as we go.
  mkdir -p "${BROOT}/localrepo"
  mount --bind "${LOCALREPO}" "${BROOT}/localrepo"
  # Initialize the [pocknix] db so the repo is valid even on the first/partial run.
  if ls "${LOCALREPO}"/*.pkg.tar.* >/dev/null 2>&1; then
    chroot "${BROOT}" bash -lc "cd /localrepo && repo-add -q ${REPO_DB} *.pkg.tar.*"
  else
    chroot "${BROOT}" bash -lc "cd /localrepo && tar -czf ${REPO_DB} -T /dev/null && ln -sf ${REPO_DB} pocknix.db"
  fi

  local built=0 name
  for pkgdir in "${PACKAGES_DIR}"/*/; do
    [ -f "${pkgdir}/PKGBUILD" ] || continue
    name="$(basename "${pkgdir}")"
    if [ "${#want[@]}" -gt 0 ]; then
      case " ${want[*]} " in *" ${name} "*) ;; *) continue ;; esac
    fi
    # refresh dbs (incl. [pocknix]) so deps built earlier this run are visible
    chroot "${BROOT}" pacman -Sy --noconfirm >/dev/null 2>&1 || true
    if build_one "${pkgdir}"; then
      built=$((built+1))
      # publish to [pocknix] immediately so later packages can depend on it
      chroot "${BROOT}" bash -lc "cd /localrepo && repo-add -q ${REPO_DB} *.pkg.tar.*"
    fi
  done

  umount "${BROOT}/localrepo"
  chroot_umount "${BROOT}"
  trap - EXIT

  [ "${built}" -gt 0 ] || die "no packages built"
  ok "local repo ready -> ${LOCALREPO}"
  ls -1 "${LOCALREPO}"/*.pkg.tar.* 2>/dev/null | sed 's#.*/#  #'
}

main "$@"
