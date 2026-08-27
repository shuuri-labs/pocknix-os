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
for d in config config/packages scripts packages/shared packages/soc vendor "devices/${DEVICE}"; do
  [ -d "${POCKNIX_ROOT}/${d}" ] && note "dir: ${d}/" "ok" || { note "dir: ${d}/" "MISSING"; fail=1; }
done

# --- package placement: shared/ vs soc/ -------------------------------------
# The split is load-bearing: shared/ builds once into [pocknix-shared], soc/
# builds per SoC gated by ./socs. A PKGBUILD directly under packages/ is
# invisible to the build; a soc/ package without socs (or with an unknown SoC)
# would silently vanish from every repo; a socs file under shared/ is a
# misplacement (shared builds must be SoC-blind).
while IFS= read -r p; do
  note "package: ${p#"${POCKNIX_ROOT}"/}" "OUTSIDE shared/ and soc/ — never built"; fail=1
done < <(find "${POCKNIX_ROOT}/packages" -maxdepth 2 -name PKGBUILD \
           ! -path "*/packages/shared/*" ! -path "*/packages/soc/*" 2>/dev/null)
for p in "${POCKNIX_ROOT}"/packages/soc/*/; do
  [ -d "${p}" ] || continue
  n="$(basename "${p}")"
  if [ ! -f "${p}/socs" ]; then
    note "soc pkg: ${n}" "MISSING socs file"; fail=1; continue
  fi
  read -r _socs < "${p}/socs"
  bad=0
  for s in ${_socs}; do
    [ -d "${POCKNIX_ROOT}/kernel/${s}" ] || { note "soc pkg: ${n}" "unknown SoC '${s}' in socs"; fail=1; bad=1; }
  done
  [ "${bad}" -eq 0 ] && [ -n "${_socs}" ] && note "soc pkg: ${n}" "socs: ${_socs}"
done
for p in "${POCKNIX_ROOT}"/packages/shared/*/socs; do
  [ -e "${p}" ] || continue
  note "shared pkg: $(basename "$(dirname "${p}")")" "has a socs file (shared builds are SoC-blind — move it to packages/soc/ or delete the file)"; fail=1
done
for f in config/pocknix.conf config/pacman.conf.in config/packages/base.list \
         "devices/${DEVICE}/profile.conf" "kernel/${SOC}/kernel.conf"; do
  [ -f "${POCKNIX_ROOT}/${f}" ] && note "file: ${f}" "ok" || { note "file: ${f}" "MISSING"; fail=1; }
done
note "device" "${DEVICE} (${DEVICE_PRETTY:-?}) on ${SOC}"

# --- scripts executable ----------------------------------------------------
for s in sync.sh bootstrap.sh build-image.sh build-kernel.sh build-packages.sh \
         build-sd-image.sh stage-repo.sh stage-check.sh publish-repo.sh install.sh check.sh; do
  [ -x "${POCKNIX_ROOT}/scripts/${s}" ] && note "exec: scripts/${s}" "ok" || { note "exec: scripts/${s}" "not +x"; fail=1; }
done

# --- kernel enablement present? (committed; refreshable via sync) -----------
_npatch=$(find "${KERNEL_DIR}/patches" -name '*.patch' 2>/dev/null | wc -l | tr -d ' ')
if [ "${_npatch:-0}" -gt 0 ]; then
  note "kernel: enablement (kernel/${SOC}/)" "${_npatch} patches"
else
  note "kernel: enablement (kernel/${SOC}/)" "run 'make sync'"
fi
# vendor sync is build-time only (gitignored)
if [ -d "${VENDOR_DIR}/rocknix-${SOC}/reference" ]; then
  note "vendor: reference/firmware" "synced"
else
  note "vendor: reference/firmware" "run 'make sync' (build host)"
fi

# --- built artifacts (only checked if they exist) --------------------------
if [ -d "${KERNEL_BUILD_DIR}/out" ]; then
  note "kernel build" "$(cat "${KERNEL_BUILD_DIR}/out/kernelrelease" 2>/dev/null || echo present)"
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
