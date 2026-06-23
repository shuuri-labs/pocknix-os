#!/usr/bin/env bash
# build-sd-image.sh — assemble a flashable SD image to boot-test pocknix on the RP6
# WITHOUT touching internal ROCKNIX. Layout mirrors ROCKNIX's qcom-abl SD so the
# device's existing ABL boots it:
#
#   GPT  p1  fat32  name "${SD_BOOT_PARTNAME}" (label ${SD_FAT_LABEL})  -> /KERNEL
#        p2  ext4   name "${ROOT_LABEL}"                                -> Arch base rootfs
#
# Boot path: ABL loads /KERNEL from the FAT; our kernel mounts root=PARTLABEL=
# ${ROOT_LABEL} directly (no initramfs — UFS/ext4 are built in). ROCKNIX also puts
# a SYSTEM squashfs on the FAT; we don't need it (plain ext4 root).
#
# Prereqs: `sudo make build` (rootfs) + `make kernel` (KERNEL). Run as root (loop+mount).
# Flash:   sudo dd if=build/image/pocknix-sd.img of=/dev/sdX bs=4M conv=fsync status=progress

source "$(dirname "$0")/lib.sh"
need_linux
need_root sd-image
for t in parted mkfs.vfat mkfs.ext4 losetup rsync chroot truncate du; do need_tool "$t"; done

KERNEL_IMG="${IMAGE_DIR}/KERNEL"
KOUT="${BUILD_DIR}/kernel/out"
OUT="${IMAGE_DIR}/pocknix-sd.img"

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
  if [ -d "${KOUT}/modroot/lib/modules" ]; then
    local kver; kver="$(cat "${KOUT}/kernelrelease" 2>/dev/null)"
    log "syncing pocknix modules (${kver}) into rootfs + removing generic kernel"
    chroot "${ROOTFS_DIR}" pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
    rsync -a "${KOUT}/modroot/lib/modules/" "${ROOTFS_DIR}/usr/lib/modules/"
    [ -n "${kver}" ] && chroot "${ROOTFS_DIR}" depmod "${kver}" 2>/dev/null || true
  else
    warn "no kernel modules in ${KOUT} — rootfs may lack matching modules"
  fi
}

firstboot_config() {
  local root="$1"
  log "configuring first boot (root login, fstab, ssh, network, hostname)"
  echo "root:${SD_ROOT_PASSWORD}" | chroot "${root}" chpasswd
  cat > "${root}/etc/fstab" <<EOF
# pocknix-os test image
PARTLABEL=${ROOT_LABEL}  /  ext4  rw,relatime  0 1
EOF
  echo "pocknix" > "${root}/etc/hostname"
  if [ -f "${root}/etc/ssh/sshd_config" ]; then
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "${root}/etc/ssh/sshd_config"
  fi

  # install the committed test-image overlay (usb gadget, diag dump, autologin, NM conf)
  if [ -d "${POCKNIX_ROOT}/overlay" ]; then
    log "installing overlay (usb-gadget + diag + autologin)"
    rsync -a "${POCKNIX_ROOT}/overlay/" "${root}/"
    chmod +x "${root}/usr/local/bin/pocknix-usbgadget" "${root}/usr/local/bin/pocknix-diag" \
             "${root}/usr/local/bin/pocknix-expand-root" "${root}/usr/local/bin/pocknix-fancontrol" \
             "${root}/usr/local/bin/pocknix-volumed" 2>/dev/null || true
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
  chroot "${root}" chown -R deck:deck /home/deck
  # PipeWire/WirePlumber for deck's session (global-enable so its --user units start on login).
  chroot "${root}" systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
  # Root services: RP6 fan curve + FEX-binfmt-off (deck can't write /proc/sys/fs/binfmt_misc) +
  # the volume-rocker handler (Steam shows the OSD but doesn't change volume on KEY_VOLUME*).
  chroot "${root}" systemctl enable pocknix-fancontrol.service pocknix-fex-binfmt-off.service \
        pocknix-volumed.service 2>/dev/null || true
  # Desktop (Plasma Mobile) session: register the Flathub remote on the first online boot so
  # Discover/flatpak can install apps. Harmless in game-only use (oneshot, no-op once added).
  chroot "${root}" systemctl enable pocknix-flathub.service 2>/dev/null || true

  # Wi-Fi pre-seed — SteamOS topology: NetworkManager is the FRONT-END (Steam's gamepadui manages
  # Wi-Fi ONLY through NM's D-Bus API — without it the setup wizard shows "no connections found"
  # even when online), with iwd as the Wi-Fi BACKEND. NM owns IP config (DHCP/DNS) and MANAGES
  # wlan0; iwd does the 802.11 association. Credentials live in an NM keyfile so they show up in
  # Steam's network UI. iwd must NOT do its own netconfig here (EnableNetworkConfiguration=false),
  # else it fights NM for DHCP on wlan0 (the conflict that forced the old iwd-direct model).
  #
  # The static NM confs come from the OVERLAY (rsync'd above): conf.d/20-wifi-backend.conf
  # (wifi.backend=iwd) + conf.d/10-unmanage-gadget.conf (usb0/gadget/ncm0 unmanaged, NOT wlan0).
  # Here we only write the build-var-dependent bits: iwd regdom + the NM connection keyfile.
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
  #   sshd + iwd (wifi) + systemd-resolved (DNS), usbgadget (ssh over USB-C), diag (boot report).
  #   seatd: gamescope's DRM backend needs a seat (no logind seat over SSH).
  #   inputplumber: gamepad -> Steam Input (DualSense) mapping.
  #   NetworkManager (front-end Steam talks to) + iwd (its wifi backend) BOTH run now.
  #   pocknix-expand-root: first-boot grow of root partition+fs to fill the card.
  chroot "${root}" systemctl enable sshd iwd NetworkManager systemd-resolved seatd inputplumber \
        pocknix-usbgadget.service pocknix-diag.service pocknix-expand-root.service \
        >/dev/null 2>&1 || true
  # audio server (PipeWire) as per-user services — start in the autologin/session user.
  # WirePlumber applies the AYN-Odin2 UCM (shipped by pocknix-bsp) automatically.
  chroot "${root}" systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service \
        >/dev/null 2>&1 || true
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

  LOOP="$(losetup --show -fP "${OUT}")"
  log "loop: ${LOOP}"
  udevadm settle 2>/dev/null || sleep 1
  [ -e "${LOOP}p1" ] && [ -e "${LOOP}p2" ] || die "loop partitions ${LOOP}p1/p2 did not appear"

  mkfs.vfat -F 32 -n "${SD_FAT_LABEL}" "${LOOP}p1" >/dev/null
  mkfs.ext4 -F -q -L "${ROOT_LABEL}" "${LOOP}p2"

  MNT="$(mktemp -d)"
  # boot partition: just our KERNEL (+ md5)
  mount "${LOOP}p1" "${MNT}"
  cp "${KERNEL_IMG}" "${MNT}/KERNEL"
  ( cd "${MNT}" && md5sum KERNEL > KERNEL.md5 )
  sync; umount "${MNT}"
  # root partition: the rootfs
  mount "${LOOP}p2" "${MNT}"
  log "copying rootfs -> root partition (takes a bit)"
  rsync -aHAX --numeric-ids "${ROOTFS_DIR}/" "${MNT}/"
  firstboot_config "${MNT}"
  sync; umount "${MNT}"; rmdir "${MNT}"; MNT=""
  losetup -d "${LOOP}"; LOOP=""
  trap - EXIT

  ok "SD image ready -> ${OUT}  ($(du -h "${OUT}" | cut -f1))"
  echo
  log "Flash it (DOUBLE-CHECK the device with lsblk first!):"
  echo "    sudo dd if=${OUT} of=/dev/sdX bs=4M conv=fsync status=progress"
  log "Then insert into the RP6 and boot. root password: ${SD_ROOT_PASSWORD}"
  log "Internal ROCKNIX is untouched; remove the SD to boot it again."
}
main "$@"
