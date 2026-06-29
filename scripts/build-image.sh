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
  # pocknix-desktop = the Plasma Mobile desktop session + the game<->desktop switch
  # (steamos-session-select). The Plasma Mobile stack itself comes from desktop.list (installed
  # above), not as deps of this package. Boot default stays game mode (the choice file defaults to
  # gamescope); desktop is opt-in via the switch. See docs/plasma-mobile-plan.md.
  #
  # QUALIFY every target with `pocknix/`: `pacman -S <name>` selects the FIRST repo in pacman.conf
  # order that has the name (NOT the highest version), and [pocknix] is appended LAST — so an
  # unqualified `gamescope`/`mangohud` would resolve to ALARM's [extra] copy (gamescope's vanilla
  # build black-screens the rotated panel; our patched mangohud has the Adreno reader). epoch=1 only
  # affects `-Syu` upgrades, not `-S` selection. Qualifying forces our builds and errors loudly if a
  # local package is genuinely missing from [pocknix] instead of silently grabbing ALARM's.
  chroot "${root}" pacman -S --noconfirm --needed \
        pocknix/pocknix-bsp pocknix/gamescope pocknix/inputplumber pocknix/pocknix-steamos-shim \
        pocknix/mangohud pocknix/pocknix-steam pocknix/fex-emu pocknix/fex-rootfs pocknix/pocknix-desktop
  # GUARD: these local builds MUST come from [pocknix], not silently fall back / go missing. gamescope
  # especially: ALARM's vanilla lacks --use-rotation-shader and black-screens on the RP6 (bitten 3x).
  local gs_ver; gs_ver="$(chroot "${root}" pacman -Q gamescope 2>/dev/null | awk '{print $2}')"
  case "${gs_ver}" in
    1:*rocknix*) log "gamescope OK: ${gs_ver} (epoch-1 patched build)" ;;
    *) umount "${root}/localrepo" 2>/dev/null || true
       die "gamescope resolved to '${gs_ver}', NOT our epoch-1 [pocknix] rocknix build. Vanilla gamescope can't drive the RP6's rotated panel (no --use-rotation-shader) -> black screen. The install pins pocknix/gamescope, so reaching here means [pocknix] is missing it: confirm build/localrepo/gamescope-1:*.pkg.tar.* exists AND is registered in pocknix.db ('make packages PKG=gamescope' rebuilds + repo-adds it), then re-run." ;;
  esac
  local lp
  for lp in fex-emu fex-rootfs; do
    chroot "${root}" pacman -Q "${lp}" >/dev/null 2>&1 || {
      umount "${root}/localrepo" 2>/dev/null || true
      die "${lp} not installed — its local build wasn't in [pocknix]. Build it: 'make packages PKG=${lp}' (fex-rootfs downloads the ~1.1 GB Arch x86 squashfs once), confirm build/localrepo/${lp}-*.pkg.tar.* exists, then re-run."
    }
  done
  # pocknix-desktop must come from [pocknix] too (it pulls the Plasma Mobile stack from ALARM).
  chroot "${root}" pacman -Q pocknix-desktop >/dev/null 2>&1 || {
    umount "${root}/localrepo" 2>/dev/null || true
    die "pocknix-desktop not installed — its local build wasn't in [pocknix]. Build it: 'make packages PKG=pocknix-desktop', confirm build/localrepo/pocknix-desktop-*.pkg.tar.* exists, then re-run."
  }
  # Kernel: swap ALARM's generic linux-aarch64 for our linux-pocknix (Image + modules, built by
  # `make kernel` -> staged into the package). Its own step (not bundled above) so a missing kernel
  # build errors clearly, and the replace is deterministic. linux-pocknix `provides=linux`.
  if chroot "${root}" pacman -Si pocknix/linux-pocknix >/dev/null 2>&1; then
    chroot "${root}" pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
    rm -rf "${root}/boot/initramfs-linux"*.img 2>/dev/null || true
    chroot "${root}" pacman -S --noconfirm pocknix/linux-pocknix
    chroot "${root}" pacman -Q linux-pocknix >/dev/null 2>&1 || {
      umount "${root}/localrepo" 2>/dev/null || true
      die "linux-pocknix failed to install — check the pacman output above."
    }
    log "kernel OK: $(chroot "${root}" pacman -Q linux-pocknix)"
  else
    umount "${root}/localrepo" 2>/dev/null || true
    die "linux-pocknix not in [pocknix] — run 'make kernel' first (build-packages.sh stages build/kernel/out into the package), then re-run. Without it the rootfs has no matching modules for the booted kernel."
  fi
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

# Generate a UTF-8 locale (ALARM base is "C" only). Qt/Plasma warn + fall back to C.UTF-8 otherwise.
configure_locale() {
  local root="$1"
  log "generating en_US.UTF-8 locale"
  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "${root}/etc/locale.gen"
  chroot "${root}" locale-gen
  echo 'LANG=en_US.UTF-8' > "${root}/etc/locale.conf"
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
    # --chown=root:root: the vendor firmware tree is owned by the host build user (uid 1000); plain
    # rsync -a would bake that into the rootfs as 'alarm'-owned firmware (and re-own /usr). Force root.
    rsync -a --chown=root:root "${FW_SRC}/" "${root}/usr/lib/firmware/"
  else
    warn "ROCKNIX firmware overlay not at ${FW_SRC} — run 'make sync' (wifi/audio firmware will be missing)"
  fi
}

# NOTE: kernel integration (modules + Image, and replacing ALARM's linux-aarch64) is now done by
# the linux-pocknix PACKAGE, installed in install_local_packages() — no separate install_kernel().

# Bake the native ARM Steam client at BUILD time (armada's generate-steam-bootstrap model) so first
# boot needs no network (drops the Wi-Fi-preseed requirement). Runs the on-device installer in the
# rootfs chroot — which already has the steam deps + Xvfb — under a STAGING HOME, verifies the tree
# is complete (steamui.so + the channel .installed manifest, else the seed would re-install online),
# strips per-session cruft, and tars the HOME-agnostic tree (relative .steam symlinks) into a
# re-seedable seed at /usr/share/pocknix-steam/steam-seed.tar.zst. pocknix-steam extracts it offline
# on first run. Cached in ${CACHE_DIR} so it runs once (POCKNIX_REBOOTSTRAP_STEAM=1 forces a rebake);
# POCKNIX_SKIP_STEAM_BAKE=1 skips entirely (no seed -> first boot downloads it, needs network).
bootstrap_steam_seed() {
  local root="$1"
  local seed="${CACHE_DIR}/steam-seed.tar.zst"
  local home="/var/lib/pocknix/steam-seed-home"
  local steam="${home}/.local/share/Steam"

  if [ -n "${POCKNIX_SKIP_STEAM_BAKE:-}" ]; then
    warn "POCKNIX_SKIP_STEAM_BAKE set — not baking Steam; first boot will download it (needs network)"
    return 0
  fi

  if [ ! -f "${seed}" ] || [ -n "${POCKNIX_REBOOTSTRAP_STEAM:-}" ]; then
    log "baking native ARM Steam client (downloads + Xvfb self-update; can take several minutes)..."
    # steam/bwrap need a real writable /dev/shm. chroot_mount binds host /dev (non-recursive), so the
    # chroot has none. Make the chroot's /dev private FIRST so this tmpfs can't propagate up and
    # shadow the HOST's /dev/shm (the bind aliases the same path), then mount a private tmpfs.
    mount --make-rprivate "${root}/dev" 2>/dev/null || true
    mount -t tmpfs tmpfs "${root}/dev/shm"
    chroot "${root}" rm -rf "${home}"; chroot "${root}" mkdir -p "${home}"
    if ! chroot "${root}" env HOME="${home}" /usr/bin/pocknix-steam-install; then
      umount "${root}/dev/shm" 2>/dev/null || true
      die "steam bake failed (pocknix-steam-install in chroot). Check network, or POCKNIX_SKIP_STEAM_BAKE=1 to defer to first boot."
    fi
    if ! chroot "${root}" test -f "${steam}/steamrtarm64/steamui.so" \
       || ! chroot "${root}" test -f "${steam}/package/steam_client_steamdeck_publicbeta_linuxarm64.installed"; then
      umount "${root}/dev/shm" 2>/dev/null || true
      die "steam bake incomplete (no steamui.so / .installed) — seed would re-install on first boot. Re-run, or POCKNIX_SKIP_STEAM_BAKE=1."
    fi
    # strip per-session cruft AND registry.vdf (like armada) so the seed shows the OOBE on first boot
    # — the user configures Wi-Fi there; pocknix-steamos-shim's steamos-update keeps the OOBE's
    # required-update step from dead-ending. Then tar the HOME-agnostic tree.
    chroot "${root}" bash -c "set -e; cd '${home}'
      rm -rf .local/share/Steam/logs .local/share/Steam/appcache/httpcache \
             .local/share/Steam/appcache/cefdata .local/share/Steam/config/htmlcache
      find . \( -name '*.log' -o -name '*.pid' -o -name '*.token' -o -name '*.crash' \) -delete
      find . \( -type s -o -type p \) -delete
      rm -f .local/share/Steam/ssfn* .local/share/Steam/registry.vdf \
            .steam/registry.vdf .steam/steam.pid .steam/steam.token
      tar -caf /steam-seed.tar.zst .local .steam"
    mkdir -p "${CACHE_DIR}"; cp "${root}/steam-seed.tar.zst" "${seed}"
    chroot "${root}" rm -f /steam-seed.tar.zst; chroot "${root}" rm -rf "${home}"
    umount "${root}/dev/shm" 2>/dev/null || true
    ok "steam seed baked: ${seed} ($(du -h "${seed}" | cut -f1))"
  else
    log "using cached steam seed: ${seed} ($(du -h "${seed}" | cut -f1))"
  fi
  install -Dm644 "${seed}" "${root}/usr/share/pocknix-steam/steam-seed.tar.zst"
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
  install_packages "${ROOTFS_DIR}" "${CONFIG_DIR}/packages/desktop.list"      # Phase 4 (ALARM): Plasma Mobile stack

  # Generate a UTF-8 locale. The ALARM base ships only "C"; Qt apps (all of Plasma) warn and fall
  # back to C.UTF-8 on every launch, and the C path is slower. Set en_US.UTF-8 system-wide.
  configure_locale "${ROOTFS_DIR}"

  # 4. device support (Phase 2): SM8550 firmware + pocknix-bsp (suspend hooks etc.).
  #    The kernel (linux-pocknix: Image + modules, replacing ALARM's linux-aarch64) is installed
  #    inside install_local_packages from build/kernel/out — run `make kernel` first.
  install_firmware "${ROOTFS_DIR}"
  install_local_packages "${ROOTFS_DIR}"

  # 5. bake the native ARM Steam client into a re-seedable seed (offline first boot)
  bootstrap_steam_seed "${ROOTFS_DIR}"

  chroot_umount "${ROOTFS_DIR}"; trap - EXIT

  # 6. assemble bootable image (Phase 6)
  warn "STUB: image assembly (Phase 6) not implemented yet"

  ok "build-image: base rootfs built at ${ROOTFS_DIR} (later phases stubbed)"
}

main "$@"
