#!/usr/bin/env bash
# build-sd-image.sh — assemble a flashable SD image to boot-test pocknix WITHOUT
# touching internal ROCKNIX. Layout mirrors ROCKNIX's SD for the SoC's
# BOOTLOADER style so the device's existing (ROCKNIX-flashed) ABL boots it:
#
#   GPT  p1  fat32  name "${SD_BOOT_PARTNAME}" (label ${SD_FAT_LABEL})  -> /KERNEL [+ GRUB]
#        p2  btrfs  name "${ROOT_LABEL}"                                -> Arch base rootfs
#
# qcom-abl (sm8550): ABL loads /KERNEL (Android boot image, cmdline baked in).
# arm-efi  (sm8250): the factory ABL chainloads /EFI/BOOT/bootaa64.efi ->
#   /boot/grub/grub.cfg -> "linux /KERNEL" (raw Image) + "devicetree
#   /boot/grub/<board>.dtb"; the FAT additionally carries EFI/ and boot/grub/
#   (cfg + grubenv + dtbs). ROCKNIX sets legacy_boot on p1 for BOTH styles (no esp flag).
# Either way our kernel mounts its root directly by PARTUUID (fixed SD GUIDs; no
# initramfs — UFS/btrfs are built in). ROCKNIX also puts a SYSTEM squashfs on
# the FAT; we don't need it.
#
# The root is btrfs with subvolumes (@ / @home / @snapshots / @pacman-cache /
# @var-log). The OS boots the filesystem's DEFAULT subvolume — neither the
# kernel cmdline nor the fstab root line names a subvol — so rollback is
# `btrfs subvolume set-default <other-root> + reboot` with zero boot-config
# changes on either bootloader style (pocknix-snapshots package).
#
# Prereqs: `sudo make build` (rootfs) + `make kernel` (KERNEL). Run as root (loop+mount).
# Flash:   sudo dd if=build/image/<soc>/pocknix-<soc>-sd.img of=/dev/sdX bs=4M conv=fsync status=progress

source "$(dirname "$0")/lib.sh"
need_linux
need_root sd-image
for t in parted sgdisk mkfs.vfat mkfs.btrfs btrfs losetup rsync chroot truncate du; do need_tool "$t"; done   # sgdisk: gptfdisk pkg

KERNEL_IMG="${IMAGE_DIR}/KERNEL"
KOUT="${KERNEL_BUILD_DIR}/out"   # per-SoC (set in lib.sh)
OUT="${IMAGE_DIR}/pocknix-${SOC}-sd.img"   # one image per SoC family -> name it so

[ -f "${KERNEL_IMG}" ] || die "no ${KERNEL_IMG} — run 'make kernel' first"
[ -d "${ROOTFS_DIR}" ] || die "no rootfs at ${ROOTFS_DIR} — run 'sudo make build' first"

LOOP=""; MNT=""
cleanup() {
  # -R: the root mount carries the subvol mounts (@home etc.) beneath it
  [ -n "${MNT}" ] && mountpoint -q "${MNT}" && umount -R "${MNT}" 2>/dev/null || true
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

# The ABL install kit at the FAT root, where ROCKNIX's images carry it: stock
# Android mounts this FAT, so a factory device can be provisioned from the SD
# alone. Inert at boot. Both boot styles carry it - qcom-abl has no other way
# in, arm-efi needs it for boards whose factory ABL lacks usable UEFI.
copy_abl_kit() {
  local mnt="$1" kit="${ROOTFS_DIR}/usr/share/pocknix/bootloader/rocknix_abl"
  [ -f "${kit}/abl_signed-${SOC^^}.elf" ] \
    || die "${kit#${ROOTFS_DIR}}/abl_signed-${SOC^^}.elf missing from the rootfs — is pocknix-bootloader-${SOC} built and installed? (make packages + make build)"
  rsync -a "${kit}" "${mnt}/"
}

# arm-efi boot partition contents beyond /KERNEL: GRUB + grub.cfg/grubenv +
# every board dtb + the ROCKNIX ABL kit. All of it except the dtbs is
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
  copy_abl_kit "${mnt}"
}

populate_qcom_abl_boot() { copy_abl_kit "$1"; }

firstboot_config() {
  local root="$1"
  log "configuring first boot (root login, fstab, sshd_config, network, hostname)"
  echo "root:${SD_ROOT_PASSWORD}" | chroot "${root}" chpasswd
  cat > "${root}/etc/fstab" <<EOF
# pocknix-os test image
# noatime: no software here needs atime; dropping atime write-backs cuts flash writes (SteamOS/ROCKNIX do the same).
# The root line names NO subvol on purpose: the kernel mounts the btrfs DEFAULT
# subvolume, which is how pocknix-rollback switches roots without touching boot
# config. The other subvols are toplevel-relative, unaffected by set-default.
# zstd:1 not :3 for the device's own writes (cheaper encoder). The level is
# encoder-side only, so the image's :3 extents keep reading back unchanged.
PARTUUID=${SD_ROOT_PARTUUID}  /                  btrfs  rw,noatime,compress=zstd:1                       0 0
PARTUUID=${SD_ROOT_PARTUUID}  /home              btrfs  rw,noatime,compress=zstd:1,subvol=@home          0 0
PARTUUID=${SD_ROOT_PARTUUID}  /.snapshots        btrfs  rw,noatime,compress=zstd:1,subvol=@snapshots     0 0
PARTUUID=${SD_ROOT_PARTUUID}  /var/cache/pacman  btrfs  rw,noatime,compress=zstd:1,subvol=@pacman-cache  0 0
PARTUUID=${SD_ROOT_PARTUUID}  /var/log           btrfs  rw,noatime,compress=zstd:1,subvol=@var-log       0 0
PARTUUID=${SD_BOOT_PARTUUID}  /flash             vfat   rw,noatime,nofail                                0 2
EOF
  echo "pocknix" > "${root}/etc/hostname"
  # Default timezone: the ALARM base ships NO /etc/localtime, so libc (and thus the SteamOS/Plasma
  # clock) silently falls back to UTC and changing the zone in the UI "has no effect" — there's no
  # file for it to land in. Ship a default symlink (overridable via SD_TIMEZONE); the user can change
  # it in the OOBE / Settings (deck is authorised via overlay 50-pocknix-deck.rules -> timedate1).
  chroot "${root}" ln -sfn "/usr/share/zoneinfo/${SD_TIMEZONE:-UTC}" /etc/localtime

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
             "${root}/usr/local/bin/pocknix-expand-root" \
             "${root}/usr/local/bin/pocknix-volumed" "${root}/usr/local/bin/pocknix-powerd" 2>/dev/null || true
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
  chroot "${root}" systemctl enable pocknix-fancontrol.service pocknix-fex-binfmt.service \
        pocknix-volumed.service pocknix-gamescope-rt.service pocknix-powerd.service 2>/dev/null || true
  # Decky Loader (QAM plugins, incl. Pocknix Control): seed deck's ~/homebrew at boot, then run
  # the loader under FEX in its private-binfmt namespace (see packages/shared/pocknix-decky).
  chroot "${root}" systemctl enable pocknix-decky-sync.service pocknix-decky-loader.service 2>/dev/null || true
  # pocknix-flathub.service is deliberately NOT enabled: pocknix-desktop's NM dispatcher hook
  # (50-pocknix-flathub) starts it when a link comes up. At boot it always failed (no DNS yet).
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
  #   iwd (wifi) + systemd-resolved (DNS), diag (boot report).
  #   sshd is deliberately NOT here — see the SD_SSH block below.
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
  #   fstrim.timer (weekly): root ext4 is mounted without `discard`, so nothing tells the FTL which
  #   blocks are free and write amplification climbs for the device's life. Arch doesn't preset it.
  chroot "${root}" systemctl enable iwd NetworkManager systemd-resolved seatd inputplumber \
        bluetooth upower udisks2 fstrim.timer \
        pocknix-diag.service pocknix-expand-root.service \
        pocknix-lavd.service pocknix-gamescope-rt.service \
        >/dev/null 2>&1 || true
  # SSH ships OFF: the image bakes in a well-known password, so a listening sshd
  # is a standing exposure on any network the device joins. The ALARM rootfs enables
  # sshd itself, so it must be disabled here, not merely left unenabled.
  if [ "${SD_SSH:-off}" = on ]; then
    warn "SD_SSH=on — this image accepts SSH logins with the baked-in password"
    chroot "${root}" systemctl enable sshd >/dev/null 2>&1 || true
  else
    for u in sshd.service sshd.socket; do
      chroot "${root}" systemctl disable "${u}" >/dev/null 2>&1 || true
    done
  fi
  # audio server (PipeWire) as per-user services — start in the autologin/session user.
  # WirePlumber applies the device UCM (shipped by the device BSP) automatically.
  # pocknix-proton-prep: watches for Steam downloading/updating the ARM Protons and keeps their
  # compat tools usable, so the first download needs no reboot (pocknix-steam also runs it at
  # game start).
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

  log "partitioning (GPT: ${SD_BOOT_PARTNAME} fat32 + ${ROOT_LABEL} btrfs)"
  parted -s "${OUT}" mklabel gpt
  parted -s "${OUT}" mkpart "${SD_BOOT_PARTNAME}" fat32 1MiB "${boot_end}MiB"
  parted -s "${OUT}" mkpart "${ROOT_LABEL}"        btrfs "${boot_end}MiB" 100%
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
  mkfs.btrfs -f -q -L "${ROOT_LABEL}" "${LOOP}p2"   # defaults: DUP metadata (SD cards eat metadata), 16K nodes

  MNT="$(mktemp -d)"
  # boot partition: KERNEL (+ md5) plus the ROCKNIX ABL kit on both styles;
  # arm-efi additionally GRUB + grubenv + the board dtbs
  mount "${LOOP}p1" "${MNT}"
  cp "${KERNEL_IMG}" "${MNT}/KERNEL"
  ( cd "${MNT}" && md5sum KERNEL > KERNEL.md5 )
  case "${BOOTLOADER}" in
    arm-efi)  populate_arm_efi_boot "${MNT}" ;;
    qcom-abl) populate_qcom_abl_boot "${MNT}" ;;
  esac
  sync; umount "${MNT}"

  # root partition: subvolume skeleton, then the OS subvol (@) becomes the fs
  # DEFAULT — the kernel cmdline/fstab never name a subvol, so rollback is just
  # set-default elsewhere + reboot (see pocknix-snapshots).
  # Populate stays zstd:3 while the shipped fstab is zstd:1 — this pass runs once on
  # the build host, so the better ratio costs the device nothing.
  log "creating btrfs subvolumes (@ @home @snapshots @pacman-cache @var-log)"
  mount -o compress=zstd:3 "${LOOP}p2" "${MNT}"
  local sv
  for sv in @ @home @snapshots @pacman-cache @var-log; do
    btrfs subvolume create "${MNT}/${sv}" >/dev/null
  done
  btrfs subvolume set-default "$(btrfs inspect-internal rootid "${MNT}/@")" "${MNT}"
  umount "${MNT}"
  # mount the whole tree so the single rootfs rsync below lands each path in its subvol
  mount -o compress=zstd:3,subvol=@ "${LOOP}p2" "${MNT}"
  mkdir -p "${MNT}/home" "${MNT}/.snapshots" "${MNT}/var/cache/pacman" "${MNT}/var/log"
  for sv in @home:home @snapshots:.snapshots @pacman-cache:var/cache/pacman @var-log:var/log; do
    mount -o "compress=zstd:3,subvol=${sv%%:*}" "${LOOP}p2" "${MNT}/${sv#*:}"
  done

  log "copying rootfs -> root partition (takes a bit)"
  rsync -aHAX --numeric-ids "${ROOTFS_DIR}/" "${MNT}/"
  # Ship no sync dbs: the build ones hold the LOCALREPO's UNSIGNED pocknix.db, and a
  # device whose first -Sy finds the live db "not newer" keeps those bytes while
  # fetching the live .sig -> "signature is invalid" on first update (bit a fresh
  # locked image). Deleted from the IMAGE only; ROOTFS_DIR keeps them for make snapshot.
  rm -f "${MNT}/var/lib/pacman/sync/"*.db "${MNT}/var/lib/pacman/sync/"*.db.sig
  firstboot_config "${MNT}"
  # Ownership gate: nothing outside /home should be owned by the host build user (uid/gid 1000 =
  # 'alarm' in the rootfs). A stray host-owned path here means a host->rootfs copy leaked ownership
  # (see the --chown=root:root rsyncs above) — which silently breaks privilege-bounded services like
  # systemd-timedated (couldn't write /etc/localtime -> timezone changes had no effect). Fail loudly.
  # Each subvolume is its own st_dev, so -xdev stops at their boundaries: sweep every mounted
  # subvol except @home (deck/uid-1000 content there is expected — no -path exclusion needed).
  local gate
  for gate in "${MNT}" "${MNT}/var/log" "${MNT}/var/cache/pacman" "${MNT}/.snapshots"; do
    leaked="$(find "${gate}" -xdev \( -uid 1000 -o -gid 1000 \) -print -quit)"
    [ -z "${leaked}" ] || die "host-owned (uid/gid 1000) path leaked into the image: ${leaked#${MNT}} — a host->rootfs rsync needs --chown=root:root"
  done
  # Sizing guard: the truncate formula above still uses du-of-rootfs (uncompressed). zstd:3
  # normally buys back far more than DUP metadata costs; if a change flips that, catch it at
  # build time instead of shipping an image that ENOSPCs on first boot.
  local free_kib
  free_kib="$(df --output=avail -k "${MNT}" | tail -1 | tr -d ' ')"
  [ "${free_kib}" -ge $(( 512 * 1024 )) ] \
    || die "btrfs root has only $(( free_kib / 1024 )) MiB free after populate (< 512 MiB) — raise SD_SLACK_MIB or check compression"
  sync; umount -R "${MNT}"; rmdir "${MNT}"; MNT=""
  losetup -d "${LOOP}"; LOOP=""
  trap - EXIT

  ok "SD image ready -> ${OUT}  ($(du -h "${OUT}" | cut -f1))"
  echo
  log "Flash it (DOUBLE-CHECK the device with lsblk first!):"
  echo "    sudo dd if=${OUT} of=/dev/sdX bs=4M conv=fsync status=progress"
  log "Then insert into the device (${DEVICE_PRETTY:-${DEVICE}}) and boot. root password: ${SD_ROOT_PASSWORD}"
  [ "${SD_SSH:-off}" = on ] || log "SSH is OFF in this image (build with SD_SSH=on, or turn it on in Pocknix Tools)."
  log "Internal ROCKNIX is untouched; remove the SD to boot it again."
}
main "$@"
