#!/usr/bin/env bash
# check-docs.sh - fail when a tracked doc names something the tree no longer has, when a
# structural README's layout disagrees with its dir, or when a structural README copies a
# version or count out of its ledger. Run by check.sh; prints file:line for each problem.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}" || exit 1

DOCS="$(git ls-files 'README.md' 'CONTRIBUTING.md' 'AGENTS.md' 'PATCHES.md' '*/README.md' '*/PATCHES.md' 'docs/*.md' \
          '.github/PULL_REQUEST_TEMPLATE.md' '.github/ISSUE_TEMPLATE/*')"
# Structure + rules only: their volatile facts belong in a PATCHES.md, kernel.conf or a PKGBUILD.
STRUCTURAL="kernel/README.md devices/README.md docs/README.md CONTRIBUTING.md AGENTS.md"
# Backticked paths that name another tree's files, not ours (file:token).
FOREIGN="CONTRIBUTING.md:packages/kernel/PATCHES.md kernel/README.md:scripts/config"
# Tracked only as a .gitkeep: what docs name under them is build output.
GENERATED="build vendor"
ALLOW_MARK="docs-check: allow"

FILES="$(git ls-files)"
TOP="$(printf '%s\n' "${FILES}" | cut -d/ -f1 | sort -u | tr '\n' ' ')"
LIST="$(mktemp)"; trap 'rm -f "${LIST}"' EXIT
printf '%s\n' "${FILES}" > "${LIST}"
TARGETS="$(grep -oE '^[a-zA-Z_-]+:' Makefile | tr -d : | tr '\n' ' ')"
bad=0
err() { printf '  %s: %s\n' "$1" "$2"; bad=1; }

# glob with <placeholder> segments -> anchored regex over `git ls-files` (a dir matches by prefix)
glob_re() {
  printf '%s' "$1" | sed -E 's/[.+^$()|]/\\&/g; s/<[^>]*>/[^\/]+/g; s/\*/[^\/]*/g; s:/$::'
}
# one {a,b} group per pass until none are left
expand_braces() {
  local t="$1" pre alts post a
  if [[ "${t}" =~ ^([^{]*)\{([^}]*)\}(.*)$ ]]; then
    pre="${BASH_REMATCH[1]}" alts="${BASH_REMATCH[2]}" post="${BASH_REMATCH[3]}"
    IFS=, read -ra parts <<< "${alts}"
    for a in ${parts[@]+"${parts[@]}"}; do expand_braces "${pre}${a}${post}"; done
  else
    printf '%s\n' "${t}"
  fi
}

# --- (a) every backticked repo path, make target and relative link exists ----------------
for doc in ${DOCS}; do
  dir="$(dirname "${doc}")"
  allowed=" $(grep -nF "${ALLOW_MARK}" "${doc}" | cut -d: -f1 | tr '\n' ' ') "
  while IFS= read -r hit; do
    n="${hit%%:*}" tok="${hit#*:}"; tok="${tok#\`}"; tok="${tok%\`}"
    case "${allowed}" in *" ${n} "*) continue ;; esac
    if [[ "${tok}" =~ ^(sudo\ )?make\ ([a-z][a-z-]*) ]]; then
      t="${BASH_REMATCH[2]}"
      case " ${TARGETS} " in *" ${t} "*) ;; *) err "${doc}:${n}" "no make target '${t}'" ;; esac
      continue
    fi
    case "${tok}" in *" "*|/*|~*|*://*) continue ;; esac
    tok="${tok%%:[0-9]*}"
    [[ "${tok}" == */* ]] || continue
    case " ${TOP} " in *" ${tok%%/*} "*) ;; *) continue ;; esac
    case " ${GENERATED} " in *" ${tok%%/*} "*) continue ;; esac
    case " ${FOREIGN} " in *" ${doc}:${tok} "*) continue ;; esac
    found=0
    while IFS= read -r alt; do
      grep -qE "^$(glob_re "${alt}")(/|$)" "${LIST}" && { found=1; break; }
    done < <(expand_braces "${tok}")
    [ "${found}" -eq 1 ] || err "${doc}:${n}" "\`${tok}\` matches nothing in the tree"
  done < <(grep -noE '`[^`]+`' "${doc}")

  while IFS= read -r hit; do
    n="${hit%%:*}" target="${hit#*](}"; target="${target%)}"; target="${target%%#*}"
    case "${target}" in ''|http*|mailto:*) continue ;; esac
    [ -e "${dir}/${target}" ] || err "${doc}:${n}" "link (${target}) does not resolve"
  done < <(grep -noE '\]\([^) ]+\)' "${doc}")
done

# --- (b) layout blocks name what their dirs hold, both ways ------------------------------
# A layout line is "<indent><entry>  <comment>": entries nest by indent, "(optional)"
# exempts one from the must-exist direction.
layout() {  # $1 = README, $2 = the indent of the block's top-level entries
  awk -v base="$2" '/^```/{ if (f) exit; f = 1; next } f {
      match($0, /^ */); ind = RLENGTH; e = substr($0, ind + 1); split(e, w, " ")
      if (ind < base || w[1] == "" || w[1] ~ /^#/) next
      d = int((ind - base) / 2); sub(/\/$/, "", w[1]); path[d] = w[1]; p = w[1]
      for (i = d - 1; i >= 0; i--) p = path[i] "/" p
      print p (index($0, "(optional)") ? " optional" : "")
    }' "$1"
}
compare_layout() {  # $1 = README, $2 = documented entries, $3 = entries the tree has
  local e at
  at="$1:$(grep -n -m1 '^```' "$1" | cut -d: -f1)"
  for e in $(printf '%s\n' "$3" | sort -u); do
    printf '%s\n' "$2" | awk '{print $1}' | grep -qxF "${e}" || err "${at}" "layout block lacks '${e}'"
  done
  for e in $(printf '%s\n' "$2" | grep -v ' optional$'); do
    printf '%s\n' "$3" | grep -qxF "${e}" || err "${at}" "layout block names '${e}', which no SoC has"
  done
}

_doc="$(layout kernel/README.md 4)"
_have=""
for _k in kernel/*/kernel.conf; do
  _d="${_k%/kernel.conf}"; _soc="${_d#kernel/}"
  for _e in "${_d}"/* "${_d}"/patches/*; do
    [ -e "${_e}" ] || continue
    _e="${_e#"${_d}"/}"; [ "${_e}" = patches ] && continue
    _have="${_have}${_e//${_soc}/<soc>}"$'\n'
  done
done
compare_layout kernel/README.md "${_doc}" "${_have}"
[ -d kernel/common/patches ] || err kernel/README.md "kernel/common/patches is missing"

_doc="$(layout devices/README.md 2)"
_have=""
for _d in devices/*/profile.conf; do
  _d="${_d%/profile.conf}"; _soc="${_d#devices/}"
  for _e in "${_d}"/* "${_d}"/packages/*; do
    [ -e "${_e}" ] || continue
    _have="${_have}$(printf '%s' "${_e#"${_d}"/}" | sed "s/${_soc}/<soc>/g")"$'\n'
  done
done
compare_layout devices/README.md "${_doc}" "${_have}"

# Every key a board sets is part of the runtime contract, so devices/README.md's table names it.
for _key in $(cat devices/*/packages/pocknix-bsp-*/boards/*.conf 2>/dev/null | grep -oE '^[[:space:]]*POCKNIX_[A-Z0-9_]+=' | tr -d ' =' | sort -u); do
  grep -q "\`${_key}\`" devices/README.md ||
    err "devices/README.md:$(grep -n -m1 '^| Key |' devices/README.md | cut -d: -f1)" "key table lacks board key ${_key}"
done

# CONTRIBUTING's "Where changes go" table: a row per top-level dir and per packages/<kind>/.
_rows="$(awk '/^## Where changes go/{f=1; next} /^## /{f=0} f && /^\| `/' CONTRIBUTING.md \
         | grep -oE '^\| `[^`]+`' | sed -E 's/^\| `//')"
for _t in $(printf '%s\n' "${FILES}" | grep / | cut -d/ -f1 | sort -u) \
          $(printf '%s\n' "${FILES}" | grep '^packages/[^/]*/' | cut -d/ -f1-2 | sort -u); do
  [ "${_t}" = packages ] && continue
  printf '%s\n' "${_rows}" | grep -q "^${_t}/" ||
    err "CONTRIBUTING.md:$(grep -n -m1 '^## Where changes go' CONTRIBUTING.md | cut -d: -f1)" "\"Where changes go\" has no row for ${_t}/"
done

# --- (c) structural READMEs carry no versions or counts -----------------------------------
for doc in ${STRUCTURAL}; do
  while IFS= read -r hit; do
    case "${hit}" in *"${ALLOW_MARK}"*) continue ;; esac
    err "${doc}:${hit%%:*}" "version or count belongs in its ledger: $(printf '%s' "${hit#*:}" | grep -oE '\bv?[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?\b|\bv[0-9]+\.[0-9]+\b|[a-z]\ \([0-9]+\)' | head -1)"
  done < <(grep -nE '\bv?[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?\b|\bv[0-9]+\.[0-9]+\b|[a-z] \([0-9]+\)' "${doc}")
done

exit "${bad}"
