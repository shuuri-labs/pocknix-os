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
# The device profile (devices/<name>/profile.conf) declares what differs per family: SoC,
# boot style, kernel cmdline, GPU sensor. It sets SOC, which selects the per-SoC kernel tree
# and its source pins (kernel/<soc>/kernel.conf).
if [ ! -f "${POCKNIX_ROOT}/devices/${DEVICE}/profile.conf" ]; then
  printf 'error: unknown DEVICE=%s — available: %s\n' \
    "${DEVICE}" "$(ls "${POCKNIX_ROOT}/devices" 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi
# Profile defaults that derive from the profile's own keys, so they run after it; a profile
# sets any of them to override. The SoC-neutral ones live in config/pocknix.conf instead,
# because a profile expands them (ROOT_LABEL in its cmdline) while it is being sourced, so a
# profile overrides those with a plain X=value.
profile_defaults() {
  : "${KERNEL_CMDLINE:=${KERNEL_CMDLINE_ROOT} ${KERNEL_CMDLINE_EXTRA}}"
  : "${DEVICE_BSP_PKG:=pocknix-bsp-${SOC}}"
  : "${DEVICE_META_PKG:=pocknix-device-${SOC}}"
  : "${KERNEL_PKG:=linux-pocknix-${SOC}}"
}
source "${POCKNIX_ROOT}/devices/${DEVICE}/profile.conf"
profile_defaults
source "${POCKNIX_ROOT}/kernel/${SOC}/kernel.conf"
# Per-SoC userspace compiler tuning: the tuned packages/soc PKGBUILDs read these
# (build-packages.sh injects them into every packages/soc and packages/gpu makepkg environment).
source "${POCKNIX_ROOT}/devices/${DEVICE}/tuning.conf"

# Paths derived from the profile (must come after it):
: "${DEVICE_DIR:=${POCKNIX_ROOT}/devices/${DEVICE}}"
: "${KERNEL_DIR:=${POCKNIX_ROOT}/kernel/${SOC}}"
: "${ROCKNIX_DEVICE_DIR:=${ROCKNIX_PROJECT_DIR}/devices/${ROCKNIX_SOC}}"
# Per-SoC pacman repo: tuned packages (mesa etc.) share pkgnames across SoCs
# with different binaries, so each SoC gets its own localrepo/published tree.
# packages/shared/* are byte-identical across SoCs: built once into the shared
# localrepo, published once as [pocknix-shared] (repo membership doubles as
# delivery targeting).
: "${LOCALREPO_DIR:=${BUILD_DIR}/localrepo/${SOC}}"
: "${LOCALREPO_SHARED_DIR:=${BUILD_DIR}/localrepo/shared}"
# Publish staging area (stage-repo.sh): a mirror of the LIVE repo with only the
# intended packages swapped in — publish-repo.sh publishes THIS, never the
# raw localrepo (which parallel sessions fill with unvalidated builds).
: "${STAGE_DIR:=${BUILD_DIR}/stage/${SOC}}"
# Which repo tree stage-repo.sh/publish-repo.sh operate on: the per-SoC
# [pocknix] tree (default) or the SoC-neutral [pocknix-shared] tree
# (make stage-shared / publish-shared). The db filename must equal the repo
# tag, hence REPO_NAME drives both the stanza and the *.db names.
: "${POCKNIX_REPO_SCOPE:=soc}"
if [ "${POCKNIX_REPO_SCOPE}" = "shared" ]; then
  REPO_NAME="pocknix-shared"; REPO_SEG="shared"
  REPO_LOCALREPO_DIR="${LOCALREPO_SHARED_DIR}"
  REPO_STAGE_DIR="${BUILD_DIR}/stage/shared"
else
  REPO_NAME="pocknix"; REPO_SEG="${SOC}"
  REPO_LOCALREPO_DIR="${LOCALREPO_DIR}"
  REPO_STAGE_DIR="${STAGE_DIR}"
fi
# Per-SoC kernel + image outputs, so switching families never forces a kernel rebuild
# or mixes one family's out/ with another's. (build/cache and build/rootfs stay shared:
# the cache is SoC-neutral downloads, the rootfs is wiped by bootstrap.sh on every build.)
: "${KERNEL_BUILD_DIR:=${BUILD_DIR}/kernel/${SOC}}"
: "${IMAGE_DIR:=${BUILD_DIR}/image/${SOC}}"

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

# --- package lists ---------------------------------------------------------
# awk $1, not sed 's/#.*//': sed keeps the whitespace before an inline comment and
# pacman then can't match the name.
# A variable as one family's build resolves it (pocknix.conf, its profile, the defaults), in a
# clean environment: everything assigns with ":=", so the selected DEVICE's values would win.
profile_get() {  # $1 = devices/<soc> dir, $2 = variable name
  env -i POCKNIX_ROOT="${POCKNIX_ROOT}" bash -c "$(declare -f profile_defaults)"'
    . "${POCKNIX_ROOT}/config/pocknix.conf" && . "$1/profile.conf" && profile_defaults && printf "%s" "${!2:-}"' sh "$1" "$2"
}

read_pkglist() {
  awk '{ sub(/#.*/, ""); if ($1 != "") print $1 }' "$1"
}

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

# --- pinned ALARM base ------------------------------------------------------
# Fetch + verify the ALARM base tarball into CACHE_DIR. One implementation for
# bootstrap.sh (rootfs) and build-packages.sh (build chroot), so the two bases cannot diverge.
fetch_alarm_tarball() {
  local tarball="${CACHE_DIR}/${ALARM_TARBALL}"
  mkdir -p "${CACHE_DIR}"
  if [ ! -f "${tarball}" ]; then
    log "downloading ALARM rootfs: ${POCKNIX_ALARM_TARBALL_URL}"
    curl -fL --retry 3 -o "${tarball}" "${POCKNIX_ALARM_TARBALL_URL}"
  else
    log "using cached ALARM rootfs: ${tarball}"
  fi
  if [ -n "${POCKNIX_ALARM_SHA256}" ]; then
    echo "${POCKNIX_ALARM_SHA256}  ${tarball}" | sha256sum -c - >/dev/null \
      || die "ALARM tarball sha256 mismatch — refusing to build"
    ok "ALARM tarball checksum verified"
  else
    warn "POCKNIX_ALARM_SHA256 is unset — build is NOT reproducible (pin it for releases)"
  fi
}

# --- kernel source + patch stack --------------------------------------------
# One implementation for build-kernel.sh and CI's apply check, so the check applies exactly
# what the build applies.
fetch_kernel_source() {  # $1 = dir to extract linux-${KERNEL_VERSION}/ into
  local tb="${CACHE_DIR}/linux-${KERNEL_VERSION}.tar.xz"
  mkdir -p "${CACHE_DIR}" "$1"
  if [ ! -f "${tb}" ]; then
    log "downloading kernel source: ${KERNEL_SOURCE_URL}"
    curl -fL --retry 3 -o "${tb}" "${KERNEL_SOURCE_URL}"
  else
    log "using cached kernel source: ${tb}"
  fi
  if [ -n "${KERNEL_SOURCE_SHA256}" ]; then
    echo "${KERNEL_SOURCE_SHA256}  ${tb}" | sha256sum -c - || die "kernel source sha256 mismatch"
    ok "kernel source checksum verified"
  else
    warn "KERNEL_SOURCE_SHA256 unset — build is NOT reproducible (pin it for releases)"
  fi
  log "extracting source -> $1/linux-${KERNEL_VERSION}"
  rm -rf "$1/linux-${KERNEL_VERSION}"
  tar -C "$1" -xf "${tb}"
}

# kernel/common goes last (its patches sit on SoC-dir prerequisites); kernel/<soc>/common-skip
# names common patches a SoC leaves out, the fallback when gating inside the patch can't work.
apply_kernel_patches() {  # $1 = source tree, $2 = kernel/<soc> dir
  local ksrc="$1" kdir="$2" d p n out skip="" gnu_patch=patch
  # Apple's patch rejects hunks GNU patch applies with fuzz. --forward fails a patch already
  # in the source instead of prompting to reverse it.
  [ "$(uname -s)" = Darwin ] && gnu_patch=gpatch
  need_tool "${gnu_patch}"
  [ -f "${kdir}/common-skip" ] && \
    skip="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "${kdir}/common-skip")"
  for d in "${kdir}"/patches/*/ "${POCKNIX_ROOT}/kernel/common/patches/"; do
    [ -d "${d}" ] || continue
    n=0
    for p in "${d}"*.patch; do
      [ -f "${p}" ] || continue
      if [ "${d}" = "${POCKNIX_ROOT}/kernel/common/patches/" ] && grep -qxF "${p##*/}" <<<"${skip}"; then
        log "  skipped ${p##*/} (${kdir##*/} common-skip)"; continue
      fi
      out="$("${gnu_patch}" --forward -p1 -d "${ksrc}" < "${p}" 2>&1)" \
        || die "patch failed to apply: ${p#"${POCKNIX_ROOT}"/}
${out}"
      n=$((n+1))
    done
    d="${d%/}"
    log "applied ${d#"${POCKNIX_ROOT}"/kernel/}: ${n} patches"
  done
}

# Render the base pacman.conf: with a pinned snapshot, the only package source
# is the frozen [pocknix-base] repo (ALARM's per-package .sig files are kept in
# the snapshot, so package SigLevel stays Required; the repo-add DB is unsigned,
# which DatabaseOptional permits). Without a pin: live ALARM. Shared
# by the rootfs and the build chroot so both always install from the SAME base.
render_base_pacman_conf() {
  local out="$1"
  if [ -n "${POCKNIX_BASE_SNAPSHOT}" ]; then
    # keep the template's [options] block, replace every repo with the snapshot
    sed '/^\[core\]$/,$d' "${CONFIG_DIR}/pacman.conf.in" > "${out}"
    cat >> "${out}" <<EOF
[pocknix-base]
SigLevel = Required DatabaseOptional
Server = ${POCKNIX_BASE_URL}
EOF
  else
    # The tarball's mirrorlist geo-routes and can land on a slow or flaky mirror mid-build; this
    # is the same mirror the snapshot harvests from, so one knob picks both.
    sed "s|^Include = /etc/pacman.d/mirrorlist\$|Server = ${POCKNIX_ALARM_PKG_MIRROR}/\$repo|" \
      "${CONFIG_DIR}/pacman.conf.in" > "${out}"
  fi
}
