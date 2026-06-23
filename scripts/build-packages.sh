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
  # linux-pocknix is a THIN package: it doesn't compile the kernel (no makepkg/toolchain in the
  # chroot for that), it just packages `make kernel`'s output. Stage build/kernel/out into the
  # package build dir as ./staged so its package() can lay it out as /boot + /usr/lib/modules.
  if [ "${name}" = "linux-pocknix" ]; then
    local kout="${BUILD_DIR}/kernel/out"
    if [ ! -f "${kout}/Image" ] || [ ! -f "${kout}/kernelrelease" ]; then
      warn "linux-pocknix: no kernel build at ${kout} — run 'make kernel' first; skipping"
      return 1
    fi
    cp -a "${kout}" "${BROOT}/build/${name}/staged"
  fi
  # Persistent source cache: SRCDEST lives OUTSIDE the per-package build dir (which is wiped
  # every run), so makepkg downloads each source ONCE and reuses it. File sources (e.g.
  # fex-emu's pinned x86 sysroot .pkg.tar.zst, ~70 MB) are kept by name; the git source becomes
  # a cached clone that only `git fetch`es deltas instead of re-cloning 100k+ objects each build.
  mkdir -p "${BROOT}/build/srccache"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  chroot "${BROOT}" chown builder:builder /build/srccache
  # makepkg refuses to run as root; build as the 'builder' user.
  # -s syncs makedepends (gamescope needs many); pocknix-bsp has none so it's a no-op.
  if ! chroot "${BROOT}" runuser -u builder -- \
      bash -lc "cd /build/${name} && SRCDEST=/build/srccache makepkg -s -f --noconfirm --nocheck --skippgpcheck"; then
    warn "makepkg failed for ${name} — keeping any previous build in ${LOCALREPO##*/}"
    return 1
  fi
  # Confirm the build produced a package, matched by pkgname — NOT every *.pkg.tar.* in the build
  # dir, which would also sweep up any .pkg.tar.* a PKGBUILD downloads as *sources* (e.g. fex-emu's
  # pinned x86 sysroot pkgs). A non-matching glob leaves the literal pattern, so `-e` is false.
  local built_pkgs=("${BROOT}/build/${name}/${name}"-*.pkg.tar.*)
  if [ ! -e "${built_pkgs[0]}" ]; then
    warn "no .pkg.tar.* produced for ${name} — keeping any previous build"
    return 1
  fi
  # ONLY NOW touch the repo. Removing the previous version(s) and publishing the new one happens
  # AFTER a confirmed successful build, so a failed/transient rebuild never wipes a known-good
  # package (build-to-temp-then-swap). The rm also clears stale dupes that would otherwise break
  # `pacman -U pkg-*.tar` with "duplicate target". (rm before cp: the new file's own epoch'd name
  # matches the *:* pattern, so cp-then-rm would delete what we just copied.)
  rm -f "${LOCALREPO}/${name}"-[0-9]*.pkg.tar.* "${LOCALREPO}/${name}"-*:*.pkg.tar.* 2>/dev/null || true
  cp "${built_pkgs[@]}" "${LOCALREPO}/"
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

  # Build a package, publishing it to [pocknix] on success so later packages see it.
  try_build() {
    chroot "${BROOT}" pacman -Sy --noconfirm >/dev/null 2>&1 || true   # refresh dbs incl. [pocknix]
    if build_one "$1"; then
      built=$((built+1))
      chroot "${BROOT}" bash -lc "cd /localrepo && repo-add -q ${REPO_DB} *.pkg.tar.*"
      return 0
    fi
    return 1
  }

  local built=0 name
  local -a failed=()
  for pkgdir in "${PACKAGES_DIR}"/*/; do
    [ -f "${pkgdir}/PKGBUILD" ] || continue
    name="$(basename "${pkgdir}")"
    if [ "${#want[@]}" -gt 0 ]; then
      case " ${want[*]} " in *" ${name} "*) ;; *) continue ;; esac
    fi
    try_build "${pkgdir}" || failed+=("${pkgdir}")
  done

  # Dependency order != alphabetical: a package can depend on a sibling the glob builds LATER
  # (e.g. pocknix-steam depends on pocknix-steamos-shim, which sorts after it), so its first
  # `makepkg -s` aborts with "target not found". Retry failures — once a dep lands in [pocknix]
  # the dependent builds. Loop until a full pass makes no progress (then they're real failures).
  while [ "${#failed[@]}" -gt 0 ]; do
    local -a retry=("${failed[@]}"); failed=(); local progress=0
    for pkgdir in "${retry[@]}"; do
      if try_build "${pkgdir}"; then progress=1; else failed+=("${pkgdir}"); fi
    done
    [ "${progress}" -eq 1 ] || break
  done
  [ "${#failed[@]}" -eq 0 ] || warn "still failing after dep-order retries: ${failed[*]##*/}"

  umount "${BROOT}/localrepo"
  chroot_umount "${BROOT}"
  trap - EXIT

  [ "${built}" -gt 0 ] || die "no packages built"
  ok "local repo ready -> ${LOCALREPO}"
  ls -1 "${LOCALREPO}"/*.pkg.tar.* 2>/dev/null | sed 's#.*/#  #'
}

main "$@"
