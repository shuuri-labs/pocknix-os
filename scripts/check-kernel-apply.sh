#!/usr/bin/env bash
# check-kernel-apply.sh — apply each SoC's kernel patch series to its pinned kernel.org source,
# without compiling: proves a kernel/ change applies on a clean tree (CI runs it per PR).
#
#   scripts/check-kernel-apply.sh [soc...]     # default: every SoC with a kernel/<soc>/kernel.conf
#
# Lints the series (scripts/patch-lint.py) before applying it. Any host with bash, curl, xz and
# GNU patch.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

socs=("$@")
if [ "${#socs[@]}" -eq 0 ]; then
  for c in "${root}"/kernel/*/kernel.conf; do
    s="$(basename "$(dirname "${c}")")"
    [ -f "${root}/devices/${s}/profile.conf" ] && socs+=("${s}")
  done
fi

failed=()
for soc in "${socs[@]}"; do
  # A subshell per SoC: lib.sh's := defaults would otherwise carry one SoC's paths into the next.
  # Run outside a condition: an if or || around it would switch set -e off inside.
  set +e
  (
    DEVICE="${soc}"
    source "${root}/scripts/lib.sh"
    work="${BUILD_DIR}/kernel-apply/${soc}"
    trap 'rm -rf "${work}"' EXIT
    rc=0
    log "${soc}: linting the patch series"
    python3 "${root}/scripts/patch-lint.py" "${KERNEL_DIR}"/patches/*/*.patch "${root}"/kernel/common/patches/*.patch \
      || { warn "${soc}: a patch is malformed (above); regenerate it with git format-patch"; rc=1; }
    fetch_kernel_source "${work}"
    apply_kernel_patches "${work}/linux-${KERNEL_VERSION}" "${KERNEL_DIR}"
    [ "${rc}" -eq 0 ] && ok "${soc}: every patch applies to linux-${KERNEL_VERSION}"
    exit "${rc}"
  )
  rc=$?
  set -e
  [ "${rc}" -eq 0 ] || failed+=("${soc}")
done

if [ "${#failed[@]}" -gt 0 ]; then
  printf '\033[1;31merror:\033[0m kernel patches do not apply for: %s\n' "${failed[*]}" >&2
  exit 1
fi
