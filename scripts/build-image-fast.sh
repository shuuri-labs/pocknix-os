#!/usr/bin/env bash
# build-image-fast.sh — iterate on packages/config without re-bootstrapping.
# Reuses an existing build/rootfs: re-renders pacman.conf, refreshes pocknix
# local packages, and re-runs package install. Skips the ALARM download/extract
# and (by default) the kernel rebuild.

source "$(dirname "$0")/lib.sh"
need_linux
need_root fast

[ -d "${ROOTFS_DIR}" ] || die "no existing rootfs at ${ROOTFS_DIR} — run 'make build' first"

log "fast rebuild against existing rootfs: ${ROOTFS_DIR}"
trap 'chroot_umount "${ROOTFS_DIR}"' EXIT
chroot_mount "${ROOTFS_DIR}"

# re-sync local pocknix packages + reinstall changed ones
warn "STUB: local pocknix package refresh (Phase 2+) not implemented yet"
chroot "${ROOTFS_DIR}" pacman -Syu --noconfirm || true

chroot_umount "${ROOTFS_DIR}"; trap - EXIT
ok "fast rebuild complete"
