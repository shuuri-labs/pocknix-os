#!/usr/bin/env bash
# build-packages.sh — build the local pocknix-* packages with makepkg.
#
# The host (Fedora) has no makepkg, so we build inside a dedicated Arch Linux ARM
# build chroot (base-devel). Results + pacman repo DBs land in ${LOCALREPO_DIR} (per-SoC)
# and ${LOCALREPO_SHARED_DIR}, which build-image.sh consumes as [pocknix] + [pocknix-shared].
#
# Standalone: `sudo make packages`.
# Needs a Linux host + root (chroot/mount); native makepkg on aarch64, qemu on x86.

source "$(dirname "$0")/lib.sh"
need_linux
need_root build-packages
for t in curl tar rsync; do need_tool "$t"; done

# Two repo trees: packages/soc/* and packages/gpu/* are PER-SoC (tuned packages share
# pkgnames across SoCs with different binaries; each SoC gets its own repo, and the
# chroot is split too so one SoC's tuned makedepends can never leak into
# another SoC's builds). packages/shared/* are byte-identical across SoCs:
# built ONCE into the shared localrepo ([pocknix-shared]) — whichever SoC runs
# first builds them, the other run's incremental skip sees them up to date.
BROOT="${BUILD_DIR}/pkgbuild-root-${SOC}"   # the makepkg build chroot (reused across runs)
LOCALREPO="${LOCALREPO_DIR}"                # build/localrepo/${SOC} (set in lib.sh)
LOCALREPO_SHARED="${LOCALREPO_SHARED_DIR}"  # build/localrepo/shared (set in lib.sh)
# Outside the chroot so it outlives a chroot rebuild; both SoC chroots share it.
CCACHE_HOST_DIR="${BUILD_DIR}/ccache"
CCACHE_ON=0                                 # set by setup_chroot once the binary is there
TARBALL="${CACHE_DIR}/${ALARM_TARBALL}"
REPO_DB="pocknix.db.tar.gz"
SHARED_REPO_DB="pocknix-shared.db.tar.gz"

cleanup() { chroot_umount "${BROOT}" 2>/dev/null || true
            mountpoint -q "${BROOT}/localrepo" && umount "${BROOT}/localrepo" 2>/dev/null || true
            mountpoint -q "${BROOT}/localrepo-shared" && umount "${BROOT}/localrepo-shared" 2>/dev/null || true
            mountpoint -q "${BROOT}/ccache" && umount "${BROOT}/ccache" 2>/dev/null || true; }
trap cleanup EXIT

# rm -rf follows bind mounts (even --one-file-system: same device), so a localrepo mount left
# by an interrupted build would take the real localrepo with it. Never rm with one in place.
wipe_chroot() {
  cleanup
  ! findmnt -rno TARGET | grep -q "^${BROOT}/" || die "still mounted under ${BROOT}, not wiping it"
  rm -rf "${BROOT}"
}

# Which repo a package dir builds into: shared packages target the shared
# localrepo, everything else (packages/soc, packages/gpu + device packages) the per-SoC one.
pkg_repo_dir()   { case "$1" in */packages/shared/*) printf '%s' "${LOCALREPO_SHARED}" ;; *) printf '%s' "${LOCALREPO}" ;; esac; }
pkg_repo_db()    { case "$1" in */packages/shared/*) printf '%s' "${SHARED_REPO_DB}" ;; *) printf '%s' "${REPO_DB}" ;; esac; }
pkg_repo_mount() { case "$1" in */packages/shared/*) printf '/localrepo-shared' ;; *) printf '/localrepo' ;; esac; }

setup_chroot() {
  # Base fingerprint: the chroot is built FROM a base (pinned snapshot id, or
  # "live" ALARM) and must be recreated when the pin changes — an old-base chroot
  # stamps binaries with sonames the new base no longer has.
  local want_base="${POCKNIX_BASE_SNAPSHOT:-live}" have_base
  have_base="$(cat "${BROOT}/.base-snapshot" 2>/dev/null || true)"
  if [ -x "${BROOT}/usr/bin/makepkg" ]; then
    # adopt pre-stamp chroots as live-based (the -Syu below converges them)
    if [ -z "${have_base}" ] && [ -z "${POCKNIX_BASE_SNAPSHOT}" ]; then
      printf 'live\n' > "${BROOT}/.base-snapshot"; have_base=live
    fi
    if [ "${have_base}" != "${want_base}" ]; then
      log "build chroot base is '${have_base:-unknown}', want '${want_base}' — recreating"
      wipe_chroot
    fi
  fi

  if [ -x "${BROOT}/usr/bin/makepkg" ]; then
    log "reusing build chroot: ${BROOT}"
    # Re-render drops the [pocknix] stanza; it is re-appended below, AFTER the
    # -Syu — its file:///localrepo isn't bind-mounted until main(), and pacman
    # dies on a configured repo with no DB.
    render_base_pacman_conf "${BROOT}/etc/pacman.conf"
    # Converge the reused chroot to the configured base. Without this the chroot
    # is frozen at its creation date and LAGS devices (a user's -Syu gets a new
    # soname our binaries were never linked against). Pinned base: no-op.
    chroot_mount "${BROOT}"
    # A PINNED base is frozen, so a chroot already stamped with that pin cannot be stale
    # and a failed -Syu just means offline. On live/unpinned bases the drift is real, and
    # building against a chroot that missed it is exactly what this guard exists to stop.
    if ! chroot "${BROOT}" pacman -Syu --noconfirm; then
      if [ -n "${POCKNIX_BASE_SNAPSHOT}" ] && [ "${have_base}" = "${want_base}" ]; then
        warn "chroot -Syu failed, but the base is pinned to ${want_base} and the chroot already matches it — continuing (frozen base cannot have moved)"
      else
        die "chroot base upgrade failed — refusing to build against a stale base (network down? re-run when reachable)"
      fi
    fi
    chroot_umount "${BROOT}"
  else
    fetch_alarm_tarball
    log "creating build chroot -> ${BROOT} (one-time; ~1.5 GB with base-devel)"
    wipe_chroot; mkdir -p "${BROOT}"
    if have bsdtar; then bsdtar -xpf "${TARBALL}" -C "${BROOT}"
    else tar -xpf "${TARBALL}" -C "${BROOT}" --numeric-owner; fi
    maybe_install_qemu "${BROOT}"
    render_base_pacman_conf "${BROOT}/etc/pacman.conf"
    chroot_mount "${BROOT}"
    chroot "${BROOT}" pacman-key --init
    chroot "${BROOT}" pacman-key --populate archlinuxarm
    chroot "${BROOT}" pacman -Syu --noconfirm --needed base-devel sudo
    chroot_umount "${BROOT}"
    printf '%s\n' "${want_base}" > "${BROOT}/.base-snapshot"
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

  # ccache installs from the base like the rest of the chroot; a base without it builds uncached
  # rather than failing. makepkg aborts when BUILDENV asks for ccache it cannot find, so the
  # drop-in only exists next to the binary.
  CCACHE_ON=0
  rm -f "${BROOT}/etc/makepkg.conf.d/pocknix-ccache.conf"
  if [ "${POCKNIX_CCACHE}" = "1" ]; then
    if [ ! -x "${BROOT}/usr/bin/ccache" ]; then
      chroot_mount "${BROOT}"
      chroot "${BROOT}" pacman -S --noconfirm --needed ccache >/dev/null 2>&1 ||
        warn "could not install ccache into the chroot: building without a compiler cache"
      chroot_umount "${BROOT}"
    fi
    if [ -x "${BROOT}/usr/bin/ccache" ]; then
      mkdir -p "${BROOT}/etc/makepkg.conf.d"
      printf 'BUILDENV+=(ccache)\n' > "${BROOT}/etc/makepkg.conf.d/pocknix-ccache.conf"
      CCACHE_ON=1
    fi
  fi

  # Local [pocknix] repo so a package can depend on another locally-built one. Points at
  # the bind-mounted /localrepo. SigLevel Never, same reason as build-image.sh's
  # append_local_repo: a signed localrepo db makes Optional TrustAll die on the unknown
  # key when makepkg -s installs a locally-built dep. The sed branch repairs REUSED
  # chroots that were created with the old stanza.
  if ! grep -q '^\[pocknix\]' "${BROOT}/etc/pacman.conf"; then
    printf '\n[pocknix]\nSigLevel = Never\nServer = file:///localrepo\n' \
      >> "${BROOT}/etc/pacman.conf"
  else
    sed -i '/^\[pocknix\]/,/^\[/{s/^SigLevel = Optional TrustAll$/SigLevel = Never/;}' \
      "${BROOT}/etc/pacman.conf"
  fi
  # Same for [pocknix-shared]: makepkg -s must resolve shared siblings too
  # (e.g. pocknix-emu-dolphin -> pocknix-emulation-common).
  if ! grep -q '^\[pocknix-shared\]' "${BROOT}/etc/pacman.conf"; then
    printf '\n[pocknix-shared]\nSigLevel = Never\nServer = file:///localrepo-shared\n' \
      >> "${BROOT}/etc/pacman.conf"
  fi
}

# Files outside a package's dir that it is also built from (build_one stages what they render
# into ./staged), so editing one rebuilds it like an edit to its own dir. pocknix.conf holds the
# SD labels and sm8250's root= PARTUUID; kernel.conf the kernel package's version and release.
pkg_extra_srcs() {  # $1 = package name
  case "$1" in
    "${DEVICE_BSP_PKG}") echo "${DEVICE_DIR}/profile.conf ${CONFIG_DIR}/pocknix.conf ${POCKNIX_ROOT}/scripts/render-bsp.sh" ;;
    "pocknix-bootloader-${SOC}") echo "${DEVICE_DIR}/profile.conf ${CONFIG_DIR}/pocknix.conf" ;;
    "${KERNEL_PKG}") echo "${KERNEL_DIR}/kernel.conf" ;;
  esac
}

# The name a package dir builds as, which PKG= selects and the skip and staging key on. The
# kernel recipe is one dir for every SoC, so it takes the current SoC's package name.
pkg_name() {  # $1 = package dir
  case "${1%/}" in
    */packages/soc/linux-pocknix) printf '%s' "${KERNEL_PKG}" ;;
    *) basename "$1" ;;
  esac
}

# makepkg's environment for a package dir. Every makepkg call needs it, --packagelist included:
# the kernel recipe's name and version come from it. Shared packages get NO SoC/tuning env: they
# must be byte-stable whichever SoC's run builds them. POCKNIX_BASE_*: pocknix-lock-migrate stamps
# the target snapshot URL into its script, so snapshot bumps re-target the migrator on rebuild.
pkg_env() {  # $1 = package dir
  printf ' %s=%q' POCKNIX_BASE_URL "${POCKNIX_BASE_URL}" POCKNIX_BASE_SNAPSHOT "${POCKNIX_BASE_SNAPSHOT}"
  case "$1" in */packages/shared/*) return ;; esac
  printf ' %s=%q' \
    POCKNIX_SOC "${SOC}" \
    POCKNIX_TUNE_CFLAGS "${POCKNIX_TUNE_CFLAGS}" \
    POCKNIX_BOOTLOADER "${BOOTLOADER}" \
    POCKNIX_KERNEL_PKG "${KERNEL_PKG}" \
    POCKNIX_KERNEL_VERSION "${KERNEL_VERSION}" \
    POCKNIX_KERNEL_PKGREL "${KERNEL_PKGREL:-}" \
    POCKNIX_KERNEL_LEGACY_NAMES "${KERNEL_LEGACY_NAMES:-}"
}

build_one() {
  local pkgdir="$1" force="${2:-0}" name env; name="$(pkg_name "${pkgdir}")"; env="$(pkg_env "${pkgdir}")"
  local repo_dir repo_db repo_mount
  repo_dir="$(pkg_repo_dir "${pkgdir}")"
  repo_db="$(pkg_repo_db "${pkgdir}")"
  repo_mount="$(pkg_repo_mount "${pkgdir}")"
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
    local uptodate=1 nlist=0 p f s
    while IFS= read -r p; do
      nlist=$((nlist+1))
      f="${repo_dir}/$(basename "${p}")"
      if [ ! -f "${f}" ] || [ -n "$(find "${pkgdir}" -newer "${f}" -print -quit)" ]; then
        uptodate=0; break
      fi
      for s in $(pkg_extra_srcs "${name}"); do
        [ "${s}" -nt "${f}" ] && { uptodate=0; break 2; }
      done
      if [ "${name}" = "${KERNEL_PKG}" ] && [ -f "${KERNEL_BUILD_DIR}/out/Image" ] &&
         [ "${KERNEL_BUILD_DIR}/out/Image" -nt "${f}" ]; then
        uptodate=0; break
      fi
    done < <(chroot "${BROOT}" runuser -u builder -- \
               bash -lc "cd /build/${name} && LC_ALL=C ${env} makepkg --packagelist" 2>/dev/null)
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
  # The kernel package is THIN: it doesn't compile the kernel (no makepkg/toolchain in the
  # chroot for that), it just packages `make kernel`'s output. Stage ${KERNEL_BUILD_DIR}/out
  # into the package build dir as ./staged so its package() can lay it out as /boot +
  # /usr/lib/modules.
  if [ "${name}" = "${KERNEL_PKG}" ]; then
    local kout="${KERNEL_BUILD_DIR}/out"
    if [ ! -f "${kout}/Image" ] || [ ! -f "${kout}/kernelrelease" ]; then
      warn "${name}: no kernel build at ${kout} — run 'make kernel' first; skipping"
      return 1
    fi
    # SoC marker sanity: catches a copied/renamed out/ dir from another SoC
    if [ -f "${kout}/soc" ] && [ "$(cat "${kout}/soc")" != "${SOC}" ]; then
      warn "${name}: ${kout} was built for SOC=$(cat "${kout}/soc"), not ${SOC} — run 'make kernel DEVICE=${DEVICE}' first; skipping"
      return 1
    fi
    cp -a "${kout}" "${BROOT}/build/${name}/staged"
  fi
  # The cmdline is written once, in the profile: the qcom-abl BSP installs it for the on-device
  # boot image rebuild, the arm-efi bootloader renders it into grub.cfg.
  if [ "${name}" = "${DEVICE_BSP_PKG}" ] || [ "${name}" = "pocknix-bootloader-${SOC}" ]; then
    mkdir -p "${BROOT}/build/${name}/staged"
    printf '%s\n' "${KERNEL_CMDLINE}" > "${BROOT}/build/${name}/staged/kernel-cmdline"
  fi
  if [ "${name}" = "${DEVICE_BSP_PKG}" ]; then
    BOOTLOADER="${BOOTLOADER}" SD_FAT_LABEL="${SD_FAT_LABEL}" ROOT_LABEL="${ROOT_LABEL}" \
      "${POCKNIX_ROOT}/scripts/render-bsp.sh" "${pkgdir}/boards" "${BROOT}/build/${name}/staged"
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
  # BSPs + metapackages) are pure file-drop/meta packages built with --nodeps instead:
  # with -s makepkg would install their RUNTIME dependency closure into the build chroot
  # (the kernel package, the Steam stack, fex-rootfs) just to lay out a few files. Their
  # depends= still ships in the .pkg metadata; -d only skips build-time resolution. A
  # ./nodeps marker opts in other packages whose runtime deps would drag a layer in.
  # Per-SoC tuning (devices/<soc>/tuning.conf via lib.sh) rides the makepkg environment
  # (pkg_env): the tuned PKGBUILDs read POCKNIX_TUNE_CFLAGS, falling back to their sm8550
  # strings when unset (e.g. standalone makepkg).
  # Off must be CCACHE_DISABLE: meson wraps its compilers in any ccache on PATH whatever
  # BUILDENV says.
  local mkflags="-s" ccenv="CCACHE_DISABLE=1"
  [ "${CCACHE_ON}" = "1" ] && ccenv="CCACHE_DIR=/ccache CCACHE_MAXSIZE=${POCKNIX_CCACHE_SIZE}"
  case "${pkgdir}" in */devices/*/packages/*) mkflags="-d" ;; esac
  [ -f "${pkgdir}/nodeps" ] && mkflags="-d"
  if ! chroot "${BROOT}" runuser -u builder -- \
      bash -lc "cd /build/${name} && LC_ALL=C SRCDEST=/build/srccache ${ccenv} ${env} makepkg ${mkflags} -f --noconfirm --nocheck --skippgpcheck"; then
    warn "makepkg failed for ${name} — keeping any previous build in ${repo_dir##*/}"
    return 1
  fi
  # Collect what makepkg ACTUALLY produced via `makepkg --packagelist`: a split PKGBUILD
  # (packages/soc/mesa -> mesa + vulkan-freedreno) emits sibling packages a "${name}-*" glob
  # misses (only the mesa half would reach localrepo), while a bare *.pkg.tar.*
  # sweep would grab .pkg.tar.* files that are makepkg *sources* symlinked into the build
  # dir (e.g. fex-emu's pinned x86 sysroot pkgs). --packagelist names exactly the built
  # artifacts, epoch and all.
  local built_pkgs=() p
  while IFS= read -r p; do
    p="${BROOT}/build/${name}/$(basename "${p}")"
    [ -e "${p}" ] && built_pkgs+=("${p}")
  done < <(chroot "${BROOT}" runuser -u builder -- \
             bash -lc "cd /build/${name} && LC_ALL=C ${env} makepkg --packagelist" 2>/dev/null)
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
    rm -f "${repo_dir}/${base}"-[0-9]*.pkg.tar.* "${repo_dir}/${base}"-*:*.pkg.tar.* 2>/dev/null || true
  done
  cp "${built_pkgs[@]}" "${repo_dir}/"
  # Register exactly the artifacts just built (NOT *.pkg.tar.* — re-adding the whole repo
  # for every package spammed 'entry already existed' x N^2). LC_ALL=C: the build chroot
  # has no generated locales, and bsdtar warns on every tar op otherwise.
  local addlist=""
  for p in "${built_pkgs[@]}"; do addlist+=" $(basename "${p}")"; done
  chroot "${BROOT}" bash -lc "cd ${repo_mount} && LC_ALL=C repo-add -q ${repo_db}${addlist}"
}

main() {
  # Optional args = package names to build (subset, always rebuilt); no args = build
  # everything, skipping packages already up-to-date in the localrepo (see build_one).
  # e.g. `make packages PKG="inputplumber pocknix-bsp-sm8550"` to force just those two.
  local want=("$@")
  mkdir -p "${LOCALREPO}" "${LOCALREPO_SHARED}"
  setup_chroot

  chroot_mount "${BROOT}"
  # Keep both local repos bind-mounted throughout so makepkg -s can resolve inter-package
  # local deps (e.g. pocknix-emu-dolphin -> pocknix-emulation-common) from [pocknix]/[pocknix-shared]
  # as we go.
  mkdir -p "${BROOT}/localrepo" "${BROOT}/localrepo-shared"
  mount --bind "${LOCALREPO}" "${BROOT}/localrepo"
  mount --bind "${LOCALREPO_SHARED}" "${BROOT}/localrepo-shared"
  if [ "${CCACHE_ON}" = "1" ]; then
    mkdir -p "${CCACHE_HOST_DIR}" "${BROOT}/ccache"
    mount --bind "${CCACHE_HOST_DIR}" "${BROOT}/ccache"
    chroot "${BROOT}" chown builder:builder /ccache
  fi
  # Initialize both dbs so the repos are valid even on the first/partial run
  # (one full re-add; per-package registration during the run adds only new artifacts).
  local rmount rdb
  for rmount in /localrepo /localrepo-shared; do
    rdb="${REPO_DB}"; [ "${rmount}" = "/localrepo-shared" ] && rdb="${SHARED_REPO_DB}"
    if ls "${BROOT}${rmount}"/*.pkg.tar.* >/dev/null 2>&1; then
      chroot "${BROOT}" bash -lc "cd ${rmount} && LC_ALL=C repo-add -q ${rdb} \$(ls *.pkg.tar.* | grep -v '\.sig\$')" >/dev/null 2>&1
    else
      chroot "${BROOT}" bash -lc "cd ${rmount} && tar -czf ${rdb} -T /dev/null && ln -sf ${rdb} ${rdb%.tar.gz}"
    fi
  done

  # Build a package (build_one registers its artifacts in its repo so later packages
  # see them; the pacman -Sy refresh happens inside build_one, only for real builds).
  try_build() {
    if build_one "$1" "${2:-0}"; then
      built=$((built+1))
      return 0
    fi
    return 1
  }

  local built=0 name force devdir devsoc pkgsocs pkggpus
  local -a failed=()
  # Per-SoC and device packages build only into the CURRENT SoC's repo: device packages by
  # their profile's SOC, packages/soc by ./socs, packages/gpu by ./gpus against GPU_GEN. The
  # gpus gate keeps the a6xx dxvk2 protons out of every other GPU's repo, where their replaces=
  # would downgrade DXVK. PKG= names and POCKNIX_FORCE_REBUILD=1 force past the up-to-date skip.
  for pkgdir in "${PACKAGES_DIR}"/shared/*/ "${PACKAGES_DIR}"/soc/*/ "${PACKAGES_DIR}"/gpu/*/ "${POCKNIX_ROOT}"/devices/*/packages/*/; do
    [ -f "${pkgdir}/PKGBUILD" ] || continue
    name="$(pkg_name "${pkgdir}")"
    case "${pkgdir}" in */devices/*/packages/*)
      devdir="$(dirname "$(dirname "${pkgdir%/}")")"
      devsoc="$(profile_get "${devdir}" SOC)"
      [ "${devsoc}" = "${SOC}" ] || continue
    ;; esac
    case "${pkgdir}" in
      */packages/soc/*)
        [ -f "${pkgdir}/socs" ] || die "${name}: packages/soc/ package with no socs file: declare its SoC(s), or all, on one space-separated line"
        read -r pkgsocs < "${pkgdir}/socs" || true   # a 0-byte file fails read; the next line names it
        [ -n "${pkgsocs}" ] || die "${name}: empty socs file"
        case " ${pkgsocs} " in " all "|*" ${SOC} "*) ;; *) continue ;; esac ;;
      */packages/gpu/*)
        [ -f "${pkgdir}/gpus" ] || die "${name}: packages/gpu/ package with no gpus file: declare its Adreno generation(s) on one space-separated line"
        [ -n "${GPU_GEN:-}" ] || die "${name}: gated on ./gpus but devices/${DEVICE}/profile.conf sets no GPU_GEN"
        read -r pkggpus < "${pkgdir}/gpus" || true
        [ -n "${pkggpus}" ] || die "${name}: empty gpus file"
        case " ${pkggpus} " in *" ${GPU_GEN} "*) ;; *) continue ;; esac ;;
    esac
    force=0
    [ "${POCKNIX_FORCE_REBUILD:-0}" = "1" ] && force=1
    if [ "${#want[@]}" -gt 0 ]; then
      case " ${want[*]} " in *" ${name} "*) force=1 ;; *) continue ;; esac
    fi
    try_build "${pkgdir}" "${force}" || failed+=("${pkgdir}")
  done

  # Dependency order != alphabetical: a package can depend on a sibling the glob builds LATER,
  # so its first `makepkg -s` aborts with "target not found". Retry failures: once a dep lands
  # in its repo the dependent builds. Loop until a full pass makes no progress (then they're
  # real failures).
  while [ "${#failed[@]}" -gt 0 ]; do
    local -a retry=("${failed[@]}"); failed=(); local progress=0
    for pkgdir in "${retry[@]}"; do
      if try_build "${pkgdir}"; then progress=1; else failed+=("${pkgdir}"); fi
    done
    [ "${progress}" -eq 1 ] || break
  done
  # --- failure summary: surface the SILENT danger. A failed rebuild that left an OLDER build in
  # localrepo gets installed by build-image with no error, so a stale package ships. Split the
  # failures into "stale artifact still present" (dangerous, loud) vs "no artifact" (build-image
  # errors at install, not silent).
  if [ "${#failed[@]}" -gt 0 ]; then
    local -a stale=() gone=() fnames=()
    local fp fname base p af had line frepo
    for fp in "${failed[@]}"; do
      fname="$(pkg_name "${fp}")"; had=0; fnames+=("${fname}")
      frepo="$(pkg_repo_dir "${fp}")"
      # artifact base name(s) this PKGBUILD produces (split pkgs -> several); --packagelist only
      # reads the PKGBUILD so it works even though the build failed.
      while IFS= read -r p; do
        [ -n "${p}" ] || continue
        base="$(basename "${p}")"; base="${base%-*}"; base="${base%-*}"; base="${base%-*}"
        for af in "${frepo}/${base}"-[0-9]*.pkg.tar.* "${frepo}/${base}"-*:*.pkg.tar.*; do
          [ -e "${af}" ] || continue
          stale+=("${base}  (localrepo still has $(basename "${af}"))"); had=1
        done
      done < <(chroot "${BROOT}" runuser -u builder -- \
                 bash -lc "cd /build/${fname} 2>/dev/null && LC_ALL=C $(pkg_env "${fp}") makepkg --packagelist" 2>/dev/null)
      [ "${had}" -eq 0 ] && gone+=("${fname}")
    done
    echo >&2
    warn "PACKAGE BUILD FAILURES (${#failed[@]}): ${fnames[*]}"
    if [ "${#stale[@]}" -gt 0 ]; then
      warn "  STALE ARTIFACT WILL SHIP: the rebuild failed but an OLD version stays in localrepo,"
      warn "  so 'make build' installs the stale one with no error. Rebuild before building an image:"
      while IFS= read -r line; do warn "    - ${line}"; done < <(printf '%s\n' "${stale[@]}" | sort -u)
    fi
    [ "${#gone[@]}" -gt 0 ] && warn "  no artifact in localrepo (build-image errors at install, not silent): ${gone[*]}"
  fi

  umount "${BROOT}/localrepo"
  umount "${BROOT}/localrepo-shared"
  mountpoint -q "${BROOT}/ccache" && umount "${BROOT}/ccache"
  chroot_umount "${BROOT}"
  trap - EXIT

  [ "${built}" -gt 0 ] || die "no packages built"
  ok "local repos ready -> ${LOCALREPO} + ${LOCALREPO_SHARED}"
  # A PKG= run leaves the other repo empty: its unmatched glob must not fail a good build.
  ls -1 "${LOCALREPO}"/*.pkg.tar.* "${LOCALREPO_SHARED}"/*.pkg.tar.* 2>/dev/null | sed 's#.*/#  #' || true
}

main "$@"
