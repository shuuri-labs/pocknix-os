#!/bin/bash
# format-device.sh — pocknix port of Valve's SteamOS SD-card formatter (jupiter-hw-support's
# /usr/lib/hwsupport/format-device.sh). The Steam Deck Storage UI's "Format SD Card" shells out to
# /usr/bin/steamos-polkit-helpers/steamos-format-device, which pkexec's THIS script as root. It
# wipes the card, lays a single GPT ext4 partition (with casefold, like SteamOS), and hands it back;
# our udev automount then remounts it and registers it with Steam.
#
# Adapted from Valve's format-device.sh, with three pocknix-specific changes:
#   1. mmcblk ONLY. Valve also formats /dev/sd[a-z] (USB). On the RP6 `sda` is the INTERNAL UFS OS
#      disk, so accepting sd* here would let the UI nuke the running system. We hard-refuse anything
#      that is not /dev/mmcblkN (the microSD slot), and additionally refuse the disk backing `/`.
#   2. Owner is fixed at 1000:1000 (SteamOS's `deck`), NOT pocknix's local deck=1001. Every SteamOS
#      device numbers deck=1000, so stamping the ext4 root_owner=1000 keeps a freshly formatted card
#      portable to a real SteamOS device; sdcard-mount.sh's idmap presents it back as our 1001 here.
#      (Formatting to our local 1001 would make the card unwritable on a genuine SteamOS device.)
#   3. No f3probe fake-card validation (that tool isn't shipped, and it is destructive-slow); the
#      --validate pass does lightweight sanity checks only.

set -uo pipefail

STEAMOS_UID=1000                 # on-disk owner to stamp; see note 2
DEV=""
LABEL=""
VALIDATE=0

# Tolerant arg parse: the Steam client's flag set drifts across beta versions (it currently sends
# `--validate --device DEV --label L --force --enable-duplicate-detection`), so accept the ones we
# act on and silently ignore the rest rather than erroring the whole format.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)        DEV="${2:-}"; shift 2 ;;
        --device=*)      DEV="${1#*=}"; shift ;;
        --label)         LABEL="${2:-}"; shift 2 ;;
        --label=*)       LABEL="${1#*=}"; shift ;;
        --owner)         STEAMOS_UID="${2%%:*}"; shift 2 ;;   # honor an explicit owner if asked
        --owner=*)       v="${1#*=}"; STEAMOS_UID="${v%%:*}"; shift ;;
        --validate)      VALIDATE=1; shift ;;
        --version)       echo "1"; exit 0 ;;
        --force|--skip-validation|--full|--quick|--enable-duplicate-detection) shift ;;
        *)               shift ;;   # unknown: ignore
    esac
done

die() { echo "format-device.sh: $*" >&2; exit 1; }

[[ -n "$DEV" ]] || die "no --device given"

# Normalize to the whole disk + its first partition, and enforce the mmcblk-only guard (note 1).
# Accept either the disk (/dev/mmcblk0) or a partition (/dev/mmcblk0p1); reject everything else.
case "$DEV" in
    /dev/mmcblk[0-9]|/dev/mmcblk[0-9][0-9])                 DISK="$DEV"; PART="${DEV}p1" ;;
    /dev/mmcblk[0-9]p[0-9]*|/dev/mmcblk[0-9][0-9]p[0-9]*)   DISK="${DEV%p[0-9]*}"; PART="${DISK}p1" ;;
    *) die "refusing to format '$DEV': only the microSD slot (/dev/mmcblkN) may be formatted" ;;
esac

[[ -b "$DISK" ]] || die "not a block device: $DISK"

# Belt-and-suspenders: never format the disk that backs the root filesystem.
ROOT_SRC="$(findmnt -no SOURCE / 2>/dev/null)"
ROOT_DISK="$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null)"
if [[ -n "$ROOT_DISK" && "/dev/${ROOT_DISK}" == "$DISK" ]]; then
    die "refusing to format $DISK: it backs the running system"
fi

if [[ "$VALIDATE" == "1" ]]; then
    # Pre-flight the client runs before the real format. No writes.
    [[ -r "$DISK" ]] || die "cannot read $DISK"
    echo "format-device.sh: $DISK is a formattable microSD"
    exit 0
fi

echo "format-device.sh: formatting $DISK (partition $PART, label '${LABEL}', owner ${STEAMOS_UID})"

# Unmount anything from this disk first (our automount likely has p1 mounted), else parted/mkfs fail.
for mp in $(lsblk -nro NAME "$DISK" | tail -n +2); do
    umount -l "/dev/${mp}" 2>/dev/null || true
done

# Scrub old signatures + partition table (primary and, via parted's relabel, the backup GPT).
wipefs -a "$DISK" >/dev/null 2>&1 || true
dd if=/dev/zero of="$DISK" bs=1M count=8 conv=fsync 2>/dev/null || die "failed to clear $DISK"

# Single GPT partition spanning the card, ext4-flagged, properly aligned.
parted --script "$DISK" mklabel gpt mkpart primary ext4 0% 100% || die "parted failed on $DISK"

# Wait for the kernel + udev to publish the new partition node.
partprobe "$DISK" 2>/dev/null || true
udevadm settle --timeout=10 2>/dev/null || true
for _ in $(seq 1 20); do [[ -b "$PART" ]] && break; sleep 0.25; done
[[ -b "$PART" ]] || die "partition $PART did not appear"

# Format ext4 like SteamOS: no reserved blocks (-m 0), casefold (Steam library case-insensitivity),
# and root_owner stamped to the SteamOS deck uid/gid so the card is portable (see note 2).
MKFS_OPTS=(-F -m 0 -O casefold -E "root_owner=${STEAMOS_UID}:${STEAMOS_UID}")
[[ -n "$LABEL" ]] && MKFS_OPTS+=(-L "$LABEL")
mkfs.ext4 "${MKFS_OPTS[@]}" "$PART" || die "mkfs.ext4 failed on $PART"

# Nudge udev so 99-pocknix-sdcard-automount.rules mounts the fresh partition and tells Steam.
udevadm trigger --action=add "$PART" 2>/dev/null || true

echo "format-device.sh: done"
exit 0
