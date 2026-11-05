#!/usr/bin/env bash
# ci.sh — helpers for .github/workflows/build.yml; check-pr.sh sources it for the same path rules.
#
#   scripts/ci.sh changes BASE HEAD        # key=JSON lines for $GITHUB_OUTPUT: what the diff needs
#       kernel_apply   SoCs whose kernel patch series must re-apply
#       kernel_build   SoCs whose kernel package contents changed
#       builds         [{repo, soc, pkgs}]: package dirs to build per target repo; shared ones
#                      build once, in the default DEVICE's chroot
#   scripts/ci.sh soc-pkgs SOC [--shared]  # every package SOC builds, the kernel aside
#   scripts/ci.sh verify SOC PKG...        # fail unless each PKG has an artifact in build/localrepo
#
# A doc-only change (*.md, README*) never triggers anything.
set -euo pipefail
ci_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ci_root}"

is_doc() { case "${1##*/}" in *.md|README*) return 0 ;; esac; return 1; }
gpu_of() { sed -n 's/.*GPU_GEN:=\([A-Za-z0-9]*\).*/\1/p' "devices/$1/profile.conf" | head -1; }

all_socs=()
for p in devices/*/profile.conf; do all_socs+=("$(basename "$(dirname "${p}")")"); done
default_soc="$(sed -n 's/^: "${DEVICE:=\([a-z0-9]*\)}".*/\1/p' config/pocknix.conf)"

tuned_dirs() {  # $1 = soc: the dirs built with its devices/<soc>/tuning.conf, the kernel aside
  local s="$1" d g; g="$(gpu_of "${s}")"
  for d in packages/soc/*/; do
    d="${d%/}"; [ "${d##*/}" = linux-pocknix ] && continue
    case " $(cat "${d}/socs") " in *" all "*|*" ${s} "*) echo "${d}" ;; esac
  done
  for d in packages/gpu/*/; do
    d="${d%/}"
    case " $(cat "${d}/gpus") " in *" ${g} "*) echo "${d}" ;; esac
  done
}

cmd_changes() {
  local base="$1" head="$2" mb f s d g
  mb="$(git merge-base "${base}" "${head}")"
  declare -A apply=() kbuild=() want=()
  at() { git show "${head}:$1" 2>/dev/null; }
  add() { git cat-file -e "${head}:$2/PKGBUILD" 2>/dev/null && want["$1|$(basename "$2")"]=1; return 0; }
  bsps() {  # $1 = soc: the packages rendered from the profile and config/pocknix.conf
    add "$1" "devices/$1/packages/pocknix-bsp-$1"
    add "$1" "packages/soc/pocknix-bootloader-$1"
  }
  while IFS= read -r f; do
    is_doc "${f}" && continue
    case "${f}" in
      kernel/common/*|packages/soc/linux-pocknix/*|scripts/build-kernel.sh)
        for s in "${all_socs[@]}"; do apply[$s]=1; kbuild[$s]=1; done ;;
      kernel/*/*)
        s="$(cut -d/ -f2 <<<"${f}")"
        [ -f "devices/${s}/profile.conf" ] && { apply[$s]=1; kbuild[$s]=1; } ;;
      scripts/lib.sh|scripts/check-kernel-apply.sh|scripts/patch-lint.py)
        for s in "${all_socs[@]}"; do apply[$s]=1; done ;;
      scripts/render-bsp.sh|config/pocknix.conf)
        for s in "${all_socs[@]}"; do bsps "${s}"; done ;;
      devices/*/profile.conf)
        bsps "$(cut -d/ -f2 <<<"${f}")" ;;
      devices/*/tuning.conf)
        s="$(cut -d/ -f2 <<<"${f}")"
        while IFS= read -r d; do add "${s}" "${d}"; done < <(tuned_dirs "${s}") ;;
      packages/shared/*/*)
        add shared "$(cut -d/ -f1-3 <<<"${f}")" ;;
      packages/soc/*/*)
        d="$(cut -d/ -f1-3 <<<"${f}")"
        for s in "${all_socs[@]}"; do
          case " $(at "${d}/socs") " in *" all "*|*" ${s} "*) add "${s}" "${d}" ;; esac
        done ;;
      packages/gpu/*/*)
        d="$(cut -d/ -f1-3 <<<"${f}")"
        for s in "${all_socs[@]}"; do
          g="$(gpu_of "${s}")"
          [ -n "${g}" ] && case " $(at "${d}/gpus") " in *" ${g} "*) add "${s}" "${d}" ;; esac
        done ;;
      devices/*/packages/*/*)
        s="$(cut -d/ -f2 <<<"${f}")"
        add "${s}" "$(cut -d/ -f1-4 <<<"${f}")" ;;
    esac
  done < <(git diff --no-renames --name-only "${mb}" "${head}")

  local builds="[]" repo pkgs
  for repo in shared "${all_socs[@]}"; do
    pkgs="$(for k in "${!want[@]}"; do if [ "${k%%|*}" = "${repo}" ]; then echo "${k#*|}"; fi; done | sort | xargs)"
    [ -n "${pkgs}" ] || continue
    s="${repo}"; [ "${repo}" = shared ] && s="${default_soc}"
    builds="$(jq -c --arg r "${repo}" --arg s "${s}" --arg p "${pkgs}" '. + [{repo: $r, soc: $s, pkgs: $p}]' <<<"${builds}")"
  done
  printf 'kernel_apply=%s\n' "$(printf '%s\n' "${!apply[@]}" | sort | jq -Rsc 'split("\n") | map(select(length > 0))')"
  printf 'kernel_build=%s\n' "$(printf '%s\n' "${!kbuild[@]}" | sort | jq -Rsc 'split("\n") | map(select(length > 0))')"
  printf 'builds=%s\n' "${builds}"
}

cmd_soc_pkgs() {
  local s="$1" d
  if [ "${2:-}" = --shared ]; then
    for d in packages/shared/*/; do [ -f "${d}PKGBUILD" ] && basename "${d}"; done
  fi
  tuned_dirs "${s}" | xargs -n1 basename
  for d in "devices/${s}"/packages/*/; do basename "${d}"; done
}

# build-packages.sh exits 0 once anything built, so a failed package shows only as a missing file.
cmd_verify() {
  local s="$1" p f n missing=()
  shift
  declare -A have=()
  for f in build/localrepo/shared/*.pkg.tar.* "build/localrepo/${s}"/*.pkg.tar.*; do
    [ -e "${f}" ] || continue
    n="${f##*/}"; n="${n%-*}"; n="${n%-*}"; n="${n%-*}"  # strip -<ver>-<rel>-<arch>.pkg.tar.*
    have[$n]=1
  done
  for p in "$@"; do [ -n "${have[$p]:-}" ] || missing+=("${p}"); done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "error: no package built for: ${missing[*]} (its makepkg error is in the build log above)" >&2
    return 1
  fi
  echo "verify: all $# packages built"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    changes) shift; cmd_changes "$@" ;;
    soc-pkgs) shift; cmd_soc_pkgs "$@" | xargs ;;
    verify) shift; cmd_verify "$@" ;;
    *) echo "usage: scripts/ci.sh changes BASE HEAD | soc-pkgs SOC [--shared] | verify SOC PKG..." >&2; exit 2 ;;
  esac
fi
