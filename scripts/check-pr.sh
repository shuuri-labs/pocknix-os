#!/usr/bin/env bash
# check-pr.sh — the pull request rules make check cannot see, run by CI on every PR.
#
#   scripts/check-pr.sh [BASE [HEAD]]     # default: origin/main HEAD
#
# BASE is the branch tip the PR merges into (pkgrel must beat ITS value, so two PRs bumping the
# same package collide here, not at release). PR_BODY (or PR_BODY_FILE) is the PR description;
# in Actions it is read from $GITHUB_EVENT_PATH. Without one the description check is skipped. Prints one line per problem, saying what to fix; exit 1 if any.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"

base="${1:-origin/main}"
head="${2:-HEAD}"
mb="$(git merge-base "${base}" "${head}")"

in_pr=0
if [ -n "${GITHUB_EVENT_PATH:-}" ] && jq -e '.pull_request' "${GITHUB_EVENT_PATH}" >/dev/null 2>&1; then
  in_pr=1; : "${PR_BODY:=$(jq -r '.pull_request.body // empty' "${GITHUB_EVENT_PATH}")}"
fi
[ -n "${PR_BODY_FILE:-}" ] && PR_BODY="$(cat "${PR_BODY_FILE}")"
[ -n "${PR_BODY:-}" ] && in_pr=1

problems=()
fail() { problems+=("$*"); }

# Files that never change what a package or kernel ships.
is_doc() { case "${1##*/}" in *.md|README*) return 0 ;; esac; return 1; }

changed=()
while IFS= read -r f; do changed+=("${f}"); done < <(git diff --name-only "${mb}" "${head}")

# --- patch files: headers and hunks ----------------------------------------------------
lint_dir="$(mktemp -d)"; trap 'rm -rf "${lint_dir}"' EXIT
while IFS= read -r f; do
  mkdir -p "${lint_dir}/$(dirname "${f}")"
  git show "${head}:${f}" > "${lint_dir}/${f}"
done < <(git diff --name-only --diff-filter=AM "${mb}" "${head}" -- '*.patch')
if [ -n "$(ls -A "${lint_dir}")" ]; then
  while IFS= read -r line; do fail "${line#"${lint_dir}"/}"; done \
    < <(cd "${lint_dir}" && find . -name '*.patch' | sed 's#^\./##' | sort | xargs python3 "${root}/scripts/patch-lint.py" --headers || true)
fi

# --- pkgrel ---------------------------------------------------------------------------------------
# A version line (pkgver, epoch or a _var it is built from) that moved is a version bump; the
# pkgrel may then restart. Otherwise pkgrel must go above the base's.
version_lines() { grep -E '^(pkgver|epoch|_[A-Za-z0-9_]+)=' || true; }
pkgrel_of() { sed -n 's/^pkgrel=["'\'']\{0,1\}\([0-9][0-9.]*\).*/\1/p' | head -1; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }

pkgdirs=()
for f in "${changed[@]}"; do
  is_doc "${f}" && continue
  case "${f}" in
    packages/soc/linux-pocknix/*) ;;
    packages/*/*/*|devices/*/packages/*/*)
      d="$(cut -d/ -f1-3 <<<"${f}")"; [ "${f#devices/}" != "${f}" ] && d="$(cut -d/ -f1-4 <<<"${f}")"
      case " ${pkgdirs[*]-} " in *" ${d} "*) ;; *) pkgdirs+=("${d}") ;; esac ;;
  esac
done
for d in "${pkgdirs[@]+"${pkgdirs[@]}"}"; do
  git cat-file -e "${head}:${d}/PKGBUILD" 2>/dev/null || continue
  git cat-file -e "${base}:${d}/PKGBUILD" 2>/dev/null || continue
  new="$(git show "${head}:${d}/PKGBUILD")"; old="$(git show "${base}:${d}/PKGBUILD")"
  [ "$(version_lines <<<"${new}")" != "$(version_lines <<<"${old}")" ] && continue
  nrel="$(pkgrel_of <<<"${new}")"; orel="$(pkgrel_of <<<"${old}")"
  gt "${nrel}" "${orel}" || fail "${d}: bump pkgrel above main's ${orel} (it is ${nrel:-unset}): its contents changed"
done

# A kernel/<soc> change repackages that SoC's kernel; kernel/common and the recipe repackage all.
ksocs=()
for f in "${changed[@]}"; do
  is_doc "${f}" && continue
  case "${f}" in
    kernel/common/*|packages/soc/linux-pocknix/*)
      for c in kernel/*/kernel.conf; do ksocs+=("$(cut -d/ -f2 <<<"${c}")"); done ;;
    kernel/*/*) ksocs+=("$(cut -d/ -f2 <<<"${f}")") ;;
  esac
done
kconf_get() { sed -n "s/^: \"\${$1:=\([^}]*\)}\".*/\1/p" | head -1; }
for s in $(printf '%s\n' "${ksocs[@]+"${ksocs[@]}"}" | sort -u); do
  c="kernel/${s}/kernel.conf"
  git cat-file -e "${head}:${c}" 2>/dev/null || continue
  git cat-file -e "${base}:${c}" 2>/dev/null || continue
  new="$(git show "${head}:${c}")"; old="$(git show "${base}:${c}")"
  [ "$(kconf_get KERNEL_VERSION <<<"${new}")" != "$(kconf_get KERNEL_VERSION <<<"${old}")" ] && continue
  nrel="$(kconf_get KERNEL_PKGREL <<<"${new}")"; orel="$(kconf_get KERNEL_PKGREL <<<"${old}")"
  gt "${nrel}" "${orel}" || fail "${c}: bump KERNEL_PKGREL above main's ${orel} (it is ${nrel:-unset}): the ${s} kernel changed"
done

# --- commits --------------------------------------------------------------------------------------
area_re='^[a-z0-9][a-z0-9._/+-]*(, ?[a-z0-9][a-z0-9._/+-]*)*: [^ ]'
while IFS= read -r sha; do
  subject="$(git log -1 --format=%s "${sha}")"
  [[ "${subject}" =~ ${area_re} ]] \
    || fail "commit ${sha:0:8} '${subject}': write the subject as 'area: summary' (lowercase area, e.g. 'kernel: ...', 'mesa: ...')"
done < <(git rev-list --no-merges --reverse "${mb}..${head}")

# --- PR body --------------------------------------------------------------------------------------
if [ "${in_pr}" -eq 1 ]; then
  for h in "What" "How" "Tested" "How to test"; do
    grep -qiE "^##[[:space:]]+${h}[[:space:]]*(<!--.*)?$" <<<"${PR_BODY:-}" \
      || fail "PR description: add the '## ${h}' section from .github/PULL_REQUEST_TEMPLATE.md"
  done
fi

if [ "${#problems[@]}" -gt 0 ]; then
  printf '%s\n' "${problems[@]}"
  exit 1
fi
echo "check-pr: ok"
