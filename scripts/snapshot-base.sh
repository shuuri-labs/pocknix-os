#!/usr/bin/env bash
# snapshot-base.sh — freeze the ALARM package base into [pocknix-base] (make snapshot).
#
# Reproducible builds need a recorded, re-fetchable input set. This harvests the
# GROUND-TRUTH union of every ALARM package a build actually installed (the image
# rootfs + every SoC's build chroot) plus the opt-in extras in
# config/packages/base-extras.list, collects exactly those files + their .sig
# (build caches first, ALARM mirror for the residue), builds a fresh
# pocknix-base.db covering only them, and publishes it.
#
# ONE repo at a STABLE url ([pocknix-base]): "frozen" means it never moves on its
# own, not that it is immutable — it moves exactly when a release moves it, so
# devices pick up a bumped base with a plain -Syu and need no repointing. The
# outgoing base is rotated to <remote>-prev first, which is what keeps the
# PREVIOUS release rebuildable (ALARM keeps no archive of old versions); older
# bases are not retained, by decision.
#
# Run RIGHT AFTER a fresh `sudo make build`: cache-sourced files are race-free,
# but the residue (tarball-era packages) comes from the mirror, which only
# serves current versions. As the user, no sudo (rclone remote lives in the
# user account; output must stay user-owned).
#
# To rebuild the PREVIOUS release, point both pins at the rotated copy:
#   POCKNIX_BASE_URL=<repo>/base-prev \
#   POCKNIX_ALARM_TARBALL_URL=<repo>/base-prev/<its dated tarball> sudo -E make build
# (nothing does that automatically — the live pins always name the current base.)
#
# Knobs: POCKNIX_SNAPSHOT_ID (default UTC date; the id is a LABEL — it names the
# pocknix-base-lock package version, not a url), POCKNIX_SNAPSHOT_NO_UPLOAD=1
# (dry run: build the snapshot dir + lockfile, skip rclone + conf pins).

source "$(dirname "$0")/lib.sh"
[ "$(id -u)" -ne 0 ] || die "run as the user, no sudo (rclone + gpg live in the user account)"
for t in curl tar awk sha256sum repo-add; do need_tool "$t"; done

# A pinned build's sync dbs are [pocknix-base], not core/extra/alarm/aur, so the
# harvest below would drop the shadowed ALARM copies and point residue downloads
# at a repo path the ALARM mirror does not serve. Only a live-ALARM build is harvestable.
[ -z "${POCKNIX_BASE_SNAPSHOT}" ] || die "POCKNIX_BASE_SNAPSHOT=${POCKNIX_BASE_SNAPSHOT} — a snapshot can only be harvested from an UNPINNED (live ALARM) build.
Blank POCKNIX_BASE_SNAPSHOT in config/pocknix.conf, re-run 'sudo make build' + 'make packages', then snapshot."

ID="${POCKNIX_SNAPSHOT_ID:-$(date -u +%Y%m%d)}"
OUT="${BUILD_DIR}/snapshot/${ID}"
RCLONE_DEST="${POCKNIX_BASE_RCLONE_REMOTE}"
RCLONE_PREV="${POCKNIX_BASE_RCLONE_REMOTE}-prev"
DATED_TARBALL="ArchLinuxARM-aarch64-${ID}.tar.gz"
LOCKFILE="${PACKAGES_DIR}/shared/pocknix-base-lock/pocknix-base.lock"
EXTRAS_LIST="${CONFIG_DIR}/packages/base-extras.list"
BASE_DB="pocknix-base.db.tar.gz"

# --- collect harvest sources -------------------------------------------------
# The union must cover the runtime closure (rootfs) AND build deps (chroots):
# the chroot is recreated from this snapshot, so its packages must be hosted too.
sources=()
[ -d "${ROOTFS_DIR}/var/lib/pacman/local" ] \
  || die "no rootfs local db at ${ROOTFS_DIR} — run 'sudo make build' first (snapshot needs a FRESH build)"
sources+=("${ROOTFS_DIR}")
for b in "${BUILD_DIR}"/pkgbuild-root-*; do
  [ -d "${b}/var/lib/pacman/local" ] && sources+=("${b}")
done
log "harvest sources: ${sources[*]#"${BUILD_DIR}/"}"

# Names owned by [pocknix]/[pocknix-shared] (all SoCs' localrepos + the shared
# one): ours, never part of the ALARM base — mesa/gamescope replace ALARM
# copies under the same name, so filter by NAME, not version.
declare -A ours
for db in "${BUILD_DIR}"/localrepo/*/pocknix.db.tar.gz \
          "${BUILD_DIR}"/localrepo/shared/pocknix-shared.db.tar.gz; do
  [ -f "${db}" ] || continue
  while IFS= read -r d; do
    d="${d%%/*}"; [ -n "${d}" ] || continue
    ours["${d%-*-*}"]=1
  done < <(tar -tf "${db}" 2>/dev/null)
done
[ "${#ours[@]}" -gt 0 ] || die "no [pocknix] db under ${BUILD_DIR}/localrepo — run 'sudo make packages' first"

# --- union manifest: name -> version ----------------------------------------
# pacman's local db is just dirs named <name>-<ver>-<rel>; pkgver/pkgrel cannot
# contain hyphens, so stripping the last two dash segments yields the name.
declare -A want wantsrc
conflicts=""
for src in "${sources[@]}"; do
  for d in "${src}"/var/lib/pacman/local/*/; do
    b="$(basename "${d}")"
    [ "${b}" = "ALPM_DB_VERSION" ] && continue
    name="${b%-*-*}"; ver="${b#"${name}-"}"
    [ -n "${ours[${name}]:-}" ] && continue
    if [ -n "${want[${name}]:-}" ] && [ "${want[${name}]}" != "${ver}" ]; then
      conflicts+="  ${name}: ${want[${name}]} (${wantsrc[${name}]}) vs ${ver} (${src##*/})"$'\n'
      continue
    fi
    want["${name}"]="${ver}"; wantsrc["${name}"]="${src##*/}"
  done
done
[ -z "${conflicts}" ] || die "version conflicts between harvest sources — one of them is stale.
Converge/rebuild so all sources share one base (sudo make build; make packages per SoC), then re-run:
${conflicts}"
log "union manifest: ${#want[@]} ALARM packages"

# --- SoC completeness --------------------------------------------------------
# The union covers every SoC's BUILD chroot but only ONE runtime rootfs, so a
# runtime-only dep of another SoC's BSP silently misses the snapshot and that
# SoC's images then fail to resolve. Fail rather than ship a one-SoC base.
soc_missing=""
for _bsp in "${POCKNIX_ROOT}"/devices/*/packages/pocknix-bsp-*/PKGBUILD; do
  [ -f "${_bsp}" ] || continue
  # source the PKGBUILD rather than grepping: a depends=() wrapped over several
  # lines would silently yield nothing, and a guard that quietly stops guarding
  # is worse than none.
  _deps="$(bash -c 'depends=(); source "$1" >/dev/null 2>&1; printf "%s\n" "${depends[@]}"' _ "${_bsp}" 2>/dev/null)"
  [ -n "${_deps}" ] || die "cannot read depends= from ${_bsp} — the SoC-completeness guard would be vacuous"
  while read -r _dep; do
    _dep="${_dep%%[<>=]*}"
    case "${_dep}" in ''|pocknix-*) continue ;; esac
    [ -n "${want[${_dep}]:-}" ] && continue
    soc_missing+="  ${_dep} (needed by $(basename "$(dirname "${_bsp}")"))"$'\n'
  done <<< "${_deps}"
done
[ -z "${soc_missing}" ] || die "base would not serve every SoC — these device BSP deps are absent:
${soc_missing}
Add them to config/packages/base.list (so EVERY build's rootfs installs them),
rebuild, then snapshot again."

# --- opt-in extras: hosted, never installed (resolved from the sync dbs) -----
extras=()
[ -f "${EXTRAS_LIST}" ] || die "missing ${EXTRAS_LIST} (committed; empty is fine, absent is not)"
mapfile -t extras < <(read_pkglist "${EXTRAS_LIST}")
[ "${#extras[@]}" -eq 0 ] || log "extras to host: ${extras[*]}"

# --- map names to repo files via the sync dbs the build used -----------------
# The sync db desc carries %FILENAME% + %SHA256SUM%, so downloads are verified
# against what pacman itself trusted. Rootfs dbs first (freshest -Syy).
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
declare -A f_file f_sha f_repo s_ver x_deps prov seen_repo
for src in "${sources[@]}"; do
  for db in "${src}"/var/lib/pacman/sync/*.db; do
    [ -f "${db}" ] || continue
    repo="$(basename "${db}" .db)"
    mkdir -p "${tmp}/${repo}"
    tar -xf "${db}" -C "${tmp}/${repo}" 2>/dev/null || die "cannot read sync db ${db}"
    while IFS='|' read -r n v fn sha; do
      key="${n} ${v}"
      [ -n "${f_file[${key}]:-}" ] || { f_file["${key}"]="${fn}"; f_sha["${key}"]="${sha}"; f_repo["${key}"]="${repo}"; }
      # extras have no installed version to key on, so record what each repo carries
      [ -n "${s_ver[${repo}|${n}]:-}" ] || s_ver["${repo}|${n}"]="${v}"
    done < <(awk 'FNR==1{name=ver=fn=sha=""}
                  /^%NAME%$/{getline name} /^%VERSION%$/{getline ver}
                  /^%FILENAME%$/{getline fn} /^%SHA256SUM%$/{getline sha}
                  ENDFILE{if(name!="")print name"|"ver"|"fn"|"sha}' "${tmp}/${repo}"/*/desc)
    # ALARM dbs only, once each: our repo-add'd dbs keep deps inside desc (no depends
    # file) and ours are served via the ours map anyway. Provides matter: a dep may
    # name a soname/virtual, and a name-only check would refuse installable extras.
    case "${repo}" in core|extra|alarm|aur) alarm_repo=1 ;; *) alarm_repo="" ;; esac
    if [ -n "${alarm_repo}" ] && [ -z "${seen_repo[${repo}]:-}" ] && [ "${#extras[@]}" -gt 0 ]; then
      seen_repo["${repo}"]=1
      for x in "${extras[@]}"; do
        v="${s_ver[${repo}|${x}]:-}"; [ -n "${v}" ] || continue
        [ -f "${tmp}/${repo}/${x}-${v}/depends" ] \
          || die "sync db ${repo} has no depends entry for ${x} ${v} — the extras guard would be vacuous"
        x_deps["${repo}|${x}"]="$(awk '/^%DEPENDS%$/{f=1;next} /^%[A-Z]+%$/{f=0} f&&NF' \
          "${tmp}/${repo}/${x}-${v}/depends" | paste -sd' ' -)"
      done
      while IFS='|' read -r provider token; do
        provider="${provider%-*-*}"
        [ -n "${want[${provider}]:-}" ] || continue    # only hosted packages can satisfy anything
        prov["${token%%[<>=]*}"]="${provider}"
      done < <(awk '/^%PROVIDES%$/{f=1;next} /^%[A-Z]+%$/{f=0}
                    f&&NF{n=split(FILENAME,a,"/"); print a[n-1]"|"$0}' "${tmp}/${repo}"/*/depends)
    fi
    rm -rf "${tmp:?}/${repo}"
  done
done

# Shadowed ALARM copies: bootstrap installs ALARM's mesa/vulkan-freedreno from
# base.list and our epoch'd [pocknix] builds upgrade over them, so the snapshot
# must carry the ALARM copies too or a pinned build dies at "target not found".
# Cache presence alone can NOT identify them — pacman caches file:// installs
# too, so once a [pocknix] package lands in a chroot as a makepkg dep its own
# file appears here (seen: pocknix-base pulled into the manifest, then failing
# its mirror fetch). The sync dbs are the discriminator: only a version that an
# ALARM repo actually carries is base material.
for src in "${sources[@]}"; do
  for f in "${src}"/var/cache/pacman/pkg/*.pkg.tar.*; do
    case "${f}" in *.sig) continue ;; esac
    b="$(basename "${f}")"; b="${b%-*}"                     # drop -<arch>.pkg.tar.*
    name="${b%-*-*}"; ver="${b#"${name}-"}"
    [ -n "${ours[${name}]:-}" ] || continue
    [ -n "${want[${name}]:-}" ] && continue
    case "${f_repo[${name} ${ver}]:-}" in
      core|extra|alarm|aur) ;;
      *) continue ;;                                        # ours, not an ALARM copy
    esac
    want["${name}"]="${ver}"
    log "including shadowed ALARM copy: ${name} ${ver} (replaced by [pocknix] at install time)"
  done
done

# pacman's own repo precedence (pacman.conf.in order), not the glob order the dbs
# were read in: [alarm] sorts first but loses to core/extra at install time.
extras_unknown="" extras_deps=""
for x in ${extras[@]+"${extras[@]}"}; do
  if [ -n "${want[${x}]:-}" ]; then
    warn "extra ${x} is already part of the installed base — drop it from base-extras.list"
    continue
  fi
  xrepo=""
  for r in core extra alarm aur; do
    [ -n "${s_ver[${r}|${x}]:-}" ] && { xrepo="${r}"; break; }
  done
  [ -n "${xrepo}" ] || { extras_unknown+="  ${x}"$'\n'; continue; }
  want["${x}"]="${s_ver[${xrepo}|${x}]}"
  log "hosting extra: ${x} ${want[${x}]} (${xrepo}) — not installed by any build"
done
[ -z "${extras_unknown}" ] || die "base-extras.list names packages no sync db carries (typo, or ALARM renamed/dropped them):
${extras_unknown}"

# Second pass so one extra may depend on another. Served = ours (both our repos are
# enabled on every device), hosted, or provided by something hosted.
for x in ${extras[@]+"${extras[@]}"}; do
  for r in core extra alarm aur; do
    [ -n "${s_ver[${r}|${x}]:-}" ] && { xrepo="${r}"; break; }
  done
  for dep in ${x_deps[${xrepo}|${x}]:-}; do
    dep="${dep%%[<>=]*}"
    [ -n "${ours[${dep}]:-}" ] && continue
    [ -n "${want[${dep}]:-}" ] && continue
    [ -n "${prov[${dep}]:-}" ] && continue
    extras_deps+="  ${dep} (needed by ${x})"$'\n'
  done
done
[ -z "${extras_deps}" ] || die "extras' dependencies are not hosted — they would not install on a locked device:
${extras_deps}
Add them to config/packages/base-extras.list (hosted only). If the package
belongs in the image instead, add it to base.list (ALARM bootstrap) or to a
layer metapackage's depends= (packages/shared/pocknix-*), then re-run."

# --- layer completeness ------------------------------------------------------
# A layer's ALARM deps reach the base only because every build installs all four
# layers; an image that drops one (#48) would silently strip them from the snapshot.
layer_missing=""
for _meta in "${PACKAGES_DIR}"/shared/pocknix-core/PKGBUILD \
             "${PACKAGES_DIR}"/shared/pocknix-*-full/PKGBUILD; do
  [ -f "${_meta}" ] || continue
  _deps="$(bash -c 'depends=(); source "$1" >/dev/null 2>&1; printf "%s\n" "${depends[@]}"' _ "${_meta}" 2>/dev/null)"
  [ -n "${_deps}" ] || die "cannot read depends= from ${_meta} — the layer guard would be vacuous"
  while read -r _dep; do
    _dep="${_dep%%[<>=]*}"
    [ -n "${_dep}" ] || continue
    [ -n "${ours[${_dep}]:-}" ] && continue
    [ -n "${want[${_dep}]:-}" ] && continue
    [ -n "${prov[${_dep}]:-}" ] && continue
    layer_missing+="  ${_dep} (needed by $(basename "$(dirname "${_meta}")"))"$'\n'
  done <<< "${_deps}"
done
[ -z "${layer_missing}" ] || die "a layer metapackage names ALARM packages the base would not host:
${layer_missing}
The image must have stopped installing that layer, so the harvest no longer sees
its deps. Name them in config/packages/base-extras.list (hosted, not installed)
so the layer stays installable, then re-run."

missing=""
for name in "${!want[@]}"; do
  key="${name} ${want[${name}]}"
  [ -n "${f_file[${key}]:-}" ] || missing+="  ${name} ${want[${name}]}"$'\n'
done
[ -z "${missing}" ] || die "installed versions not found in any sync db (ALARM published mid-build?).
Re-run the build so installed versions match the refreshed dbs, then snapshot again:
${missing}"

# --- gather files: build caches first, mirror for the residue ----------------
# The pacman caches in the rootfs + chroots hold the EXACT bytes pacman verified
# and installed — harvesting them closes the build-to-snapshot race (a mirror
# re-download 404s if ALARM bumps a package in between). Only packages that
# never hit a cache (tarball-preinstalled, never upgraded) come from the mirror.
mkdir -p "${OUT}" 2>/dev/null || die "${OUT} not creatable — one-time: sudo install -d -o $(id -un) ${BUILD_DIR}/snapshot"
cachedirs=()
for src in "${sources[@]}"; do cachedirs+=("${src}/var/cache/pacman/pkg"); done
curlcfg="${tmp}/curl.cfg"; shafile="${tmp}/sha.check"
todl=0 cached=0
for name in "${!want[@]}"; do
  key="${name} ${want[${name}]}"
  fn="${f_file[${key}]}"; repo="${f_repo[${key}]}"
  printf '%s  %s\n' "${f_sha[${key}]}" "${OUT}/${fn}" >> "${shafile}"
  for cdir in "${cachedirs[@]}"; do
    if [ ! -s "${OUT}/${fn}" ] && [ -f "${cdir}/${fn}" ]; then
      cp "${cdir}/${fn}" "${OUT}/"; cached=$((cached+1))
    fi
    if [ ! -s "${OUT}/${fn}.sig" ] && [ -f "${cdir}/${fn}.sig" ]; then
      cp "${cdir}/${fn}.sig" "${OUT}/"
    fi
  done
  for suffix in "" ".sig"; do
    [ -s "${OUT}/${fn}${suffix}" ] && continue   # resumable: keep cache-copied/prior files
    printf 'url = "%s/%s/%s%s"\noutput = "%s/%s%s"\n' \
      "${POCKNIX_ALARM_PKG_MIRROR}" "${repo}" "${fn}" "${suffix}" "${OUT}" "${fn}" "${suffix}" >> "${curlcfg}"
    todl=$((todl+1))
  done
done
log "sourced ${cached} packages from the build's own pacman caches"
if [ -s "${curlcfg}" ]; then
  log "downloading ${todl} residual files from ${POCKNIX_ALARM_PKG_MIRROR} (parallel)"
  # -L: the ALARM mirror front 302s to geo mirrors; --remove-on-error: parallel
  # mode pre-creates output files, which would otherwise survive empty on failure
  curl -sS --fail -L --remove-on-error --retry 3 --parallel --parallel-max 8 --config "${curlcfg}" \
    || warn "curl reported failures — the verify pass below will name anything unusable"
fi
log "verifying ${#want[@]} package checksums against the sync dbs"
sha256sum --quiet -c "${shafile}" || die "checksum failures above — mirror moved mid-run? delete the bad files in ${OUT} and re-run"
for name in "${!want[@]}"; do
  fn="${f_file[${name} ${want[${name}]}]}"
  [ -s "${OUT}/${fn}.sig" ] || die "missing signature ${fn}.sig — re-run (mirror should serve it)"
done

# OUT is resumable, so an aborted earlier attempt can leave packages this run no
# longer wants; repo-add and the closing rclone sync would publish them anyway.
declare -A keepfile
for name in "${!want[@]}"; do
  fn="${f_file[${name} ${want[${name}]}]}"
  keepfile["${fn}"]=1; keepfile["${fn}.sig"]=1
done
for f in "${OUT}"/*.pkg.tar.*; do
  [ -e "${f}" ] || continue
  b="$(basename "${f}")"
  [ -n "${keepfile[${b}]:-}" ] && continue
  log "dropping leftover from an aborted run: ${b}"
  rm -f "${f}"
done

# --- the exact base tarball, dated + hashed ----------------------------------
[ -f "${CACHE_DIR}/${ALARM_TARBALL}" ] || die "no cached tarball ${CACHE_DIR}/${ALARM_TARBALL} — the snapshot must ship the tarball the build used"
cp -f "${CACHE_DIR}/${ALARM_TARBALL}" "${OUT}/${DATED_TARBALL}"
TARBALL_SHA="$(sha256sum "${OUT}/${DATED_TARBALL}" | awk '{print $1}')"
# seed the cache under the pinned name so the next local build doesn't re-fetch
cp -f "${CACHE_DIR}/${ALARM_TARBALL}" "${CACHE_DIR}/${DATED_TARBALL}" 2>/dev/null \
  || warn "couldn't seed ${DATED_TARBALL} into ${CACHE_DIR} (root-owned?) — next build downloads it from the snapshot once"

# --- fresh repo db over exactly what we host ---------------------------------
# Never copy ALARM's own db: it lists ~13k packages while we host ~900, and
# pacman would resolve to entries that 404. LC_ALL=C: quiet bsdtar locale warns.
log "building ${BASE_DB} (repo-add over ${#want[@]} packages)"
( cd "${OUT}" && rm -f "${BASE_DB}" pocknix-base.db pocknix-base.files* \
  && ls *.pkg.tar.* | grep -v '\.sig$' | LC_ALL=C xargs repo-add -q "${BASE_DB}" ) \
  || die "repo-add failed"

# --- lockfile ----------------------------------------------------------------
# Header is machine-read: pocknix-base-lock's PKGBUILD takes its pkgver from the
# snapshot id here, so the device's "which base am I on" answer can never
# disagree with the manifest it ships.
{
  printf '# pocknix-base.lock - ALARM base snapshot %s (%d packages)\n' "${ID}" "${#want[@]}"
  printf '# Generated by scripts/snapshot-base.sh (make snapshot); shipped by pocknix-base-lock.\n'
  for name in "${!want[@]}"; do printf '%s %s\n' "${name}" "${want[${name}]}"; done | sort
} > "${OUT}/pocknix-base.lock"

# Published alongside the base so a re-run can tell "the live base is already
# this snapshot" from "the live base is the previous release" (see the rotation).
printf '%s\n' "${ID}" > "${OUT}/SNAPSHOT_ID"

# Same id, different contents would republish pocknix-base-lock-<id>-1 with new
# bytes: devices never see the upgrade (same version) and the package that IS
# the device's record of its base would report one it isn't on. Suffix instead.
if [ -f "${LOCKFILE}" ] \
   && [ "$(sed -n 's/^#.*snapshot \([0-9][0-9.]*\).*/\1/p' "${LOCKFILE}" | head -1)" = "${ID}" ] \
   && ! diff -q <(grep -v '^#' "${LOCKFILE}") <(grep -v '^#' "${OUT}/pocknix-base.lock") >/dev/null; then
  die "snapshot ${ID} already exists with DIFFERENT contents — re-run with a distinct id:
  POCKNIX_SNAPSHOT_ID=${ID}.1 make snapshot"
fi

if [ -n "${POCKNIX_SNAPSHOT_NO_UPLOAD:-}" ]; then
  cp -f "${OUT}/pocknix-base.lock" "${LOCKFILE}"
  ok "dry run: snapshot dir ready at ${OUT} ($(du -sh "${OUT}" | cut -f1)); lockfile written, nothing uploaded, conf NOT pinned"
  exit 0
fi

# --- publish: rotate the outgoing base, then replace it ----------------------
[ -n "${RCLONE_DEST}" ] || die "POCKNIX_BASE_RCLONE_REMOTE unset — cannot upload"
need_tool rclone
if [ -n "$(rclone lsf --max-depth 1 "${RCLONE_DEST}" 2>/dev/null | head -1)" ]; then
  # A re-run after a failed publish must NEVER rotate: the live base is then this
  # same (half-written) snapshot, and copying it over -prev destroys the previous
  # release's only rebuild source. Equal ids = resume; unknown/older id = real rotation.
  live_id="$(rclone cat "${RCLONE_DEST}/SNAPSHOT_ID" 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [ "${live_id}" = "${ID}" ]; then
    warn "live base is ALREADY snapshot ${ID} — resuming a previous publish, NOT rotating (${RCLONE_PREV} keeps the last release)"
  else
    log "rotating the current base (${live_id:-id unknown}) -> ${RCLONE_PREV} (keeps the PREVIOUS release rebuildable)"
    rclone sync --checksum "${RCLONE_DEST}" "${RCLONE_PREV}"
  fi
fi
log "publishing -> ${RCLONE_DEST} ($(du -sh "${OUT}" | cut -f1))"
# packages + tarball first, db + lock LAST: a client syncing mid-publish sees
# either the old db (its packages all still present) or the new one (ditto).
# -L: repo-add's pocknix-base.db is a symlink. The closing sync prunes the
# superseded package versions, which by then no live db references.
# SNAPSHOT_ID goes up FIRST, before anything else is mutated: from here on any
# interruption leaves the remote id equal to ours, so a re-run skips the rotation.
rclone copy --include 'SNAPSHOT_ID' "${OUT}" "${RCLONE_DEST}"
rclone copy --include '*.pkg.tar.*' "${OUT}" "${RCLONE_DEST}"
rclone copy --include "${DATED_TARBALL}" "${OUT}" "${RCLONE_DEST}"
rclone copy -L --include 'pocknix-base.db*' --include 'pocknix-base.files*' \
  --include 'pocknix-base.lock' "${OUT}" "${RCLONE_DEST}"
rclone sync -L "${OUT}" "${RCLONE_DEST}"

# --- pin the checkout --------------------------------------------------------
# POCKNIX_BASE_URL is NOT pinned here: it is stable across snapshots by design.
cp -f "${OUT}/pocknix-base.lock" "${LOCKFILE}"
conf="${POCKNIX_ROOT}/config/pocknix.conf"
sed -i \
  -e "s|^: \"\${POCKNIX_BASE_SNAPSHOT:=.*}\"|: \"\${POCKNIX_BASE_SNAPSHOT:=${ID}}\"|" \
  -e "s|^: \"\${ALARM_TARBALL:=.*}\"|: \"\${ALARM_TARBALL:=${DATED_TARBALL}}\"|" \
  -e "s|^: \"\${POCKNIX_ALARM_SHA256:=.*}\"|: \"\${POCKNIX_ALARM_SHA256:=${TARBALL_SHA}}\"|" \
  -e "s|^: \"\${POCKNIX_ALARM_TARBALL_URL:=.*}\"|: \"\${POCKNIX_ALARM_TARBALL_URL:=${POCKNIX_BASE_URL}/${DATED_TARBALL}}\"|" \
  "${conf}"
ok "snapshot ${ID}: ${#want[@]} packages published to ${RCLONE_DEST} (previous kept at ${RCLONE_PREV})"
ok "pinned: config/pocknix.conf + ${LOCKFILE#"${POCKNIX_ROOT}/"} — rebuild pocknix-base-lock, review, commit"
