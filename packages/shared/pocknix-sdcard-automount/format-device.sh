#!/bin/bash
# format-device.sh — pkexec'd as root by steamos-format-device when the Storage UI formats a card.
# mmcblk ONLY: Valve's original also accepts /dev/sd[a-z], but on the RP6 `sda` is the INTERNAL UFS
# OS disk. Owner is stamped 1000:1000 (SteamOS's deck, not our local 1001) so a fresh card stays
# writable on a genuine SteamOS device; sdcard-mount.sh's idmap presents it back as 1001 here.
# Derived from Valve jupiter-hw-support's /usr/lib/hwsupport/format-device.sh.

set -uo pipefail

STEAMOS_UID=1000
DEV=""
LABEL=""
VALIDATE=0

# The Steam client's flag set drifts across beta versions, so act on the flags we know and
# silently ignore the rest rather than erroring the whole format.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)        DEV="${2:-}"; shift 2 ;;
        --device=*)      DEV="${1#*=}"; shift ;;
        --label)         LABEL="${2:-}"; shift 2 ;;
        --label=*)       LABEL="${1#*=}"; shift ;;
        --owner)         STEAMOS_UID="${2%%:*}"; shift 2 ;;
        --owner=*)       v="${1#*=}"; STEAMOS_UID="${v%%:*}"; shift ;;
        --validate)      VALIDATE=1; shift ;;
        --version)       echo "1"; exit 0 ;;
        --force|--skip-validation|--full|--quick|--enable-duplicate-detection) shift ;;
        *)               shift ;;
    esac
done

die() { echo "format-device.sh: $*" >&2; exit 1; }

[[ -n "$DEV" ]] || die "no --device given"

case "$DEV" in
    /dev/mmcblk[0-9]|/dev/mmcblk[0-9][0-9])                 DISK="$DEV"; PART="${DEV}p1" ;;
    /dev/mmcblk[0-9]p[0-9]*|/dev/mmcblk[0-9][0-9]p[0-9]*)   DISK="${DEV%p[0-9]*}"; PART="${DISK}p1" ;;
    *) die "refusing to format '$DEV': only the microSD slot (/dev/mmcblkN) may be formatted" ;;
esac

[[ -b "$DISK" ]] || die "not a block device: $DISK"

# /flash is checked as well as /: a card can hold the boot partition without hosting /.
mount_disk() {
    local src pk
    src="$(findmnt -no SOURCE "$1" 2>/dev/null)"
    src="${src%%\[*}"       # btrfs SOURCE carries a [/subvol] suffix lsblk cannot resolve
    [[ -b "$src" ]] || return 0
    pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"
    [[ -n "$pk" ]] && echo "/dev/${pk}" || echo "$src"
}
for mp in / /flash; do
    [[ "$(mount_disk "$mp")" == "$DISK" ]] && die "refusing to format $DISK: the running system booted from it"
done

if [[ "$VALIDATE" == "1" ]]; then
    [[ -r "$DISK" ]] || die "cannot read $DISK"
    echo "format-device.sh: $DISK is a formattable microSD"
    exit 0
fi

echo "format-device.sh: formatting $DISK (partition $PART, label '${LABEL}', owner ${STEAMOS_UID})"

# parted/mkfs fail on a busy device, and our automount likely has p1 mounted.
for mp in $(lsblk -nro NAME "$DISK" | tail -n +2); do
    umount -l "/dev/${mp}" 2>/dev/null || true
done

# A service in a private mount ns (e.g. Decky's loader) keeps an inherited copy of the mount and
# holds the device busy; the init-ns umount above does not propagate into private namespaces.
declare -A ns_seen
for proc in /proc/[0-9]*; do
    ns="$(readlink "${proc}/ns/mnt" 2>/dev/null)" || continue
    [[ -n "${ns_seen[$ns]:-}" ]] && continue
    ns_seen[$ns]=1
    grep -q "${DISK##*/}" "${proc}/mountinfo" 2>/dev/null || continue
    for mp in $(lsblk -nro NAME "$DISK" | tail -n +2); do
        nsenter -t "${proc#/proc/}" -m umount -A -l "/dev/${mp}" 2>/dev/null || true
    done
done

wipefs -a "$DISK" >/dev/null 2>&1 || true
dd if=/dev/zero of="$DISK" bs=1M count=8 conv=fsync 2>/dev/null || die "failed to clear $DISK"

parted --script "$DISK" mklabel gpt mkpart primary ext4 0% 100% || die "parted failed on $DISK"

partprobe "$DISK" 2>/dev/null || true
udevadm settle --timeout=10 2>/dev/null || true
for _ in $(seq 1 20); do [[ -b "$PART" ]] && break; sleep 0.25; done
[[ -b "$PART" ]] || die "partition $PART did not appear"

# casefold is what makes Steam's case-insensitive library paths work on the card.
MKFS_OPTS=(-F -m 0 -O casefold -E "root_owner=${STEAMOS_UID}:${STEAMOS_UID}")
[[ -n "$LABEL" ]] && MKFS_OPTS+=(-L "$LABEL")
mkfs.ext4 "${MKFS_OPTS[@]}" "$PART" || die "mkfs.ext4 failed on $PART"

# mkfs emits no add uevent, so the automount rule needs a manual re-trigger.
udevadm trigger --action=add "$PART" 2>/dev/null || true

echo "format-device.sh: done"
exit 0
