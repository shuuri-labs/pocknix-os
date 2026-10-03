#!/usr/bin/env bash
# build-sd-image.sh - flashable SD image, laid out like ROCKNIX's so the device's ABL boots it:
#   p1 fat32 "${SD_BOOT_PARTNAME}": /KERNEL (+ EFI/ and boot/grub/ with the dtbs on arm-efi)
#   p2 btrfs "${ROOT_LABEL}": subvols @ @home @snapshots @pacman-cache @var-log
# The kernel mounts root by PARTUUID (no initramfs) and boots the btrfs DEFAULT subvol: the
# cmdline and fstab must never name one, that is what lets pocknix-rollback switch roots.
# Layout rationale and traps: pocknix-notes dev/building.md "SD image assembly".
# Prereqs: `sudo make build` + `make kernel`. Run as root (loop + mount).

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

# `make build` may predate the kernel, so the modules land here (idempotent).
ensure_kernel_in_rootfs() {
  if [ -f "${KOUT}/soc" ] && [ "$(cat "${KOUT}/soc")" != "${SOC}" ]; then
    die "${KOUT} was built for SOC=$(cat "${KOUT}/soc"), not ${SOC} — run 'make kernel DEVICE=${DEVICE}' first"
  fi
  if [ -d "${KOUT}/modroot/lib/modules" ]; then
    local kver; kver="$(cat "${KOUT}/kernelrelease" 2>/dev/null)"
    log "syncing pocknix modules (${kver}) into rootfs + removing generic kernel"
    chroot "${ROOTFS_DIR}" pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
    # host-owned build output; rsync -a would carry uid 1000 into the rootfs (gate in main)
    rsync -a --chown=root:root "${KOUT}/modroot/lib/modules/" "${ROOTFS_DIR}/usr/lib/modules/"
    [ -n "${kver}" ] && chroot "${ROOTFS_DIR}" depmod "${kver}" 2>/dev/null || true
  else
    warn "no kernel modules in ${KOUT} — rootfs may lack matching modules"
  fi
}

# ABL kit at the FAT root on both boot styles: stock Android mounts this FAT, so a factory
# device is provisioned from the SD alone. Inert at boot.
copy_abl_kit() {
  local mnt="$1" kit="${ROOTFS_DIR}/usr/share/pocknix/bootloader/rocknix_abl"
  [ -f "${kit}/abl_signed-${SOC^^}.elf" ] \
    || die "${kit#${ROOTFS_DIR}}/abl_signed-${SOC^^}.elf missing from the rootfs — is pocknix-bootloader-${SOC} built and installed? (make packages + make build)"
  rsync -a "${kit}" "${mnt}/"
}

# GRUB + cfg + grubenv come from pocknix-bootloader-${SOC} in the rootfs (its alpm hook
# refreshes /flash from the same tree); only the dtbs come from the kernel build.
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
# pocknix-os
# The root line names NO subvol on purpose: the kernel boots the btrfs DEFAULT subvolume,
# which is how pocknix-rollback switches roots without touching boot config.
# noatime + zstd:1 keep the device's own writes cheap; the image was populated at zstd:3.
PARTUUID=${SD_ROOT_PARTUUID}  /                  btrfs  rw,noatime,compress=zstd:1                       0 0
PARTUUID=${SD_ROOT_PARTUUID}  /home              btrfs  rw,noatime,compress=zstd:1,subvol=@home          0 0
PARTUUID=${SD_ROOT_PARTUUID}  /.snapshots        btrfs  rw,noatime,compress=zstd:1,subvol=@snapshots     0 0
PARTUUID=${SD_ROOT_PARTUUID}  /var/cache/pacman  btrfs  rw,noatime,compress=zstd:1,subvol=@pacman-cache  0 0
PARTUUID=${SD_ROOT_PARTUUID}  /var/log           btrfs  rw,noatime,compress=zstd:1,subvol=@var-log       0 0
PARTUUID=${SD_BOOT_PARTUUID}  /flash             vfat   rw,noatime,nofail                                0 2
EOF
  echo "pocknix" > "${root}/etc/hostname"
  # ALARM ships no /etc/localtime; without the symlink, timezone changes in the UI have nothing
  # to land in and silently stay UTC.
  chroot "${root}" ln -sfn "/usr/share/zoneinfo/${SD_TIMEZONE:-UTC}" /etc/localtime

  if [ -d "${POCKNIX_ROOT}/overlay" ]; then
    log "installing overlay (diag + autologin + helpers)"
    # --chown is REQUIRED: rsync -a would stamp / and /etc with the host user's uid 1000, and
    # capability-bounded services (timedated) then cannot write there. The gate in main catches it.
    rsync -a --chown=root:root "${POCKNIX_ROOT}/overlay/" "${root}/"
    chmod +x "${root}/usr/local/bin/pocknix-diag" \
             "${root}/usr/local/bin/pocknix-expand-root" \
             "${root}/usr/local/bin/pocknix-volumed" "${root}/usr/local/bin/pocknix-powerd" \
             "${root}/usr/local/bin/pocknix-oobe-marker" 2>/dev/null || true
  fi

  # PipeWire refuses to run as root and Proton's bwrap wants a normal user. uid 1001 stays:
  # installed devices carry it (1000 was ALARM's login) and the SD idmap keys on it.
  # The overlay already placed /home/deck, so useradd -m reuses it and the chown below owns it.
  log "creating non-root 'deck' session user (audio + Proton need a normal user)"
  chroot "${root}" useradd -m -u 1001 -U -s /bin/bash -G video,render,input,audio,seat,wheel deck 2>/dev/null || true
  echo "deck:${SD_DECK_PASSWORD:-${SD_ROOT_PASSWORD}}" | chroot "${root}" chpasswd
  # ALARM's default login (password `alarm`, wheel) is a known root credential once SSH is on.
  chroot "${root}" userdel -r alarm 2>/dev/null || true
  # XDG dirs exist from first boot, before xdg-user-dirs writes its config at first login.
  for d in Desktop Documents Downloads Music Pictures Videos; do
    mkdir -p "${root}/home/deck/${d}"
  done
  # also owns the Steam tree build-image.sh pre-extracted here (root-owned until now)
  chroot "${root}" chown -R deck:deck /home/deck
  # The on-device launcher has no network fallback: a rootfs without the baked client would
  # ship a Steam session that fails on first launch.
  [ -x "${root}/home/deck/.local/share/Steam/steamrtarm64/steam" ] \
    || die "Steam client not pre-extracted in the rootfs (/home/deck/.local/share/Steam) — run 'sudo make build' first."

  chroot "${root}" systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
  # root-side helpers: deck can write neither binfmt_misc nor its own rtprio (SteamOS model)
  chroot "${root}" systemctl enable pocknix-fancontrol.service pocknix-fex-binfmt.service \
        pocknix-volumed.service pocknix-gamescope-rt.service pocknix-powerd.service 2>/dev/null || true
  chroot "${root}" systemctl enable pocknix-decky-sync.service pocknix-decky-loader.service 2>/dev/null || true
  # pocknix-flathub.service is deliberately NOT enabled: the NM dispatcher starts it once a link
  # is up; a boot-transaction start would stall multi-user.target for the >300 MB flatpak seed
  # (and at boot it always failed on DNS anyway).
  chroot "${root}" systemctl enable pocknix-waydroid-tuning.service 2>/dev/null || true

  # Steam manages Wi-Fi only through NetworkManager; iwd is its backend and must not run its
  # own netconfig or it fights NM for DHCP (dev/steam.md "Wi-Fi"). The static NM conf is in
  # the overlay; only the build-variable bits are written here.
  install -d -m 755 "${root}/etc/NetworkManager/conf.d"
  # Country stays for 5 GHz regdom
  install -d -m 755 "${root}/etc/iwd"
  {
    echo "[General]"
    [ -n "${SD_WIFI_COUNTRY}" ] && echo "Country=${SD_WIFI_COUNTRY}"
    echo "EnableNetworkConfiguration=false"
  } > "${root}/etc/iwd/main.conf"
  # NM hands DNS to systemd-resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf "${root}/etc/resolv.conf"

  # ALARM enables networkd; managing no interface here, its wait-online holds
  # network-online.target for the full 120 s on every boot. resolved stays (NM uses it).
  chroot "${root}" systemctl disable systemd-networkd.service systemd-networkd.socket \
        systemd-networkd-wait-online.service \
        systemd-networkd-varlink.socket systemd-networkd-resolve-hook.socket \
        systemd-networkd-varlink-metrics.socket >/dev/null 2>&1 || true

  if [ -n "${SD_WIFI_SSID}" ]; then
    # an empty PSK only surfaces as an association failure on the device
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

    # NM 1.56's iwd backend never hands the keyfile PSK to iwd (activation dead-ends at
    # need-auth), so iwd gets the passphrase directly and NM reflects its connection.
    # Plain-ASCII SSIDs only: iwd hex-encodes other names as =<hex>.psk.
    install -d -m 700 "${root}/var/lib/iwd"
    cat > "${root}/var/lib/iwd/${SD_WIFI_SSID}.psk" <<EOF
[Security]
Passphrase=${SD_WIFI_PSK}
EOF
    chmod 600 "${root}/var/lib/iwd/${SD_WIFI_SSID}.psk"
    [ -z "${SD_WIFI_COUNTRY}" ] && warn "SD_WIFI_COUNTRY unset — world regdom; 5 GHz won't associate"
  fi

  # seatd: gamescope's DRM backend needs a seat. upower + udisks2 are D-Bus-activatable but
  # Steam queries battery and enumerates drives once at startup and never retries, so they
  # must already be running. fstrim: root is mounted without discard. No USB gadget on purpose
  # (dev/building.md).
  chroot "${root}" systemctl enable iwd NetworkManager systemd-resolved seatd inputplumber \
        bluetooth upower udisks2 fstrim.timer \
        pocknix-diag.timer pocknix-expand-root.service pocknix-oobe-marker.service \
        pocknix-lavd.service pocknix-gamescope-rt.service \
        >/dev/null 2>&1 || true
  # A well-known password is baked in, so sshd ships off. ALARM enables it: disable, not skip.
  if [ "${SD_SSH:-off}" = on ]; then
    warn "SD_SSH=on — this image accepts SSH logins with the baked-in password"
    chroot "${root}" systemctl enable sshd >/dev/null 2>&1 || true
  else
    for u in sshd.service sshd.socket; do
      chroot "${root}" systemctl disable "${u}" >/dev/null 2>&1 || true
    done
  fi
  chroot "${root}" systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service \
        pocknix-proton-prep.service \
        >/dev/null 2>&1 || true
}

main() {
  ensure_kernel_in_rootfs

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
  # Fixed GUIDs: grub.cfg and fstab pin them, so an internal install with the same partition
  # name and label can never steal the SD boot's root.
  sgdisk --partition-guid=1:"${SD_BOOT_PARTUUID}" \
         --partition-guid=2:"${SD_ROOT_PARTUUID}" "${OUT}" >/dev/null

  LOOP="$(losetup --show -fP "${OUT}")"
  log "loop: ${LOOP}"
  udevadm settle 2>/dev/null || sleep 1
  [ -e "${LOOP}p1" ] && [ -e "${LOOP}p2" ] || die "loop partitions ${LOOP}p1/p2 did not appear"

  mkfs.vfat -F 32 -n "${SD_FAT_LABEL}" "${LOOP}p1" >/dev/null
  mkfs.btrfs -f -q -L "${ROOT_LABEL}" "${LOOP}p2"   # defaults: DUP metadata (SD cards eat metadata), 16K nodes

  MNT="$(mktemp -d)"
  mount "${LOOP}p1" "${MNT}"
  cp "${KERNEL_IMG}" "${MNT}/KERNEL"
  ( cd "${MNT}" && md5sum KERNEL > KERNEL.md5 )
  case "${BOOTLOADER}" in
    arm-efi)  populate_arm_efi_boot "${MNT}" ;;
    qcom-abl) populate_qcom_abl_boot "${MNT}" ;;
  esac
  sync; umount "${MNT}"

  # @ becomes the fs DEFAULT subvol, which is what the kernel boots (see the header).
  # zstd:3 here costs the device nothing: the level is encoder-side only.
  log "creating btrfs subvolumes (@ @home @snapshots @pacman-cache @var-log)"
  mount -o compress=zstd:3 "${LOOP}p2" "${MNT}"
  local sv
  for sv in @ @home @snapshots @pacman-cache @var-log; do
    btrfs subvolume create "${MNT}/${sv}" >/dev/null
  done
  btrfs subvolume set-default "$(btrfs inspect-internal rootid "${MNT}/@")" "${MNT}"
  umount "${MNT}"
  # one rsync below lands each path in its subvol
  mount -o compress=zstd:3,subvol=@ "${LOOP}p2" "${MNT}"
  mkdir -p "${MNT}/home" "${MNT}/.snapshots" "${MNT}/var/cache/pacman" "${MNT}/var/log"
  for sv in @home:home @snapshots:.snapshots @pacman-cache:var/cache/pacman @var-log:var/log; do
    mount -o "compress=zstd:3,subvol=${sv%%:*}" "${LOOP}p2" "${MNT}/${sv#*:}"
  done

  log "copying rootfs -> root partition (takes a bit)"
  rsync -aHAX --numeric-ids "${ROOTFS_DIR}/" "${MNT}/"
  # No sync dbs in the image: the build's unsigned localrepo db is "not newer" than the live
  # one on first -Sy, so pacman keeps it and pairs it with the live .sig = "signature is invalid".
  rm -f "${MNT}/var/lib/pacman/sync/"*.db "${MNT}/var/lib/pacman/sync/"*.db.sig
  firstboot_config "${MNT}"
  # Ownership gate: a host->rootfs copy without --chown leaks uid 1000 and silently breaks
  # capability-bounded services. Each subvol is its own st_dev, so -xdev needs every one
  # listed; @home is skipped on purpose.
  local gate
  for gate in "${MNT}" "${MNT}/var/log" "${MNT}/var/cache/pacman" "${MNT}/.snapshots"; do
    leaked="$(find "${gate}" -xdev \( -uid 1000 -o -gid 1000 \) -print -quit)"
    [ -z "${leaked}" ] || die "host-owned (uid/gid 1000) path leaked into the image: ${leaked#${MNT}} — a host->rootfs rsync needs --chown=root:root"
  done
  # The size formula uses uncompressed du and trusts zstd to outweigh DUP metadata; catch it
  # here rather than ENOSPC on first boot.
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
