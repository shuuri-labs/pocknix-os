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
  local pkgdir="$1" force="${2:-0}" name; name="$(basename "${pkgdir}")"
  rm -rf "${BROOT}/build/${name}"
  mkdir -p "${BROOT}/build"
  cp -r "${pkgdir}" "${BROOT}/build/${name}"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  # Incremental skip: if every artifact this PKGBUILD would produce (per `makepkg
  # --packagelist`: name-[epoch:]ver-rel-arch, split siblings included) is already in the
  # localrepo AND newer than every file in the package dir, there is nothing to do — so a
  # re-run of `make build` doesn't recompile mesa/gamescope/the world. Editing any file in
  # the package dir (patch, script, PKGBUILD) triggers a rebuild without needing a pkgrel
  # bump. Force paths: `make packages PKG=<name>` always rebuilds the named packages;
  # POCKNIX_FORCE_REBUILD=1 rebuilds everything. The kernel package also rebuilds whenever
  # `make kernel` produced a newer Image than the packaged one.
  if [ "${force}" -eq 0 ]; then
    local uptodate=1 nlist=0 p f
    while IFS= read -r p; do
      nlist=$((nlist+1))
      f="${LOCALREPO}/$(basename "${p}")"
      if [ ! -f "${f}" ] || [ -n "$(find "${pkgdir}" -newer "${f}" -print -quit)" ]; then
        uptodate=0; break
      fi
      case "${name}" in linux-pocknix-*)
        if [ -f "${BUILD_DIR}/kernel/out/Image" ] && [ "${BUILD_DIR}/kernel/out/Image" -nt "${f}" ]; then
          uptodate=0; break
        fi
      ;; esac
    done < <(chroot "${BROOT}" runuser -u builder -- \
               bash -lc "cd /build/${name} && LC_ALL=C makepkg --packagelist" 2>/dev/null)
    if [ "${nlist}" -gt 0 ] && [ "${uptodate}" -eq 1 ]; then
      log "skip: ${name} (already in localrepo, sources unchanged — force with PKG=${name})"
      return 0
    fi
  fi
  log "makepkg: ${name}"
  # Refresh the chroot's sync DBs (incl. [pocknix], so makepkg -s sees siblings built
  # earlier this run) — only here, when actually building; skipped packages must not
  # each pay a network DB refresh.
  chroot "${BROOT}" pacman -Sy --noconfirm >/dev/null 2>&1 || true
  # linux-pocknix-<soc> is a THIN package: it doesn't compile the kernel (no makepkg/toolchain
  # in the chroot for that), it just packages `make kernel`'s output. Stage build/kernel/out
  # into the package build dir as ./staged so its package() can lay it out as /boot +
  # /usr/lib/modules. NB: only the CURRENT device's SoC kernel can be staged (make kernel
  # builds one SoC at a time); other SoCs' kernel packages skip with a warning.
  case "${name}" in linux-pocknix-*)
    if [ "${name}" != "${KERNEL_PKG}" ]; then
      warn "${name}: not the current SoC's kernel (${KERNEL_PKG}) — skipping (build with the right DEVICE)"
      return 1
    fi
    local kout="${BUILD_DIR}/kernel/out"
    if [ ! -f "${kout}/Image" ] || [ ! -f "${kout}/kernelrelease" ]; then
      warn "${name}: no kernel build at ${kout} — run 'make kernel' first; skipping"
      return 1
    fi
    cp -a "${kout}" "${BROOT}/build/${name}/staged"
  ;; esac
  # Drift guard: a device BSP's committed kernel-cmdline must byte-match its own device
  # profile's KERNEL_CMDLINE (the boot image is built from the profile; the BSP file feeds
  # the on-device /flash/KERNEL rebuild — they must agree). The device is derived from the
  # package's path (devices/<dev>/packages/<pkg>); the subshell unsets the current profile's
  # values so the checked device's own defaults apply.
  if [ -f "${pkgdir}/kernel-cmdline" ]; then
    local devdir want_cmdline
    devdir="$(dirname "$(dirname "${pkgdir%/}")")"
    if [ -f "${devdir}/profile.conf" ]; then
      want_cmdline="$(unset SOC ROOT_LABEL KERNEL_CMDLINE KERNEL_CMDLINE_ROOT KERNEL_CMDLINE_EXTRA
                      . "${devdir}/profile.conf"; printf '%s' "${KERNEL_CMDLINE}")"
      if [ "$(cat "${pkgdir}/kernel-cmdline")" != "${want_cmdline}" ]; then
        die "${name}: kernel-cmdline drifted from ${devdir}/profile.conf KERNEL_CMDLINE —
  profile: ${want_cmdline}
  package: $(cat "${pkgdir}/kernel-cmdline")
Update one to match the other."
      fi
    fi
  fi
  # Persistent source cache: SRCDEST lives OUTSIDE the per-package build dir (which is wiped
  # every run), so makepkg downloads each source ONCE and reuses it. File sources (e.g.
  # fex-emu's pinned x86 sysroot .pkg.tar.zst, ~70 MB) are kept by name; the git source becomes
  # a cached clone that only `git fetch`es deltas instead of re-cloning 100k+ objects each build.
  mkdir -p "${BROOT}/build/srccache"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  chroot "${BROOT}" chown builder:builder /build/srccache
  # makepkg refuses to run as root; build as the 'builder' user.
  # -s syncs makedepends (gamescope needs many). Device packages (devices/*/packages/*:
  # BSPs + metapackages) are pure file-drop/meta packages built with --nodeps instead —
  # with -s makepkg would install their RUNTIME dependency closure into the build chroot
  # (the kernel package, the Steam stack, the ~1.1 GB fex-rootfs) just to lay out a few
  # files, which is slow and was the failure mode for pocknix-device-rp6. Their depends=
  # still ships in the .pkg metadata; -d only skips build-time resolution.
  local mkflags="-s"
  case "${pkgdir}" in */devices/*/packages/*) mkflags="-d" ;; esac
  if ! chroot "${BROOT}" runuser -u builder -- \
      bash -lc "cd /build/${name} && LC_ALL=C SRCDEST=/build/srccache makepkg ${mkflags} -f --noconfirm --nocheck --skippgpcheck"; then
    warn "makepkg failed for ${name} — keeping any previous build in ${LOCALREPO##*/}"
    return 1
  fi
  # Collect what makepkg ACTUALLY produced via `makepkg --packagelist`: a split PKGBUILD
  # (packages/mesa -> mesa + vulkan-freedreno) emits sibling packages a "${name}-*" glob
  # misses (bitten by mesa: only the mesa half reached localrepo), while a bare *.pkg.tar.*
  # sweep would grab .pkg.tar.* files that are makepkg *sources* symlinked into the build
  # dir (e.g. fex-emu's pinned x86 sysroot pkgs). --packagelist names exactly the built
  # artifacts, epoch and all.
  local built_pkgs=() p
  while IFS= read -r p; do
    p="${BROOT}/build/${name}/$(basename "${p}")"
    [ -e "${p}" ] && built_pkgs+=("${p}")
  done < <(chroot "${BROOT}" runuser -u builder -- \
             bash -lc "cd /build/${name} && LC_ALL=C makepkg --packagelist" 2>/dev/null)
  if [ "${#built_pkgs[@]}" -eq 0 ]; then
    warn "no .pkg.tar.* produced for ${name} — keeping any previous build"
    return 1
  fi
  # ONLY NOW touch the repo. Removing the previous version(s) and publishing the new one happens
  # AFTER a confirmed successful build, so a failed/transient rebuild never wipes a known-good
  # package (build-to-temp-then-swap). The rm also clears stale dupes that would otherwise break
  # `pacman -U pkg-*.tar` with "duplicate target". (rm before cp: the new file's own epoch'd name
  # matches the *:* pattern, so cp-then-rm would delete what we just copied.) Clear per PRODUCED
  # package name — split siblings each have their own previous versions.
  local base
  for p in "${built_pkgs[@]}"; do
    base="$(basename "${p}")"
    base="${base%-*}"; base="${base%-*}"; base="${base%-*}"  # strip -<ver>-<rel>-<arch>.pkg.tar.*
    rm -f "${LOCALREPO}/${base}"-[0-9]*.pkg.tar.* "${LOCALREPO}/${base}"-*:*.pkg.tar.* 2>/dev/null || true
  done
  cp "${built_pkgs[@]}" "${LOCALREPO}/"
  # Register exactly the artifacts just built (NOT *.pkg.tar.* — re-adding the whole repo
  # for every package spammed 'entry already existed' x N^2). LC_ALL=C: the build chroot
  # has no generated locales, and bsdtar warns on every tar op otherwise.
  local addlist=""
  for p in "${built_pkgs[@]}"; do addlist+=" $(basename "${p}")"; done
  chroot "${BROOT}" bash -lc "cd /localrepo && LC_ALL=C repo-add -q ${REPO_DB}${addlist}"
}

main() {
  # Optional args = package names to build (subset, always rebuilt); no args = build
  # everything, skipping packages already up-to-date in the localrepo (see build_one).
  # e.g. `make packages PKG="inputplumber pocknix-bsp-rp6"` to force just those two.
  local want=("$@")
  mkdir -p "${LOCALREPO}"
  setup_chroot

  chroot_mount "${BROOT}"
  # Keep the local repo bind-mounted throughout so makepkg -s can resolve inter-package
  # local deps (pocknix-steam -> gamescope, gtk2) from the [pocknix] repo as we go.
  mkdir -p "${BROOT}/localrepo"
  mount --bind "${LOCALREPO}" "${BROOT}/localrepo"
  # Initialize the [pocknix] db so the repo is valid even on the first/partial run
  # (one full re-add; per-package registration during the run adds only new artifacts).
  if ls "${LOCALREPO}"/*.pkg.tar.* >/dev/null 2>&1; then
    chroot "${BROOT}" bash -lc "cd /localrepo && LC_ALL=C repo-add -q ${REPO_DB} \$(ls *.pkg.tar.* | grep -v '\.sig\$')" >/dev/null 2>&1
  else
    chroot "${BROOT}" bash -lc "cd /localrepo && tar -czf ${REPO_DB} -T /dev/null && ln -sf ${REPO_DB} pocknix.db"
  fi

  # Build a package (build_one registers its artifacts in [pocknix] so later packages
  # see them; the pacman -Sy refresh happens inside build_one, only for real builds).
  try_build() {
    if build_one "$1" "${2:-0}"; then
      built=$((built+1))
      return 0
    fi
    return 1
  }

  local built=0 name force
  local -a failed=()
  # Shared packages (packages/*/) + every device's packages (devices/*/packages/*/ — the
  # arch=any BSPs/metapackages build in seconds), so the repo always carries all devices.
  # Up-to-date packages are skipped (see build_one); PKG= names and
  # POCKNIX_FORCE_REBUILD=1 force.
  for pkgdir in "${PACKAGES_DIR}"/*/ "${POCKNIX_ROOT}"/devices/*/packages/*/; do
    [ -f "${pkgdir}/PKGBUILD" ] || continue
    name="$(basename "${pkgdir}")"
    force=0
    [ "${POCKNIX_FORCE_REBUILD:-0}" = "1" ] && force=1
    if [ "${#want[@]}" -gt 0 ]; then
      case " ${want[*]} " in *" ${name} "*) force=1 ;; *) continue ;; esac
    fi
    try_build "${pkgdir}" "${force}" || failed+=("${pkgdir}")
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
