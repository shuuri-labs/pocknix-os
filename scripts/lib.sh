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
  cp -f /etc/resolv.conf "${root}/etc/resolv.conf"
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
