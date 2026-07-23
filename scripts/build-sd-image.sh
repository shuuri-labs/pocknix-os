#!/usr/bin/env bash
# build-sd-image.sh — assemble a flashable SD image to boot-test pocknix WITHOUT
# touching internal ROCKNIX. Layout mirrors ROCKNIX's SD for the SoC's
# BOOTLOADER style so the device's existing (ROCKNIX-flashed) ABL boots it:
#
#   GPT  p1  fat32  name "${SD_BOOT_PARTNAME}" (label ${SD_FAT_LABEL})  -> /KERNEL [+ GRUB]
#        p2  ext4   name "${ROOT_LABEL}"                                -> Arch base rootfs
#
# qcom-abl (sm8550): ABL loads /KERNEL (Android boot image, cmdline baked in).
# arm-efi  (sm8250): the factory ABL chainloads /EFI/BOOT/bootaa64.efi ->
#   /boot/grub/grub.cfg -> "linux /KERNEL" (raw Image) + "devicetree
#   /boot/grub/<board>.dtb"; the FAT additionally carries EFI/ and boot/grub/
#   (cfg + grubenv + dtbs). ROCKNIX sets legacy_boot on p1 for BOTH styles (no esp flag).
# Either way our kernel mounts its root directly by PARTUUID (fixed SD GUIDs; no
# initramfs — UFS/ext4 are built in). ROCKNIX also puts a SYSTEM squashfs on
# the FAT; we don't need it (plain ext4 root).
#
# Prereqs: `sudo make build` (rootfs) + `make kernel` (KERNEL). Run as root (loop+mount).
# Flash:   sudo dd if=build/image/<soc>/pocknix-<soc>-sd.img of=/dev/sdX bs=4M conv=fsync status=progress

source "$(dirname "$0")/lib.sh"
need_linux
need_root sd-image
for t in parted sgdisk mkfs.vfat mkfs.ext4 losetup rsync chroot truncate du; do need_tool "$t"; done   # sgdisk: gptfdisk pkg

KERNEL_IMG="${IMAGE_DIR}/KERNEL"
KOUT="${KERNEL_BUILD_DIR}/out"   # per-SoC (set in lib.sh)
OUT="${IMAGE_DIR}/pocknix-${SOC}-sd.img"   # one image per SoC family -> name it so

[ -f "${KERNEL_IMG}" ] || die "no ${KERNEL_IMG} — run 'make kernel' first"
[ -d "${ROOTFS_DIR}" ] || die "no rootfs at ${ROOTFS_DIR} — run 'sudo make build' first"

LOOP=""; MNT=""
cleanup() {
  [ -n "${MNT}" ] && mountpoint -q "${MNT}" && umount "${MNT}" 2>/dev/null || true
  [ -n "${MNT}" ] && rmdir "${MNT}" 2>/dev/null || true
  [ -n "${LOOP}" ] && losetup -d "${LOOP}" 2>/dev/null || true
}
trap cleanup EXIT

# Make sure the rootfs carries the pocknix kernel modules + drops the generic
# ALARM kernel, in case `make build` ran before the kernel existed (idempotent).
ensure_kernel_in_rootfs() {
  # SoC marker sanity (kernel outputs are per-SoC dirs now, so this should never
  # fire — kept as cheap insurance against manual copies/renames)
  if [ -f "${KOUT}/soc" ] && [ "$(cat "${KOUT}/soc")" != "${SOC}" ]; then
    die "${KOUT} was built for SOC=$(cat "${KOUT}/soc"), not ${SOC} — run 'make kernel DEVICE=${DEVICE}' first"
  fi
  if [ -d "${KOUT}/modroot/lib/modules" ]; then
    local kver; kver="$(cat "${KOUT}/kernelrelease" 2>/dev/null)"
    log "syncing pocknix modules (${kver}) into rootfs + removing generic kernel"
    chroot "${ROOTFS_DIR}" pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
    # --chown=root:root: the kernel build output is owned by the host build user (uid 1000), and
    # plain rsync -a preserves that — which inside the ALARM rootfs is 'alarm', not root. Force root.
    rsync -a --chown=root:root "${KOUT}/modroot/lib/modules/" "${ROOTFS_DIR}/usr/lib/modules/"
    [ -n "${kver}" ] && chroot "${ROOTFS_DIR}" depmod "${kver}" 2>/dev/null || true
  else
    warn "no kernel modules in ${KOUT} — rootfs may lack matching modules"
  fi
}

# arm-efi boot partition contents beyond /KERNEL: GRUB + grub.cfg/grubenv +
# every board dtb + the ROCKNIX ABL payload. All of it except the dtbs is
# shipped in the rootfs by pocknix-bootloader-${SOC} (single source of truth:
# its alpm hook refreshes /flash from the same tree on upgrades); the dtbs come
# from the kernel build (grub.cfg references /boot/grub/<board>.dtb).
populate_arm_efi_boot() {
  local mnt="$1" bl="${ROOTFS_DIR}/usr/share/pocknix/bootloader"
  [ -f "${bl}/EFI/BOOT/bootaa64.efi" ] \
    || die "arm-efi: ${bl#${ROOTFS_DIR}}/EFI/BOOT/bootaa64.efi missing from the rootfs — is pocknix-bootloader-${SOC} built and installed? (make packages + make build)"
  [ -f "${bl}/boot/grub/grub.cfg" ] \
    || die "arm-efi: ${bl#${ROOTFS_DIR}}/boot/grub/grub.cfg missing from the rootfs"
  rsync -a "${bl}/EFI" "${bl}/boot" "${mnt}/"
  cp "${KOUT}/dtbs/"*.dtb "${mnt}/boot/grub/"
}

# qcom-abl boot partition contents beyond /KERNEL: the ROCKNIX ABL install kit
# (rocknix_abl/: signed ABL elf + the Android-side backup/flash/restore
# scripts), copied to the FAT root exactly where ROCKNIX's images carry it —
# stock Android mounts this FAT, so a factory device can be provisioned from
# this SD alone (backup then flash from rooted Android; see the kit README).
# Inert files at boot; shipped in the rootfs by pocknix-bootloader-${SOC}.
populate_qcom_abl_boot() {
  local mnt="$1" kit="${ROOTFS_DIR}/usr/share/pocknix/bootloader/rocknix_abl"
  [ -f "${kit}/abl_signed-${SOC^^}.elf" ] \
    || die "qcom-abl: ${kit#${ROOTFS_DIR}}/abl_signed-${SOC^^}.elf missing from the rootfs — is pocknix-bootloader-${SOC} built and installed? (make packages + make build)"
  rsync -a "${kit}" "${mnt}/"
}

firstboot_config() {
  local root="$1"
  log "configuring first boot (root login, fstab, ssh, network, hostname)"
  echo "root:${SD_ROOT_PASSWORD}" | chroot "${root}" chpasswd
  cat > "${root}/etc/fstab" <<EOF
# pocknix-os test image
# noatime: no software here needs atime; dropping atime write-backs cuts flash writes (SteamOS/ROCKNIX do the same).
PARTUUID=${SD_ROOT_PARTUUID}  /       ext4  rw,noatime         0 1
PARTUUID=${SD_BOOT_PARTUUID}  /flash  vfat  rw,noatime,nofail  0 2
EOF
  echo "pocknix" > "${root}/etc/hostname"
  # Default timezone: the ALARM base ships NO /etc/localtime, so libc (and thus the SteamOS/Plasma
  # clock) silently falls back to UTC and changing the zone in the UI "has no effect" — there's no
  # file for it to land in. Ship a default symlink (overridable via SD_TIMEZONE); the user can change
  # it in the OOBE / Settings (deck is authorised via overlay 50-pocknix-deck.rules -> timedate1).
  chroot "${root}" ln -sfn "/usr/share/zoneinfo/${SD_TIMEZONE:-UTC}" /etc/localtime
  if [ -f "${root}/etc/ssh/sshd_config" ]; then
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "${root}/etc/ssh/sshd_config"
  fi

  # install the committed test-image overlay (diag dump, autologin, NM conf, fan/volume helpers)
  if [ -d "${POCKNIX_ROOT}/overlay" ]; then
    log "installing overlay (diag + autologin + helpers)"
    # --chown=root:root is REQUIRED: the overlay lives in the host git checkout owned by the build
    # user (uid 1000). Plain rsync -a preserves that ownership AND stamps the destination parent dirs
    # it touches (/, /usr, /etc/systemd, /etc/polkit-1, /root) — inside the ALARM rootfs uid 1000 is
    # 'alarm', not root. That silently broke privilege-bounded services: systemd-timedated runs as root
    # but with CapabilityBoundingSet=CAP_SYS_TIME (no DAC_OVERRIDE), so it couldn't write /etc/localtime
    # when /etc was alarm-owned -> "set timezone has no effect". Force every overlay path to root:root.
    rsync -a --chown=root:root "${POCKNIX_ROOT}/overlay/" "${root}/"
    chmod +x "${root}/usr/local/bin/pocknix-diag" \
             "${root}/usr/local/bin/pocknix-expand-root" "${root}/usr/local/bin/pocknix-fancontrol" \
             "${root}/usr/local/bin/pocknix-volumed" "${root}/usr/local/bin/pocknix-powerd" \
             "${root}/usr/local/bin/pocknix-install-internal" \
             "${root}/usr/local/bin/pocknix-uninstall-internal" 2>/dev/null || true
  fi

  # --- non-root 'deck' session user ---
  # PipeWire refuses to run as root (ConditionUser=!root), so audio ("no output devices detected" in
  # Steam) only works for a normal user; bwrap/pressure-vessel (Proton) prefer non-root too. uid 1001
  # (ALARM ships 'alarm' at 1000). Groups: video/render (GPU), input (gamepad), audio, seat (seatd),
  # wheel (polkit admin via 50-pocknix-deck.rules). The overlay (rsync'd above) already placed
  # /home/deck/.bash_profile (boot-to-Steam) + the tty1 autologin=deck drop-in; useradd -m reuses
  # that home, then we chown it.
  log "creating non-root 'deck' session user (audio + Proton need a normal user)"
  chroot "${root}" useradd -m -u 1001 -U -s /bin/bash -G video,render,input,audio,seat,wheel deck 2>/dev/null || true
  echo "deck:${SD_DECK_PASSWORD:-${SD_ROOT_PASSWORD}}" | chroot "${root}" chpasswd
  # XDG user dirs in deck's home (Dolphin "Places", file dialogs, screenshots, downloads expect
  # these). The xdg-user-dirs package (desktop.list) also writes ~/.config/user-dirs.dirs at first
  # login so XDG_PICTURES_DIR etc. resolve, but create them here so they exist from first boot.
  for d in Desktop Documents Downloads Music Pictures Videos; do
    mkdir -p "${root}/home/deck/${d}"   # ownership fixed by the chown below ('deck' is unknown to the host)
  done
  # One chown covers everything under /home/deck: the XDG dirs just made, the overlay's .bash_profile/
  # .config, AND the Steam tree pre-extracted into it by build-image.sh (all root-owned until now).
  chroot "${root}" chown -R deck:deck /home/deck
  # NB: the native Steam client is already pre-extracted into /home/deck by build-image.sh's
  # bootstrap_steam_seed (done there so `du -sm ROOTFS_DIR` above sizes the partition to fit the
  # ~1.3 GB tree). The chown above (root -> deck) is what gives deck ownership of it. Guard: the
  # bake is mandatory (the on-device launcher has no network fallback), so a missing tree means a
  # broken/stale rootfs — fail rather than ship a Steam session that hard-fails on first launch.
  [ -x "${root}/home/deck/.local/share/Steam/steamrtarm64/steam" ] \
    || die "Steam client not pre-extracted in the rootfs (/home/deck/.local/share/Steam) — run 'sudo make build' first."

  # PipeWire/WirePlumber for deck's session (global-enable so its --user units start on login).
  chroot "${root}" systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
  # Root services: RP6 fan curve + FEX-binfmt-off (deck can't write /proc/sys/fs/binfmt_misc) +
  # the volume-rocker handler (Steam shows the OSD but doesn't change volume on KEY_VOLUME*) +
  # gamescope-rt (RRs the compositor from root — the deck session has no rtprio grant, the
  # SteamOS model; see limits.d/60-pocknix-gaming.conf. Replaces the old rt-demote watcher).
  chroot "${root}" systemctl enable pocknix-fancontrol.service pocknix-fex-binfmt-off.service \
        pocknix-volumed.service pocknix-gamescope-rt.service pocknix-powerd.service 2>/dev/null || true
  # Decky Loader (QAM plugins, incl. Pocknix Control): seed deck's ~/homebrew at boot, then run
  # the loader under FEX in its private-binfmt namespace (see packages/pocknix-decky).
  chroot "${root}" systemctl enable pocknix-decky-sync.service pocknix-decky-loader.service 2>/dev/null || true
  # Desktop (Plasma Mobile) session: register the Flathub remote on the first online boot so
  # Discover/flatpak can install apps. Harmless in game-only use (oneshot, no-op once added).
  chroot "${root}" systemctl enable pocknix-flathub.service 2>/dev/null || true
  # Waydroid: re-assert the Android /data tuning (nav/density/font/immersive/multi_windows)
  # after each container boot — those settings are wiped by `waydroid init`. See docs/waydroid.md.
  chroot "${root}" systemctl enable pocknix-waydroid-tuning.service 2>/dev/null || true

  # Wi-Fi pre-seed — SteamOS topology: NetworkManager is the FRONT-END (Steam's gamepadui manages
  # Wi-Fi ONLY through NM's D-Bus API — without it the setup wizard shows "no connections found"
  # even when online), with iwd as the Wi-Fi BACKEND. NM owns IP config (DHCP/DNS) and MANAGES
  # wlan0; iwd does the 802.11 association. Credentials live in an NM keyfile so they show up in
  # Steam's network UI. iwd must NOT do its own netconfig here (EnableNetworkConfiguration=false),
  # else it fights NM for DHCP on wlan0 (the conflict that forced the old iwd-direct model).
  #
  # The static NM conf comes from the OVERLAY (rsync'd above): conf.d/20-wifi-backend.conf
  # (wifi.backend=iwd). Here we only write the build-var-dependent bits: iwd regdom + the NM
  # connection keyfile.
  install -d -m 755 "${root}/etc/NetworkManager/conf.d"
  # iwd = backend only: keep regdom Country (5 GHz) but turn its own netconfig OFF.
  install -d -m 755 "${root}/etc/iwd"
  {
    echo "[General]"
    [ -n "${SD_WIFI_COUNTRY}" ] && echo "Country=${SD_WIFI_COUNTRY}"
    echo "EnableNetworkConfiguration=false"
  } > "${root}/etc/iwd/main.conf"
  # NM integrates DNS via systemd-resolved; point glibc at resolved's stub.
  ln -sf /run/systemd/resolve/stub-resolv.conf "${root}/etc/resolv.conf"

  # The ALARM base ships systemd-networkd ENABLED, but pocknix networking is
  # NetworkManager(+iwd): networkd manages no interfaces, so its enabled
  # wait-online blocks network-online.target for its full 120s timeout on EVERY
  # boot — stalling multi-user.target and everything ordered after it
  # (fancontrol, diag, decky all started ~2 minutes late; found on the RP5
  # bring-up, but every image paid it). systemd-resolved stays (NM uses it).
  chroot "${root}" systemctl disable systemd-networkd.service systemd-networkd.socket \
        systemd-networkd-wait-online.service \
        systemd-networkd-varlink.socket systemd-networkd-resolve-hook.socket \
        systemd-networkd-varlink-metrics.socket >/dev/null 2>&1 || true

  if [ -n "${SD_WIFI_SSID}" ]; then
    # Guard: a Wi-Fi SSID with no password silently ships an unusable image (the SSID is logged but
    # an empty PSK only surfaces as a boot-time association failure). Fail the build instead.
    [ -n "${SD_WIFI_PSK}" ] || die "SD_WIFI_SSID='${SD_WIFI_SSID}' is set but SD_WIFI_PSK is empty. Pass SD_WIFI_PSK='<password>' (note: 'sudo VAR=… make' must not drop it)."
    log "pre-seeding Wi-Fi (NetworkManager + iwd backend) for SSID '${SD_WIFI_SSID}'${SD_WIFI_COUNTRY:+, country ${SD_WIFI_COUNTRY}}"
    install -d -m 700 "${root}/etc/NetworkManager/system-connections"
    cat > "${root}/etc/NetworkManager/system-connections/${SD_WIFI_SSID}.nmconnection" <<EOF
[connection]
id=${SD_WIFI_SSID}
type=wifi
interface-name=wlan0
autoconnect=true

[wifi]
mode=infrastructure
ssid=${SD_WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${SD_WIFI_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
EOF
    chmod 600 "${root}/etc/NetworkManager/system-connections/${SD_WIFI_SSID}.nmconnection"

    # Provision the credential DIRECTLY into iwd (KnownNetwork) too. NetworkManager 1.56's iwd
    # backend does NOT hand the keyfile PSK to iwd — activation dead-ends at
    # need-auth/no-secrets ("No agents were available"), so wlan0 never associates on a clean flash.
    # With iwd holding the passphrase it autoconnects on its own and NM reflects the connection (so
    # Steam still sees Wi-Fi through NM). This is the project's original proven iwd-direct credential.
    # NOTE: filename is <SSID>.psk for plain-ASCII SSIDs; iwd hex-encodes names containing
    # non-alphanumerics (e.g. spaces) as '=<hex>.psk' — not handled here (uncommon for test SSIDs).
    install -d -m 700 "${root}/var/lib/iwd"
    cat > "${root}/var/lib/iwd/${SD_WIFI_SSID}.psk" <<EOF
[Security]
Passphrase=${SD_WIFI_PSK}
EOF
    chmod 600 "${root}/var/lib/iwd/${SD_WIFI_SSID}.psk"
    [ -z "${SD_WIFI_COUNTRY}" ] && warn "SD_WIFI_COUNTRY unset — world regdom; 5 GHz won't associate"
  fi

  # enable services for interaction/verification with no keyboard:
  #   sshd + iwd (wifi) + systemd-resolved (DNS), diag (boot report).
  #   seatd: gamescope's DRM backend needs a seat (no logind seat over SSH).
  #   inputplumber: gamepad -> Steam Input (DualSense) mapping.
  #   NetworkManager (front-end Steam talks to) + iwd (its wifi backend) BOTH run now.
  #   pocknix-expand-root: first-boot grow of root partition+fs to fill the card.
  # NOTE: the USB-C network gadget (ssh over USB) is intentionally gone — it showed as a phantom
  # "wired" connection in Steam, and the port is dual-role (DTS data-role="dual"), so leaving it
  # free lets the USB-C port act as a host for peripherals (keyboard, storage, …).
  #   upower: battery %/time-to-empty for Steam's gamepadui (it reads battery only via the UPower
  #   D-Bus API) + Plasma. D-Bus-activated anyway, but enable it so it's up before Steam's first query.
  #   udisks2: Steam's Storage page enumerates FORMATTABLE external drives (the microSD "Format"
  #   flow) over the UDisks2 D-Bus API (CSystemStorageDeviceManagerLinux). It's D-Bus-activatable
  #   but Steam's storage manager enumerates once at startup and does not recover if UDisks2 comes
  #   up late, so a disabled udisks2 = empty format list even though the card is present. Enable it
  #   so it is running before Steam inits. (Mounted ext4 libraries still show via our automount; this
  #   is only the raw-drive/format list.) The UDisks2 polkit grant is in 50-pocknix-deck.rules.
  chroot "${root}" systemctl enable sshd iwd NetworkManager systemd-resolved seatd inputplumber \
        bluetooth upower udisks2 \
        pocknix-diag.service pocknix-expand-root.service \
        pocknix-lavd.service pocknix-gamescope-rt.service \
        >/dev/null 2>&1 || true
  # audio server (PipeWire) as per-user services — start in the autologin/session user.
  # WirePlumber applies the device UCM (shipped by the device BSP) automatically.
  # pocknix-proton-prep: watches for Steam downloading/updating Proton 11 ARM and keeps the compat
  # tool usable, so the first download needs no reboot (pocknix-steam also runs it at game start).
  chroot "${root}" systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service \
        pocknix-proton-prep.service \
        >/dev/null 2>&1 || true
  # Emulation first-login seeding: ~/ROMs tree + ES-DE/RetroArch/SRM configs (pocknix-emulation;
  # idempotent oneshot, never blocks the session).
  chroot "${root}" systemctl --global enable pocknix-roms-init.service >/dev/null 2>&1 || true
}

main() {
  ensure_kernel_in_rootfs
  # firmware is now installed into the rootfs by build-image.sh (make build)

  local root_mib img_mib boot_end
  root_mib=$(( $(du -sm "${ROOTFS_DIR}" | cut -f1) + SD_SLACK_MIB ))
  img_mib=$(( 1 + SD_BOOT_MIB + root_mib + 1 ))
  boot_end=$(( 1 + SD_BOOT_MIB ))
  log "creating ${OUT} (~${img_mib} MiB = ${SD_BOOT_MIB} boot + ${root_mib} root)"
  mkdir -p "${IMAGE_DIR}"
  rm -f "${OUT}"
  truncate -s "${img_mib}M" "${OUT}"

  log "partitioning (GPT: ${SD_BOOT_PARTNAME} fat32 + ${ROOT_LABEL} ext4)"
  parted -s "${OUT}" mklabel gpt
  parted -s "${OUT}" mkpart "${SD_BOOT_PARTNAME}" fat32 1MiB "${boot_end}MiB"
  parted -s "${OUT}" mkpart "${ROOT_LABEL}"        ext4  "${boot_end}MiB" 100%
  parted -s "${OUT}" set 1 legacy_boot on
  # Deterministic partition GUIDs (see SD_*_PARTUUID in config/pocknix.conf):
  # the arm-efi grub.cfg and the fstab below pin these, so an internal install's
  # identical POCKNIX_ROOT name/label can never steal the SD boot's root.
  sgdisk --partition-guid=1:"${SD_BOOT_PARTUUID}" \
         --partition-guid=2:"${SD_ROOT_PARTUUID}" "${OUT}" >/dev/null

  LOOP="$(losetup --show -fP "${OUT}")"
  log "loop: ${LOOP}"
  udevadm settle 2>/dev/null || sleep 1
  [ -e "${LOOP}p1" ] && [ -e "${LOOP}p2" ] || die "loop partitions ${LOOP}p1/p2 did not appear"

  mkfs.vfat -F 32 -n "${SD_FAT_LABEL}" "${LOOP}p1" >/dev/null
  mkfs.ext4 -F -q -L "${ROOT_LABEL}" "${LOOP}p2"

  MNT="$(mktemp -d)"
  # boot partition: KERNEL (+ md5); arm-efi additionally GRUB + dtbs + abl
  # payload; qcom-abl additionally the ROCKNIX ABL install kit
  mount "${LOOP}p1" "${MNT}"
  cp "${KERNEL_IMG}" "${MNT}/KERNEL"
  ( cd "${MNT}" && md5sum KERNEL > KERNEL.md5 )
  case "${BOOTLOADER}" in
    arm-efi)  populate_arm_efi_boot "${MNT}" ;;
    qcom-abl) populate_qcom_abl_boot "${MNT}" ;;
  esac
  sync; umount "${MNT}"
  # root partition: the rootfs
  mount "${LOOP}p2" "${MNT}"
  log "copying rootfs -> root partition (takes a bit)"
  rsync -aHAX --numeric-ids "${ROOTFS_DIR}/" "${MNT}/"
  firstboot_config "${MNT}"
  # Ownership gate: nothing outside /home should be owned by the host build user (uid/gid 1000 =
  # 'alarm' in the rootfs). A stray host-owned path here means a host->rootfs copy leaked ownership
  # (see the --chown=root:root rsyncs above) — which silently breaks privilege-bounded services like
  # systemd-timedated (couldn't write /etc/localtime -> timezone changes had no effect). Fail loudly.
  leaked="$(find "${MNT}" -xdev \( -uid 1000 -o -gid 1000 \) ! -path "${MNT}/home/*" -print -quit)"
  [ -z "${leaked}" ] || die "host-owned (uid/gid 1000) path leaked into the image: ${leaked#${MNT}} — a host->rootfs rsync needs --chown=root:root"
  sync; umount "${MNT}"; rmdir "${MNT}"; MNT=""
  losetup -d "${LOOP}"; LOOP=""
  trap - EXIT

  ok "SD image ready -> ${OUT}  ($(du -h "${OUT}" | cut -f1))"
  echo
  log "Flash it (DOUBLE-CHECK the device with lsblk first!):"
  echo "    sudo dd if=${OUT} of=/dev/sdX bs=4M conv=fsync status=progress"
  log "Then insert into the device (${DEVICE_PRETTY:-${DEVICE}}) and boot. root password: ${SD_ROOT_PASSWORD}"
  log "Internal ROCKNIX is untouched; remove the SD to boot it again."
}
main "$@"
