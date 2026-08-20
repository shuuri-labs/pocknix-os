#!/bin/bash
# sdcard-mount.sh — udev-driven SD automount for the Steam session. Beyond mounting it must tell
# the RUNNING client over steam://addlibraryfolder, or a live-inserted card never appears in the
# Storage UI. Mounted with an ext4 idmap swapping SteamOS's deck uid 1000 for our 1001 so a card
# roams between pocknix and real SteamOS devices; a chown here would stamp 1001 on disk instead.
# Derived from Valve jupiter-hw-support's /usr/lib/hwsupport/sdcard-mount.sh.

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

# deck is 1001 on pocknix (uid 1000 is alarm); every SteamOS device numbers deck 1000.
STEAM_UID=1001
STEAMOS_UID=1000
STEAM_HOME=/home/deck
# Native ARM client: Valve's ubuntu12_32 bootstrap is x86 and will not exec on aarch64.
STEAM_CLIENT_DIR="${STEAM_HOME}/.local/share/Steam/steamrtarm64"
STEAM_LDLP="${STEAM_CLIENT_DIR}:${STEAM_HOME}/.local/share/Steam/lib/aarch64-linux-gnu"

MOUNT_LOCK="/var/run/sdcard-mount.lock"
if [[ -e $MOUNT_LOCK && $(pgrep -F "$MOUNT_LOCK") ]]; then
    echo "$MOUNT_LOCK is active: ignoring action $ACTION"
    # Do not return success: it could leave the transient unit 'started' without doing the mount.
    exit 1
fi

MOUNT_POINT=$(mount | grep -F "${DEVICE}" | awk '{ print $3 }')

urlencode()
{
    [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

# Run inside the deck user's systemd session so the client inherits the right DBus/pipe env.
notify_steam()
{
    local url_action=$1
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

    dev_json=$(lsblk -o PATH,LABEL,FSTYPE --json -- "$DEVICE" | jq '.blockdevices[0]')
    ID_FS_LABEL=$(jq -r '.label | select(type == "string")' <<< "$dev_json")
    ID_FS_TYPE=$(jq -r '.fstype | select(type == "string")' <<< "$dev_json")

    LABEL=${ID_FS_LABEL}
    if [[ -z "${LABEL}" ]]; then
        LABEL=${DEVBASE}
    elif /bin/grep -qF " /run/media/deck/${LABEL} " /etc/mtab; then
        LABEL+="-${DEVBASE}"
    fi
    MOUNT_POINT="/run/media/deck/${LABEL}"

    echo "Mount point: ${MOUNT_POINT}"

    /bin/mkdir -p -- "${MOUNT_POINT}"

    # Identity map except the two singletons that trade 1000 and 1001, so every other owner
    # (root-owned lost+found, etc.) passes through unchanged instead of becoming `nobody`.
    TAIL_START=$((STEAM_UID + 1))
    TAIL_COUNT=$((4294967295 - TAIL_START))
    IDMAP="u:0:0:${STEAMOS_UID} u:${STEAMOS_UID}:${STEAM_UID}:1 u:${STEAM_UID}:${STEAMOS_UID}:1 u:${TAIL_START}:${TAIL_START}:${TAIL_COUNT}"
    IDMAP+=" g:0:0:${STEAMOS_UID} g:${STEAMOS_UID}:${STEAM_UID}:1 g:${STEAM_UID}:${STEAMOS_UID}:1 g:${TAIL_START}:${TAIL_START}:${TAIL_COUNT}"
    OPTS="rw,noatime,X-mount.idmap=${IDMAP}"

    # Steam only handles ext4 external drives, which is what its own "Format" produces.
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
