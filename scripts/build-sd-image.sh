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
    chmod +x "${root}/usr/local/bin/pocknix-usbgadget" "${root}/usr/local/bin/pocknix-diag" 2>/dev/null || true
  fi

  # Wi-Fi pre-seed — provision iwd DIRECTLY. iwd is the backend and owns autoconnect;
  # an NM keyfile profile never reaches iwd (the credentials don't get handed off), so
  # we write iwd's own known-network file + main.conf (regulatory Country, needed for
  # 5 GHz; EnableNetworkConfiguration so iwd does its own DHCP) and hand wlan0 to iwd
  # by marking it unmanaged in NetworkManager.
  if [ -n "${SD_WIFI_SSID}" ]; then
    log "pre-seeding Wi-Fi (iwd) for SSID '${SD_WIFI_SSID}'${SD_WIFI_COUNTRY:+, country ${SD_WIFI_COUNTRY}}"
    install -d -m 755 "${root}/etc/iwd"
    {
      echo "[General]"
      [ -n "${SD_WIFI_COUNTRY}" ] && echo "Country=${SD_WIFI_COUNTRY}"
      echo "EnableNetworkConfiguration=true"
      echo ""
      echo "[Network]"
      echo "NameResolvingService=systemd"
    } > "${root}/etc/iwd/main.conf"
    # iwd pushes DHCP DNS to systemd-resolved; point glibc at resolved's stub.
    ln -sf /run/systemd/resolve/stub-resolv.conf "${root}/etc/resolv.conf"
    install -d -m 700 "${root}/var/lib/iwd"
    printf '[Security]\nPassphrase=%s\n' "${SD_WIFI_PSK}" > "${root}/var/lib/iwd/${SD_WIFI_SSID}.psk"
    chmod 600 "${root}/var/lib/iwd/${SD_WIFI_SSID}.psk"
    # let iwd own wlan0 end-to-end (autoconnect + DHCP); keep NM off it to avoid conflict
    cat > "${root}/etc/NetworkManager/conf.d/10-unmanage-gadget.conf" <<EOF
[keyfile]
unmanaged-devices=interface-name:usb0;interface-name:gadget;interface-name:ncm0;interface-name:wlan0
EOF
    [ -z "${SD_WIFI_COUNTRY}" ] && warn "SD_WIFI_COUNTRY unset — world regdom; 5 GHz won't associate"
  elif [ -n "${SD_WIFI_COUNTRY}" ]; then
    install -d -m 755 "${root}/etc/iwd"
    printf '[General]\nCountry=%s\n' "${SD_WIFI_COUNTRY}" > "${root}/etc/iwd/main.conf"
  fi

  # enable services for interaction/verification with no keyboard:
  #   sshd + iwd (wifi) + systemd-resolved (DNS), usbgadget (ssh over USB-C), diag (boot report).
  chroot "${root}" systemctl enable sshd iwd systemd-resolved \
        pocknix-usbgadget.service pocknix-diag.service >/dev/null 2>&1 || true
  if [ -n "${SD_WIFI_SSID}" ]; then
    # iwd owns wifi end-to-end incl. its own DHCP. NetworkManager, if running, registers
    # as iwd's netconfig agent and then refuses the unmanaged wlan0 -> IP never gets set.
    # So keep NM OFF when we've iwd-preseeded.
    chroot "${root}" systemctl disable NetworkManager >/dev/null 2>&1 || true
  else
    chroot "${root}" systemctl enable NetworkManager >/dev/null 2>&1 || true
  fi
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
