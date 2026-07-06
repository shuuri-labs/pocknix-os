#!/usr/bin/env bash
# Shared helpers for pocknix-os build scripts. Source this first:
#   source "$(dirname "$0")/lib.sh"
# It resolves POCKNIX_ROOT, loads config/pocknix.conf, and defines utilities.

set -euo pipefail

# --- locate project root (parent of scripts/) ------------------------------
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POCKNIX_ROOT="$(cd "${_lib_dir}/.." && pwd)"

# shellcheck source=../config/pocknix.conf
source "${POCKNIX_ROOT}/config/pocknix.conf"

# --- device profile + per-SoC kernel pins -----------------------------------
# The device profile (devices/<name>/profile.conf) declares everything device-
# specific: SoC, partition labels/names, kernel cmdline, firmware source,
# device packages. It sets SOC, which selects the per-SoC kernel tree and its
# source pins (kernel/<soc>/kernel.conf).
if [ ! -f "${POCKNIX_ROOT}/devices/${DEVICE}/profile.conf" ]; then
  printf 'error: unknown DEVICE=%s — available: %s\n' \
    "${DEVICE}" "$(ls "${POCKNIX_ROOT}/devices" 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi
source "${POCKNIX_ROOT}/devices/${DEVICE}/profile.conf"
source "${POCKNIX_ROOT}/kernel/${SOC}/kernel.conf"

# Paths derived from the profile (must come after it):
: "${DEVICE_DIR:=${POCKNIX_ROOT}/devices/${DEVICE}}"
: "${KERNEL_DIR:=${POCKNIX_ROOT}/kernel/${SOC}}"
: "${ROCKNIX_DEVICE_DIR:=${ROCKNIX_PROJECT_DIR}/devices/${ROCKNIX_SOC}}"

# --- logging ---------------------------------------------------------------
_c_blue=$'\033[1;34m'; _c_grn=$'\033[1;32m'; _c_yel=$'\033[1;33m'
_c_red=$'\033[1;31m';  _c_rst=$'\033[0m'
log()  { printf '%s==>%s %s\n'  "$_c_blue" "$_c_rst" "$*"; }
ok()   { printf '%s ok%s %s\n'  "$_c_grn"  "$_c_rst" "$*"; }
warn() { printf '%swarn%s %s\n' "$_c_yel"  "$_c_rst" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$_c_red" "$_c_rst" "$*" >&2; exit 1; }

# --- guards ----------------------------------------------------------------
need_root() { [ "$(id -u)" -eq 0 ] || die "must run as root (chroot/mount needed): try 'sudo make $1'"; }
need_linux() { [ "$(uname -s)" = "Linux" ] || die "the image build must run on a Linux host (current: $(uname -s)). Use a Linux box or container."; }
have()     { command -v "$1" >/dev/null 2>&1; }
need_tool(){ have "$1" || die "missing required tool: $1"; }

# --- chroot mount/teardown (idempotent) ------------------------------------
chroot_mount() {
  local root="$1"
  mount --bind /dev      "${root}/dev"
  mount --bind /dev/pts  "${root}/dev/pts"
  mount -t proc  proc    "${root}/proc"
  mount -t sysfs sys     "${root}/sys"
  mount -t tmpfs tmpfs   "${root}/run"
  chroot_resolv "${root}"
}

# Give the chroot a working /etc/resolv.conf. On systemd-resolved hosts (Fedora,
# Arch, etc.) the host /etc/resolv.conf is a stub pointing at 127.0.0.53, which
# resolves nothing inside the chroot — so prefer the real upstream resolvers, and
# fall back to public DNS if only a localhost stub is available.
chroot_resolv() {
  local root="$1" src
  for src in /run/systemd/resolve/resolv.conf /etc/resolv.conf; do
    if [ -e "$src" ]; then
      rm -f "${root}/etc/resolv.conf"
      cp -L "$src" "${root}/etc/resolv.conf"
      break
    fi
  done
  if ! grep -E '^[[:space:]]*nameserver' "${root}/etc/resolv.conf" 2>/dev/null | grep -qv '127\.'; then
    warn "no usable upstream resolver found in chroot — falling back to public DNS (1.1.1.1)"
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "${root}/etc/resolv.conf"
  fi
}
chroot_umount() {
  local root="$1"
  for m in run sys proc dev/pts dev; do
    mountpoint -q "${root}/${m}" && umount -lf "${root}/${m}" || true
  done
}

# install qemu-user-static into the rootfs when cross-building from x86_64
maybe_install_qemu() {
  local root="$1"
  [ "$(uname -m)" = "aarch64" ] && return 0   # native, nothing to do
  [ -f "${QEMU_AARCH64_STATIC}" ] || die "cross-building on $(uname -m) needs ${QEMU_AARCH64_STATIC} (install qemu-user-static + binfmt)"
  install -Dm755 "${QEMU_AARCH64_STATIC}" "${root}${QEMU_AARCH64_STATIC}"
}
