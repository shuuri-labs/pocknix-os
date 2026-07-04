#!/bin/bash
# sdcard-mount.sh — pocknix port of Valve's SteamOS SD-card automount helper.
#
# Called by 99-pocknix-sdcard-automount.rules (via systemd-run) on insert/removal of an ext4
# mmcblk partition. It mounts the card under /run/media, hands ownership to the Steam session
# user, and — the part a bare udev mount rule is missing — tells the RUNNING Steam client about
# it over its pipe with steam://addlibraryfolder, so the card actually shows up in the gamescope
# UI's Storage list. Without that IPC call Steam never surfaces a live-inserted card.
#
# Adapted from Valve's /usr/lib/hwsupport/sdcard-mount.sh. Two pocknix-specific changes vs Valve:
#   1. Session user is uid 1001 (`deck`), NOT Valve's 1000 — on pocknix uid 1000 is `alarm`.
#   2. The steam:// URL is sent via the NATIVE ARM client (~/.local/share/Steam/steamrtarm64/steam);
#      Valve's ./.steam/root/ubuntu12_32/steam is the x86 bootstrap and won't execute on aarch64.

usage()
{
    echo "Usage: $0 {add|remove} device_name (e.g. mmcblk0p1)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

ACTION=$1
DEVBASE=$2
DEVICE="/dev/${DEVBASE}"

# The Steam session user (pocknix: deck = 1001; NOT Valve's 1000 = alarm here).
STEAM_UID=1001
STEAM_HOME=/home/deck
# Native ARM client + its runtime libs (see /usr/bin/pocknix-steam for the same contract).
STEAM_CLIENT_DIR="${STEAM_HOME}/.local/share/Steam/steamrtarm64"
STEAM_LDLP="${STEAM_CLIENT_DIR}:${STEAM_HOME}/.local/share/Steam/lib/aarch64-linux-gnu"

MOUNT_LOCK="/var/run/sdcard-mount.lock"
if [[ -e $MOUNT_LOCK && $(pgrep -F "$MOUNT_LOCK") ]]; then
    echo "$MOUNT_LOCK is active: ignoring action $ACTION"
    # Do not return success: it could leave the transient unit 'started' without doing the mount.
    exit 1
fi

# See if this drive is already mounted, and if so where
MOUNT_POINT=$(mount | grep -F "${DEVICE}" | awk '{ print $3 }')

# From https://gist.github.com/HazCod/da9ec610c3d50ebff7dd5e7cac76de05
urlencode()
{
    [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

# Send a steam:// URL to the running client for the deck user, in that user's systemd session so it
# inherits the right DBus/pipe env. No-op (best effort) if Steam isn't running.
notify_steam()
{
    local url_action=$1   # addlibraryfolder | removelibraryfolder
    local url=$2
    if pgrep -x "steam" > /dev/null; then
        systemd-run -M ${STEAM_UID}@ --user --collect --wait \
            /bin/sh -c "cd '${STEAM_CLIENT_DIR}' && LD_LIBRARY_PATH='${STEAM_LDLP}' ./steam steam://${url_action}/${url}" \
            || echo "notify_steam: steam://${url_action} send failed (non-fatal)"
    fi
}

do_mount()
{
    if [[ -n ${MOUNT_POINT} ]]; then
        echo "Warning: ${DEVICE} is already mounted at ${MOUNT_POINT}"
        exit 1
    fi

    # Get info for this drive: $ID_FS_LABEL, and $ID_FS_TYPE
    dev_json=$(lsblk -o PATH,LABEL,FSTYPE --json -- "$DEVICE" | jq '.blockdevices[0]')
    ID_FS_LABEL=$(jq -r '.label | select(type == "string")' <<< "$dev_json")
    ID_FS_TYPE=$(jq -r '.fstype | select(type == "string")' <<< "$dev_json")

    # Figure out a mount point to use, namespaced under the deck user like modern SteamOS.
    LABEL=${ID_FS_LABEL}
    if [[ -z "${LABEL}" ]]; then
        LABEL=${DEVBASE}
    elif /bin/grep -qF " /run/media/deck/${LABEL} " /etc/mtab; then
        # Already in use, make a unique one
        LABEL+="-${DEVBASE}"
    fi
    MOUNT_POINT="/run/media/deck/${LABEL}"

    echo "Mount point: ${MOUNT_POINT}"

    /bin/mkdir -p -- "${MOUNT_POINT}"

    # Global mount options
    OPTS="rw,noatime"

    # Steam only handles ext4 external drives for now (matches what its "Format" produces), so that's
    # all we automount — same guard as Valve.
    if [[ ${ID_FS_TYPE} != "ext4" ]]; then
       echo "Error mounting ${DEVICE}: wrong fstype: ${ID_FS_TYPE} - ${dev_json}"
       /bin/rmdir -- "${MOUNT_POINT}" 2>/dev/null
       exit 2
    fi

    if ! /bin/mount -o "${OPTS}" -- "${DEVICE}" "${MOUNT_POINT}"; then
        echo "Error mounting ${DEVICE} (status = $?)"
        /bin/rmdir -- "${MOUNT_POINT}"
        exit 1
    fi

    chown ${STEAM_UID}:${STEAM_UID} -- "${MOUNT_POINT}"

    echo "**** Mounted ${DEVICE} at ${MOUNT_POINT} ****"

    notify_steam addlibraryfolder "$(urlencode "${MOUNT_POINT}")"
}

do_unmount()
{
    notify_steam removelibraryfolder "$(urlencode "${MOUNT_POINT}")"

    if [[ -z ${MOUNT_POINT} ]]; then
        echo "Warning: ${DEVICE} is not mounted"
    else
        /bin/umount -l -- "${DEVICE}"
        echo "**** Unmounted ${DEVICE}"
    fi

    # Reap empty orphan mount points under /run/media/deck.
    for f in /run/media/deck/* ; do
        [[ -e $f ]] || continue
        if [[ -n $(/usr/bin/find "$f" -maxdepth 0 -type d -empty) ]]; then
            if ! /bin/grep -qF " $f " /etc/mtab; then
                echo "**** Removing mount point $f"
                /bin/rmdir "$f"
            fi
        fi
    done
}

case "${ACTION}" in
    add)
        do_mount
        ;;
    remove)
        do_unmount
        ;;
    *)
        usage
        ;;
esac
