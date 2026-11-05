#!/usr/bin/env bash
# check-pr.sh — the pull request rules make check cannot see, run by CI on every PR.
#
#   scripts/check-pr.sh [BASE [HEAD]]     # default: origin/main HEAD
#
# BASE is the live tip the PR merges into: pkgrel must beat ITS value, so two PRs bumping the
# same package collide here, not at release. PR_BODY (or PR_BODY_FILE) is the PR description;
# in Actions it is read from $GITHUB_EVENT_PATH. Without one the description check is skipped.
# Prints one line per problem, saying what to fix; exit 1 if any.
set -euo pipefail
source "$(dirname "$0")/ci.sh"

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
# --no-renames: a renamed patch is linted at its new path, and the package it left still counts.
changed_files() { git diff --no-renames --name-only "${mb}" "${head}" "$@"; }

# --- patch files: structure, plus mail headers on new ones ---------------------------------------
lint_dir="$(mktemp -d)"; trap 'rm -rf "${lint_dir}"' EXIT
lint() {  # $1 = diff filter, rest = patch-lint.py flags
  local filter="$1" f line; shift
  rm -rf "${lint_dir:?}"/*
  while IFS= read -r f; do
    mkdir -p "${lint_dir}/$(dirname "${f}")"
    git show "${head}:${f}" > "${lint_dir}/${f}"
  done < <(changed_files --diff-filter="${filter}" -- '*.patch')
  [ -n "$(ls -A "${lint_dir}")" ] || return 0
  while IFS= read -r line; do fail "${line}"; done \
    < <(cd "${lint_dir}" && find . -name '*.patch' | sed 's#^\./##' | sort | xargs python3 "${ci_root}/scripts/patch-lint.py" "$@" || true)
}
lint A --headers
lint M

# --- pkgrel ---------------------------------------------------------------------------------------
# pkgrel must go above the base's unless the version moved (version_lines, in ci.sh).
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }

declare -A pkgdirs=()
while IFS= read -r f; do
  is_doc "${f}" && continue
  case "${f}" in
    packages/soc/linux-pocknix/*) ;;
    devices/*/packages/*/*) pkgdirs["$(cut -d/ -f1-4 <<<"${f}")"]=1 ;;
    packages/*/*/*) pkgdirs["$(cut -d/ -f1-3 <<<"${f}")"]=1 ;;
  esac
done < <(changed_files)
for d in "${!pkgdirs[@]}"; do
  git cat-file -e "${head}:${d}/PKGBUILD" 2>/dev/null || continue
  git cat-file -e "${base}:${d}/PKGBUILD" 2>/dev/null || continue
  new="$(git show "${head}:${d}/PKGBUILD")"; old="$(git show "${base}:${d}/PKGBUILD")"
  [ "$(version_lines <<<"${new}")" != "$(version_lines <<<"${old}")" ] && continue
  nrel="$(pkgrel_of <<<"${new}")"; orel="$(pkgrel_of <<<"${old}")"
  gt "${nrel}" "${orel}" || fail "${d}: bump pkgrel above main's ${orel} (it is ${nrel:-unset}): its contents changed"
done

for s in $(cmd_changes "${base}" "${head}" | sed -n 's/^kernel_build=//p' | jq -r '.[]'); do
  c="kernel/${s}/kernel.conf"
  git cat-file -e "${head}:${c}" 2>/dev/null || continue
  git cat-file -e "${base}:${c}" 2>/dev/null || continue
  new="$(git show "${head}:${c}")"; old="$(git show "${base}:${c}")"
  [ "$(kconf_get KERNEL_VERSION <<<"${new}")" != "$(kconf_get KERNEL_VERSION <<<"${old}")" ] && continue
  nrel="$(kconf_get KERNEL_PKGREL <<<"${new}")"; orel="$(kconf_get KERNEL_PKGREL <<<"${old}")"
  gt "${nrel}" "${orel}" || fail "${c}: bump KERNEL_PKGREL above main's ${orel} (it is ${nrel:-unset}): the ${s} kernel changed"
done

# --- commits --------------------------------------------------------------------------------------
area_re='^([a-z0-9][a-z0-9._/+-]*(, ?[a-z0-9][a-z0-9._/+-]*)*: [^ ]|Revert ")'
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
