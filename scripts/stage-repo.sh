#!/usr/bin/env bash
# stage-repo.sh — build the publish source (build/stage/<soc> or build/stage/shared) FROM the LIVE repo.
#
# build/localrepo is shared mutable build output: parallel sessions drop test
# packages, downgrades, and half-finished work into it, so publishing it
# wholesale can ship unvalidated packages (and the publish sync PRUNES the
# bucket to match). Staging inverts the direction of trust: mirror what is
# currently LIVE (known good), swap in ONLY the packages named on the command
# line, then verify the delta against live is exactly those names.
# publish-repo.sh publishes this dir and refuses to run without the .staged-ok
# marker written here on success.
#
# Usage:  make stage DEVICE=<target> PKG="pocknix-steam ..."   (as USER, no sudo)
#   - PKG names are ARTIFACT names: a split PKGBUILD's siblings are staged
#     individually (PKG="mesa vulkan-freedreno").
#   - DROP="<name>" retires a live package; the delta gate accepts only named
#     drops as deletions. Needed because pacman honors replaces= only for names
#     absent from every sync db — a package left live blocks its own migration.
#   - re-run freely: the mirror refresh is incremental (seconds after the first
#     run) and every run starts over from live, so a failed/abandoned staging
#     can never leak into the next one.

source "$(dirname "$0")/lib.sh"
need_tool rclone
read -ra DROPS <<< "${POCKNIX_STAGE_DROP:-}"
[ "$#" -gt 0 ] || [ "${#DROPS[@]}" -gt 0 ] || die "no packages named — usage: make stage PKG=\"<artifact-name> ...\" [DROP=\"<name> ...\"]"
for d in "${DROPS[@]-}"; do
  for name in "$@"; do [ "${d}" = "${name}" ] && die "${d}: named in both PKG and DROP"; done
done
[ -n "${POCKNIX_REPO_RCLONE_REMOTE}" ] || die "POCKNIX_REPO_RCLONE_REMOTE unset — no live repo to stage from"
[ "$(id -u)" -ne 0 ] || die "run as the publish user, not root (rclone + gpg config live in the user account)"

# Scope (lib.sh): the per-SoC [pocknix] tree by default, the SoC-neutral
# [pocknix-shared] tree with POCKNIX_REPO_SCOPE=shared (make stage-shared).
REMOTE="${POCKNIX_REPO_RCLONE_REMOTE}/${REPO_SEG}"
MARKER="${REPO_STAGE_DIR}/.staged-ok"

mkdir -p "${REPO_STAGE_DIR}" 2>/dev/null \
  || die "cannot create ${REPO_STAGE_DIR} (root-owned build/? fix once: sudo install -d -o $(id -un) ${BUILD_DIR}/stage)"
rm -f "${MARKER}"

# sync (not copy): also deletes local leftovers, so stage snaps back to
# exactly-live before this run's swap — a previously staged-but-unpublished
# package cannot survive into this release.
log "refreshing staging mirror from live: ${REMOTE} -> ${REPO_STAGE_DIR}"
rclone sync "${REMOTE}" "${REPO_STAGE_DIR}" \
  || die "rclone sync from ${REMOTE} failed (first-ever publish of this tree? seed with: POCKNIX_PUBLISH_FROM=localrepo make publish)"
# drop the downloaded db/index so publish's repo-add rebuilds a FRESH database
# containing exactly the staged package set (no ghost entries).
rm -f "${REPO_STAGE_DIR}/${REPO_NAME}".db* "${REPO_STAGE_DIR}/${REPO_NAME}".files*

shopt -s nullglob

# base name of a package file: strip -<ver>-<rel>-<arch>.pkg.tar.*[.sig]
pkgbase() { local b="${1##*/}"; b="${b%-*}"; b="${b%-*}"; b="${b%-*}"; printf '%s' "${b}"; }

list_pkgs() {  # non-sig package filenames in $1, sorted
  local f; for f in "$1"/*.pkg.tar.*; do [[ "$f" == *.sig ]] || basename "$f"; done | sort
}

live_list="$(list_pkgs "${REPO_STAGE_DIR}")"

for name in "$@"; do
  # exactly one built artifact for <name> in the localrepo (both globs match
  # epoch'd filenames, hence the dedupe; pkgbase check guards glob overreach)
  found=()
  for f in "${REPO_LOCALREPO_DIR}/${name}"-[0-9]*.pkg.tar.* "${REPO_LOCALREPO_DIR}/${name}"-*:*.pkg.tar.*; do
    [[ "$f" == *.sig ]] && continue
    [ "$(pkgbase "$f")" = "${name}" ] || continue
    case " ${found[*]-} " in *" ${f} "*) ;; *) found+=("$f") ;; esac
  done
  # Per-SoC staging falls back to the SHARED localrepo: shared packages build
  # only there, but during the [pocknix-shared] transition they are also staged
  # into the per-SoC trees (same bytes) — and pocknix-base permanently so (it
  # carries the stanza migration, so stale devices must reach it from [pocknix]).
  if [ "${#found[@]}" -eq 0 ] && [ "${POCKNIX_REPO_SCOPE}" != "shared" ]; then
    for f in "${LOCALREPO_SHARED_DIR}/${name}"-[0-9]*.pkg.tar.* "${LOCALREPO_SHARED_DIR}/${name}"-*:*.pkg.tar.*; do
      [[ "$f" == *.sig ]] && continue
      [ "$(pkgbase "$f")" = "${name}" ] || continue
      case " ${found[*]-} " in *" ${f} "*) ;; *) found+=("$f") ;; esac
    done
    [ "${#found[@]}" -gt 0 ] && log "${name}: staging the SHARED artifact into ${REPO_SEG} (dual-publish)"
  fi
  [ "${#found[@]}" -gt 0 ] || die "${name}: no artifact in ${REPO_LOCALREPO_DIR} (or the shared localrepo) — build it first (make packages; split artifacts build from their parent PKGBUILD)"
  [ "${#found[@]}" -eq 1 ] || die "${name}: multiple versions in localrepo ($(basename "${found[0]}") ...) — remove the stale ones first"
  # swap: drop every live version of <name> (sigs match the same globs), stage the new one
  for f in "${REPO_STAGE_DIR}/${name}"-[0-9]*.pkg.tar.* "${REPO_STAGE_DIR}/${name}"-*:*.pkg.tar.*; do
    [ "$(pkgbase "$f")" = "${name}" ] && rm -f "$f"
  done
  cp "${found[0]}" "${REPO_STAGE_DIR}/"
  log "staged: $(basename "${found[0]}")"
done

for d in "${DROPS[@]-}"; do
  [ -n "${d}" ] || continue
  hit=0
  for f in "${REPO_STAGE_DIR}/${d}"-[0-9]*.pkg.tar.* "${REPO_STAGE_DIR}/${d}"-*:*.pkg.tar.*; do
    [ "$(pkgbase "$f")" = "${d}" ] || continue
    rm -f "$f"; hit=1
  done
  [ "${hit}" -eq 1 ] || die "${d}: nothing to drop — no such package in the live repo"
  log "dropped: ${d}"
done

# --- delta gate: staging must differ from live by EXACTLY the named packages ---
staged_list="$(list_pkgs "${REPO_STAGE_DIR}")"
adds="$(comm -13 <(printf '%s' "${live_list}") <(printf '%s' "${staged_list}"))"
dels="$(comm -23 <(printf '%s' "${live_list}") <(printf '%s' "${staged_list}"))"

bad=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  wanted=0
  for name in "$@"; do [ "$(pkgbase "$f")" = "${name}" ] && wanted=1; done
  # a dropped name is a legitimate DELETION only — it can never appear as an add
  case "${dels}" in *"$f"*) for d in "${DROPS[@]-}"; do [ "$(pkgbase "$f")" = "${d}" ] && wanted=1; done ;; esac
  [ "${wanted}" -eq 1 ] || bad="${bad} ${f}"
done <<< "${adds}
${dels}"
[ -z "${bad}" ] || die "delta vs live contains packages you did not name:${bad}
(staging state is disposable — just re-run make stage, it restarts from live)"

for name in "$@"; do
  hit=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$(pkgbase "$f")" = "${name}" ] && hit=1
  done <<< "${adds}"
  [ "${hit}" -eq 1 ] || die "${name}: staged version is identical to live — bump pkgrel first (a published filename must never change bytes)"
done

log "delta vs live repo:"
while IFS= read -r f; do [ -n "$f" ] && printf '  + %s\n' "$f"; done <<< "${adds}"
while IFS= read -r f; do [ -n "$f" ] && printf '  - %s\n' "$f"; done <<< "${dels}"

# marker last, so it is newer than every staged file (publish checks this)
{
  printf 'repo=%s\nstaged=%s\n' "${REPO_SEG}" "$(date -u +%FT%TZ)"
  while IFS= read -r f; do [ -n "$f" ] && printf '%s\n' "+$f"; done <<< "${adds}"
  while IFS= read -r f; do [ -n "$f" ] && printf '%s\n' "-$f"; done <<< "${dels}"
} > "${MARKER}"

ok "staged -> ${REPO_STAGE_DIR}"
if [ "${POCKNIX_REPO_SCOPE}" = "shared" ]; then
  log "next: make publish-shared  (publishes the shared stage dir; the marker is consumed on success)"
else
  log "next: make publish DEVICE=<target of ${SOC}>  (publishes the stage dir; the marker is consumed on success)"
fi
