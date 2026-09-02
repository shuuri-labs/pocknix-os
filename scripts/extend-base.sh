#!/usr/bin/env bash
# extend-base.sh — host extra ALARM packages in the LIVE base without a re-cut
# (make extend-base PKG="samba ...").
#
# A full `make snapshot` needs a fresh unpinned build and rotates the base; adding a
# dep-light extra between cuts (a package whose deps the frozen base already
# satisfies) only needs the live db to grow by a few entries. The result is a suffixed
# snapshot id (20260826.1 -> 20260826.2): nothing already published changes bytes, so
# the fleet only ever sees a pocknix-base-lock upgrade, and `pacman -S <extra>` resolves
# on locked devices.
#
# Runs as the user in the VM (rclone remote). POCKNIX_SNAPSHOT_NO_UPLOAD=1 = dry run:
# builds the extended dir + lockfile, uploads nothing, pins nothing.

source "$(dirname "$0")/lib.sh"
[ "$(id -u)" -ne 0 ] || die "run as the user, no sudo (rclone lives in the user account)"
for t in curl tar awk sha256sum repo-add rclone; do need_tool "$t"; done
[ "$#" -gt 0 ] || die "no packages named — usage: make extend-base PKG=\"<alarm-name> ...\""

LOCKFILE="${PACKAGES_DIR}/shared/pocknix-base-lock/pocknix-base.lock"
EXTRAS_LIST="${CONFIG_DIR}/packages/base-extras.list"
RCLONE_DEST="${POCKNIX_BASE_RCLONE_REMOTE}"
BASE_DB="pocknix-base.db.tar.gz"
BASE_FILES="pocknix-base.files.tar.gz"
conf="${POCKNIX_ROOT}/config/pocknix.conf"

# --- which base we are extending -------------------------------------------
# The tree lockfile, the conf pin and the live SNAPSHOT_ID must all agree, or the
# extension would be computed from one base and published over another.
tree_id="$(sed -n 's/^#.*snapshot \([0-9][0-9.]*\).*/\1/p' "${LOCKFILE}" | head -1)"
[ -n "${tree_id}" ] || die "cannot read the snapshot id from ${LOCKFILE}"
[ "${POCKNIX_BASE_SNAPSHOT}" = "${tree_id}" ] \
  || die "config/pocknix.conf pins ${POCKNIX_BASE_SNAPSHOT:-<unpinned>} but the lockfile is snapshot ${tree_id} — commit or revert first"
live_id="$(rclone cat "${RCLONE_DEST}/SNAPSHOT_ID" 2>/dev/null | head -1 | tr -d '[:space:]')"
[ "${live_id}" = "${tree_id}" ] \
  || die "live base is snapshot ${live_id:-<none>}, the tree is ${tree_id} — pull main (or finish the interrupted publish) first"
case "${tree_id}" in
  *.*) ID="${tree_id%.*}.$(( ${tree_id##*.} + 1 ))" ;;
  *)   ID="${tree_id}.1" ;;
esac
OUT="${BUILD_DIR}/snapshot/${ID}"
mkdir -p "${OUT}" 2>/dev/null || die "${OUT} not creatable — one-time: sudo install -d -o $(id -un) ${BUILD_DIR}/snapshot"
rm -f "${OUT}"/*.pkg.tar.* "${OUT}"/pocknix-base.* "${OUT}"/SNAPSHOT_ID
log "extending base ${tree_id} -> ${ID} with: $*"

# --- the live db, and what it already serves --------------------------------
rclone copy --include "${BASE_DB}" --include "${BASE_FILES}" "${RCLONE_DEST}" "${OUT}"
[ -s "${OUT}/${BASE_DB}" ] && [ -s "${OUT}/${BASE_FILES}" ] || die "could not fetch ${BASE_DB}/${BASE_FILES} from ${RCLONE_DEST}"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/base"
tar -xf "${OUT}/${BASE_DB}" -C "${tmp}/base" 2>/dev/null || die "cannot read ${BASE_DB}"
# served = every hosted name plus everything they provide (sonames, virtuals)
declare -A served
while IFS='|' read -r n p; do
  served["${n}"]=1
  [ -n "${p}" ] && served["${p%%[<>=]*}"]=1
done < <(awk '/^%NAME%$/{getline name; print name"|"}
              /^%PROVIDES%$/{f=1;next} /^%[A-Z]+%$/{f=0}
              f&&NF{print name"|"$0}' "${tmp}/base"/*/desc)
# the live db must be the base the lockfile describes, entry for entry
live_count="$(ls -d "${tmp}/base"/*/ | wc -l)"
lock_count="$(grep -vc '^#' "${LOCKFILE}")"
[ "${live_count}" -eq "${lock_count}" ] \
  || die "live db has ${live_count} packages, the lockfile ${lock_count} — the tree lockfile is not the live base"
while read -r n v; do
  [ -d "${tmp}/base/${n}-${v}" ] || die "lockfile names ${n} ${v} but the live db does not carry it — adopt the live bytes first"
done < <(grep -v '^#' "${LOCKFILE}")

# --- locate the extras in ALARM's sync dbs -----------------------------------
# pacman.conf.in precedence (core > extra > alarm > aur), the same way the build
# resolves. The desc gives FILENAME + SHA256SUM so the download is verified against
# what pacman itself would trust; the depends file gives the guard its input.
declare -A x_ver x_file x_sha x_repo x_deps x_prov
for repo in core extra alarm aur; do
  mkdir -p "${tmp}/${repo}"
  curl -sS --fail -L --retry 3 -o "${tmp}/${repo}.db" "${POCKNIX_ALARM_PKG_MIRROR}/${repo}/${repo}.db" \
    || die "cannot fetch ${repo}.db from ${POCKNIX_ALARM_PKG_MIRROR}"
  tar -xf "${tmp}/${repo}.db" -C "${tmp}/${repo}" 2>/dev/null || die "cannot read ${repo}.db"
  for x in "$@"; do
    [ -n "${x_ver[${x}]:-}" ] && continue
    # the glob also matches siblings (tree-sitter for tree), so confirm %NAME%
    d=""
    for p in "${tmp}/${repo}/${x}"-*/; do
      [ -f "${p}/desc" ] || continue
      if [ "$(awk '/^%NAME%$/{getline; print; exit}' "${p}/desc")" = "${x}" ]; then d="${p}"; break; fi
    done
    [ -n "${d}" ] || continue
    x_ver["${x}"]="$(awk '/^%VERSION%$/{getline; print; exit}' "${d}/desc")"
    x_file["${x}"]="$(awk '/^%FILENAME%$/{getline; print; exit}' "${d}/desc")"
    x_sha["${x}"]="$(awk '/^%SHA256SUM%$/{getline; print; exit}' "${d}/desc")"
    x_repo["${x}"]="${repo}"
    [ -f "${d}/depends" ] || die "sync db ${repo} has no depends entry for ${x} — the dependency guard would be vacuous"
    x_deps["${x}"]="$(awk '/^%DEPENDS%$/{f=1;next} /^%[A-Z]+%$/{f=0} f&&NF' "${d}/depends" | paste -sd' ' -)"
    x_prov["${x}"]="$(awk '/^%PROVIDES%$/{f=1;next} /^%[A-Z]+%$/{f=0} f&&NF' "${d}/depends" | paste -sd' ' -)"
  done
  rm -rf "${tmp:?}/${repo}" "${tmp}/${repo}.db"
done
unknown=""
for x in "$@"; do
  [ -n "${x_ver[${x}]:-}" ] || unknown+="  ${x}"$'\n'
done
[ -z "${unknown}" ] || die "no ALARM sync db carries these (typo, or renamed/dropped upstream):
${unknown}"
for x in "$@"; do
  [ -z "${served[${x}]:-}" ] || die "${x} is already hosted in base ${tree_id} — nothing to extend"
  log "extra: ${x} ${x_ver[${x}]} (${x_repo[${x}]})"
done

# --- dependency guard --------------------------------------------------------
# An extra whose deps the frozen base cannot serve would install nowhere; that is
# a real cut's job (make snapshot), not an extension's. Extras may depend on each other.
for x in "$@"; do
  served["${x}"]=1
  for p in ${x_prov[${x}]}; do served["${p%%[<>=]*}"]=1; done
done
missing=""
for x in "$@"; do
  for dep in ${x_deps[${x}]}; do
    dep="${dep%%[<>=]*}"
    [ -n "${served[${dep}]:-}" ] || missing+="  ${dep} (needed by ${x})"$'\n'
  done
done
[ -z "${missing}" ] || die "these dependencies are not in base ${tree_id} — it would not install on a locked device:
${missing}
Name them in PKG= too if they are dep-light themselves; anything heavier waits for a real cut."

# --- fetch + verify + repo-add ------------------------------------------------
for x in "$@"; do
  fn="${x_file[${x}]}"
  for suffix in "" ".sig"; do
    curl -sS --fail -L --retry 3 -o "${OUT}/${fn}${suffix}" "${POCKNIX_ALARM_PKG_MIRROR}/${x_repo[${x}]}/${fn}${suffix}" \
      || die "cannot fetch ${fn}${suffix} from ${POCKNIX_ALARM_PKG_MIRROR} (mirror moved on? the sync db said ${x_ver[${x}]})"
  done
  echo "${x_sha[${x}]}  ${OUT}/${fn}" | sha256sum --quiet -c - || die "checksum mismatch for ${fn}"
done
( cd "${OUT}" && for x in "$@"; do printf '%s\n' "${x_file[${x}]}"; done | LC_ALL=C xargs repo-add -q "${BASE_DB}" ) \
  || die "repo-add failed"
rm -f "${OUT}"/*.old    # repo-add's backups would match the db upload pattern below

# --- lockfile + SNAPSHOT_ID ----------------------------------------------------
# Same header contract as snapshot-base.sh (pocknix-base-lock reads its pkgver from
# it) and the same `sort`, so the only diff against the tree is the new lines.
total=$(( lock_count + $# ))
{
  printf '# pocknix-base.lock - ALARM base snapshot %s (%d packages)\n' "${ID}" "${total}"
  printf '# Generated by scripts/snapshot-base.sh (make snapshot); shipped by pocknix-base-lock.\n'
  { grep -v '^#' "${LOCKFILE}"; for x in "$@"; do printf '%s %s\n' "${x}" "${x_ver[${x}]}"; done; } | sort
} > "${OUT}/pocknix-base.lock"
diff -q <(grep -v '^#' "${LOCKFILE}") <(grep -v '^#' "${LOCKFILE}" | sort) >/dev/null \
  || warn "this host's sort order differs from the one that wrote the lockfile — expect reorder noise in the diff (run in the build VM)"
printf '%s\n' "${ID}" > "${OUT}/SNAPSHOT_ID"

if [ -n "${POCKNIX_SNAPSHOT_NO_UPLOAD:-}" ]; then
  ok "dry run: extension ready at ${OUT} (lockfile ${total} packages); nothing uploaded, conf NOT pinned"
  exit 0
fi

# --- publish: additive, no rotation ------------------------------------------
# Packages first, db + lock after: a client syncing mid-publish sees either the old
# db (every file it names still present) or the new one (ditto). SNAPSHOT_ID last:
# it is what the next `make extend-base` / `make snapshot` keys its own state on.
# -L: repo-add's pocknix-base.db is a symlink; R2 gets a copy under both names.
log "publishing the extension -> ${RCLONE_DEST}"
rclone copy --include '*.pkg.tar.*' "${OUT}" "${RCLONE_DEST}"
rclone copy -L --include 'pocknix-base.db*' --include 'pocknix-base.files*' \
  --include 'pocknix-base.lock' "${OUT}" "${RCLONE_DEST}"
rclone copy --include 'SNAPSHOT_ID' "${OUT}" "${RCLONE_DEST}"

# --- pin the checkout ----------------------------------------------------------
# Only the snapshot id moves: the tarball pins stay on the parent cut, since the
# extension changes what the base HOSTS, not what a fresh build bootstraps from.
cp -f "${OUT}/pocknix-base.lock" "${LOCKFILE}"
sed -i -e "s|^: \"\${POCKNIX_BASE_SNAPSHOT:=.*}\"|: \"\${POCKNIX_BASE_SNAPSHOT:=${ID}}\"|" "${conf}"
for x in "$@"; do
  read_pkglist "${EXTRAS_LIST}" | grep -qx "${x}" || printf '%s\n' "${x}" >> "${EXTRAS_LIST}"
done
ok "base ${ID}: +$* published to ${RCLONE_DEST} (additive; ${tree_id} was not rotated)"
ok "pinned: config/pocknix.conf + lockfile; ${EXTRAS_LIST#"${POCKNIX_ROOT}/"} lists the extras (group/comment them, then commit)"
log "next: sudo make packages PKG=pocknix-base-lock, then stage + publish it to shared AND every SoC (it is dual-published)"
