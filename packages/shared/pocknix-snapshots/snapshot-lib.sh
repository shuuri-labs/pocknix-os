# snapshot-lib.sh — shared by the pocknix-snapshots hooks + CLIs (sourced, not executed).
# Everything here must stay cheap: the pre hook runs inside every pacman transaction.

SNAP_DIR=/.snapshots
SNAP_CONF=/etc/pocknix/snapshots.conf

# defaults, overridable via ${SNAP_CONF} (pacman backup= file)
POCKNIX_SNAPSHOT_KEEP=5              # pre-update snapshots to retain
POCKNIX_SNAPSHOT_MIN_FREE_MIB=1024   # below this: skip the snapshot, never block the update
POCKNIX_SNAPSHOT_WARN_FREE_MIB=5120  # below this: the QAM UI shows a low-space warning
[ -f "${SNAP_CONF}" ] && . "${SNAP_CONF}"

# Snapshots are supported when / is btrfs AND the @snapshots subvol is mounted.
# Both are false in the image-build chroot and on pre-btrfs (ext4) installs, so
# every hook/CLI entry point starts here and silently no-ops (same trick as the
# kernel hooks' `mountpoint -q /flash`).
pocknix_snap_supported() {
  [ "$(findmnt -no FSTYPE / 2>/dev/null)" = btrfs ] || return 1
  mountpoint -q "${SNAP_DIR}" || return 1
  return 0
}

snap_free_mib() { df --output=avail -m "${SNAP_DIR}" 2>/dev/null | tail -1 | tr -d ' '; }

snap_next_id() {  # next zero-padded snapshot id (0001, 0002, ...)
  local last
  last="$(ls "${SNAP_DIR}" 2>/dev/null | grep -E '^[0-9]{4}$' | sort -n | tail -1)"
  printf '%04d' $(( 10#${last:-0} + 1 ))
}

snap_root_dev() {  # device backing /, without findmnt's [/subvol] suffix
  local src; src="$(findmnt -no SOURCE /)"
  echo "${src%%\[*}"
}

snap_mounted_subvol() {  # toplevel path of the subvol mounted at / (e.g. "@", "@rb-...")
  local src sub; src="$(findmnt -no SOURCE /)"
  sub="${src#*\[/}"; sub="${sub%\]}"
  [ "${sub}" != "${src}" ] && echo "${sub}" || echo ""
}

snap_default_subvol() {  # toplevel path of the fs default subvol (what boots next)
  btrfs subvolume get-default / 2>/dev/null | sed -n 's/.* path //p'
}
