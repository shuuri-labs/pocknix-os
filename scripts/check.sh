#!/usr/bin/env bash
# check.sh — sanity-check the project + (when present) the built artifacts.
# Phase 0: validates the harness itself; later phases add image/DTB/module checks.

source "$(dirname "$0")/lib.sh"

fail=0
note() { printf '  %-44s %s\n' "$1" "$2"; }

log "pocknix-os preflight"

# --- host tooling ----------------------------------------------------------
for t in bash sed rsync curl tar; do
  if have "$t"; then note "host tool: $t" "ok"; else note "host tool: $t" "MISSING"; fail=1; fi
done
if [ "$(uname -s)" = "Linux" ]; then note "host os" "Linux ok"
else note "host os" "$(uname -s) (image build needs Linux)"; fi

# --- project layout --------------------------------------------------------
for d in config config/packages scripts packages vendor; do
  [ -d "${POCKNIX_ROOT}/${d}" ] && note "dir: ${d}/" "ok" || { note "dir: ${d}/" "MISSING"; fail=1; }
done
for f in config/pocknix.conf config/pacman.conf.in config/packages/base.list; do
  [ -f "${POCKNIX_ROOT}/${f}" ] && note "file: ${f}" "ok" || { note "file: ${f}" "MISSING"; fail=1; }
done

# --- scripts executable ----------------------------------------------------
for s in sync.sh bootstrap.sh build-image.sh install.sh check.sh; do
  [ -x "${POCKNIX_ROOT}/scripts/${s}" ] && note "exec: scripts/${s}" "ok" || { note "exec: scripts/${s}" "not +x"; fail=1; }
done

# --- kernel enablement present? (committed; refreshable via sync) -----------
_npatch=$(find "${KERNEL_DIR}/patches" -name '*.patch' 2>/dev/null | wc -l | tr -d ' ')
if [ "${_npatch:-0}" -gt 0 ]; then
  note "kernel: enablement (kernel/)" "${_npatch} patches (mainline+sm8550+version)"
else
  note "kernel: enablement (kernel/)" "run 'make sync'"
fi
# vendor sync is build-time only (gitignored)
if [ -d "${VENDOR_DIR}/rocknix-sm8550/reference" ]; then
  note "vendor: reference/firmware" "synced"
else
  note "vendor: reference/firmware" "run 'make sync' (build host)"
fi

# --- built artifacts (only checked if they exist) --------------------------
if [ -d "${BUILD_DIR}/kernel/out" ]; then
  note "kernel build" "$(cat "${BUILD_DIR}/kernel/out/kernelrelease" 2>/dev/null || echo present)"
else
  note "kernel build" "run 'make kernel'"
fi
if [ -f "${IMAGE_DIR}/KERNEL" ]; then
  note "boot image KERNEL" "$(du -h "${IMAGE_DIR}/KERNEL" | cut -f1) (qcom-abl)"
else
  note "boot image KERNEL" "not built (make kernel)"
fi
[ -d "${ROOTFS_DIR}" ] && note "rootfs" "present"

echo
[ "$fail" -eq 0 ] && ok "preflight passed" || die "preflight found problems (see above)"
