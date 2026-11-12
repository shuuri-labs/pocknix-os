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

# soc/ and gpu/ build per SoC (same pkgnames, different binaries) in split chroots, so tuned
# makedepends never leak; shared/ builds once into [pocknix-shared], by whichever SoC runs first.
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
  # An old-base chroot stamps binaries with sonames the new base lacks: recreate on a pin change.
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
    # Re-render drops [pocknix]; it is re-added after the -Syu, since pacman dies on a repo whose
    # file:///localrepo isn't mounted until main().
    render_base_pacman_conf "${BROOT}/etc/pacman.conf"
    # Converge the reused chroot to the base, or it lags devices (sonames we never linked against).
    chroot_mount "${BROOT}"
    # A pinned base is frozen: with a matching stamp a failed -Syu just means offline. Unpinned,
    # the drift is real and the build must stop.
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

  # Idempotent; also repairs chroots made without sudo, which makepkg -s needs as builder.
  chroot "${BROOT}" id builder >/dev/null 2>&1 || chroot "${BROOT}" useradd -m builder
  if [ ! -x "${BROOT}/usr/bin/sudo" ]; then
    chroot_mount "${BROOT}"
    chroot "${BROOT}" pacman -Sy --noconfirm --needed sudo
    chroot_umount "${BROOT}"
  fi
  printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > "${BROOT}/etc/sudoers.d/builder"
  chmod 0440 "${BROOT}/etc/sudoers.d/builder"

  # A base without ccache builds uncached. The drop-in exists only next to the binary: makepkg
  # aborts when BUILDENV asks for a ccache it cannot find.
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

  # SigLevel Never: a signed localrepo db makes Optional TrustAll die on the unknown key when
  # makepkg -s installs a local dep. The sed branch repairs chroots with the old stanza.
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

# Files outside a package's dir that it is built from: editing one rebuilds it like its own.
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

# Every makepkg call needs it, --packagelist included (the kernel recipe's version comes from it).
# Shared packages get no SoC/tuning env, so they are byte-stable whichever SoC builds them.
pkg_env() {  # $1 = package dir
  # pocknix-lock-migrate stamps the base URL into its script: a snapshot bump re-targets it.
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
  # Skip when every --packagelist artifact is in the localrepo and newer than every file in the
  # dir. PKG= and POCKNIX_FORCE_REBUILD=1 force; the kernel also rebuilds on a newer Image.
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
  # Refresh sync DBs (makepkg -s must see this run's siblings) only when building.
  chroot "${BROOT}" pacman -Sy --noconfirm >/dev/null 2>&1 || true
  # Thin package: it lays out `make kernel`'s out/, staged as ./staged; nothing compiles here.
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
  # The cmdline is written once, in the profile: the BSP installs it for the on-device boot files,
  # the arm-efi bootloader renders it into grub.cfg.
  if [ "${name}" = "${DEVICE_BSP_PKG}" ] || [ "${name}" = "pocknix-bootloader-${SOC}" ]; then
    mkdir -p "${BROOT}/build/${name}/staged"
    printf '%s\n' "${KERNEL_CMDLINE}" > "${BROOT}/build/${name}/staged/kernel-cmdline"
  fi
  if [ "${name}" = "${DEVICE_BSP_PKG}" ]; then
    BOOTLOADER="${BOOTLOADER}" SD_FAT_LABEL="${SD_FAT_LABEL}" ROOT_LABEL="${ROOT_LABEL}" \
      "${POCKNIX_ROOT}/scripts/render-bsp.sh" "${pkgdir}/boards" "${BROOT}/build/${name}/staged"
  fi
  # SRCDEST outlives the wiped build dir: file sources download once, git sources fetch deltas.
  mkdir -p "${BROOT}/build/srccache"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  chroot "${BROOT}" chown builder:builder /build/srccache
  # Device packages and ./nodeps opt-ins build -d: -s would pull their runtime closure into the
  # chroot. Off must be CCACHE_DISABLE: meson wraps any ccache on PATH whatever BUILDENV says.
  local mkflags="-s" ccenv="CCACHE_DISABLE=1"
  [ "${CCACHE_ON}" = "1" ] && ccenv="CCACHE_DIR=/ccache CCACHE_MAXSIZE=${POCKNIX_CCACHE_SIZE}"
  case "${pkgdir}" in */devices/*/packages/*) mkflags="-d" ;; esac
  [ -f "${pkgdir}/nodeps" ] && mkflags="-d"
  if ! chroot "${BROOT}" runuser -u builder -- \
      bash -lc "cd /build/${name} && LC_ALL=C SRCDEST=/build/srccache ${ccenv} ${env} makepkg ${mkflags} -f --noconfirm --nocheck --skippgpcheck"; then
    warn "makepkg failed for ${name} — keeping any previous build in ${repo_dir##*/}"
    return 1
  fi
  # --packagelist names exactly what was built: a "${name}-*" glob misses split siblings, and a
  # bare *.pkg.tar.* sweep grabs package sources symlinked into the build dir.
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
  # Only now touch the repo, so a failed build never wipes a good package. rm before cp: the new
  # file's epoch'd name matches *:*, so cp then rm would delete it.
  local base
  for p in "${built_pkgs[@]}"; do
    base="$(basename "${p}")"
    base="${base%-*}"; base="${base%-*}"; base="${base%-*}"  # strip -<ver>-<rel>-<arch>.pkg.tar.*
    rm -f "${repo_dir}/${base}"-[0-9]*.pkg.tar.* "${repo_dir}/${base}"-*:*.pkg.tar.* 2>/dev/null || true
  done
  cp "${built_pkgs[@]}" "${repo_dir}/"
  # Add only what was just built (re-adding the repo is N^2). LC_ALL=C: the chroot has no locales.
  local addlist=""
  for p in "${built_pkgs[@]}"; do addlist+=" $(basename "${p}")"; done
  chroot "${BROOT}" bash -lc "cd ${repo_mount} && LC_ALL=C repo-add -q ${repo_db}${addlist}"
}

main() {
  # Args = package names, always rebuilt; none = everything, skipping what is up to date.
  local want=("$@")
  mkdir -p "${LOCALREPO}" "${LOCALREPO_SHARED}"
  setup_chroot

  chroot_mount "${BROOT}"
  # Both repos stay mounted so makepkg -s resolves deps built earlier in this run.
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
  # Per-SoC and device packages build only into this SoC's repo. The gpus gate keeps the a6xx
  # dxvk2 protons out of other GPUs' repos, where their replaces= would downgrade DXVK.
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

  # Glob order is not dependency order: retry failures until a full pass makes no progress.
  while [ "${#failed[@]}" -gt 0 ]; do
    local -a retry=("${failed[@]}"); failed=(); local progress=0
    for pkgdir in "${retry[@]}"; do
      if try_build "${pkgdir}"; then progress=1; else failed+=("${pkgdir}"); fi
    done
    [ "${progress}" -eq 1 ] || break
  done
  # --- failure summary ---
  # A failed rebuild that left an older build in localrepo ships silently via build-image, so
  # report those apart from packages with no artifact (build-image errors on those).
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
