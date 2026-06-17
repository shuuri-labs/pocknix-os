#!/usr/bin/env bash
# bootstrap.sh — download, verify and extract the Arch Linux ARM aarch64 base
# rootfs into build/rootfs. Idempotent: re-running rebuilds a clean rootfs.

source "$(dirname "$0")/lib.sh"
need_linux
need_root bootstrap
for t in curl tar rsync; do need_tool "$t"; done

mkdir -p "${CACHE_DIR}"
tarball="${CACHE_DIR}/${ALARM_TARBALL}"
url="${ALARM_MIRROR}/${ALARM_TARBALL}"

if [ ! -f "${tarball}" ]; then
  log "downloading ALARM rootfs: ${url}"
  curl -fL --retry 3 -o "${tarball}" "${url}"
else
  log "using cached ALARM rootfs: ${tarball}"
fi

# verify (hermetic builds: set POCKNIX_ALARM_SHA256)
if [ -n "${POCKNIX_ALARM_SHA256}" ]; then
  log "verifying sha256"
  echo "${POCKNIX_ALARM_SHA256}  ${tarball}" | sha256sum -c - \
    || die "ALARM tarball sha256 mismatch — refusing to build"
  ok "checksum verified"
else
  warn "POCKNIX_ALARM_SHA256 is unset — build is NOT reproducible (pin it for releases)"
fi

log "extracting rootfs -> ${ROOTFS_DIR}"
[ -d "${ROOTFS_DIR}" ] && { chroot_umount "${ROOTFS_DIR}" || true; rm -rf "${ROOTFS_DIR}"; }
mkdir -p "${ROOTFS_DIR}"
# bsdtar preserves the ALARM tarball's xattrs/ownership better than gnu tar
if have bsdtar; then
  bsdtar -xpf "${tarball}" -C "${ROOTFS_DIR}"
else
  tar -xpf "${tarball}" -C "${ROOTFS_DIR}" --numeric-owner
fi

maybe_install_qemu "${ROOTFS_DIR}"
ok "base rootfs ready -> ${ROOTFS_DIR}"
