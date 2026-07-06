#!/usr/bin/env bash
# publish-repo.sh — sign build/localrepo and publish it as the public [pocknix] repo.
#
# The localrepo IS already a complete pacman repo (packages + pocknix.db from repo-add,
# maintained by build-packages.sh); publishing is: detach-sign every package, re-add them
# to a signed database, export the public key alongside, and sync the directory to the
# host (rclone remote, e.g. Cloudflare R2). Devices with the [pocknix] stanza + the
# lsigned key then update with plain `pacman -Syu`.
#
# Config (config/pocknix.conf or env):
#   POCKNIX_REPO_GPG_KEY        signing key id/email (required unless --unsigned)
#   POCKNIX_REPO_RCLONE_REMOTE  rclone destination (optional: skip upload if empty)
#
# Modes:
#   (default)    sign + repo-add --sign + upload (if a remote is configured)
#   --unsigned   skip signing (LAN-testing only — pair with SigLevel Optional TrustAll)
#   --serve      after preparing, serve the repo over LAN http :8000 (foreground;
#                point the device at http://<this-host>:8000 for testing)
#
# NB: localrepo files are root-owned (they were copied out of the build chroot). Run
# this as the user who owns your GPG key and use sudo only if the .sig writes fail.
# Never republish the same package filename with different bytes — bump pkgrel instead
# (client caches + signatures break otherwise).

source "$(dirname "$0")/lib.sh"

LOCALREPO="${BUILD_DIR}/localrepo"
REPO_DB="pocknix.db.tar.gz"
unsigned=0 serve=0
for a in "$@"; do
  case "$a" in
    --unsigned) unsigned=1 ;;
    --serve)    serve=1 ;;
    *) die "unknown arg: $a (known: --unsigned --serve)" ;;
  esac
done

[ -d "${LOCALREPO}" ] || die "no ${LOCALREPO} — run 'make packages' first"
shopt -s nullglob
# package files, excluding detached signatures (which match the same glob)
pkgs=()
for p in "${LOCALREPO}"/*.pkg.tar.*; do [[ "$p" == *.sig ]] || pkgs+=("$p"); done
[ "${#pkgs[@]}" -gt 0 ] || die "no packages in ${LOCALREPO}"

if [ "${unsigned}" -eq 0 ]; then
  [ -n "${POCKNIX_REPO_GPG_KEY}" ] || die "POCKNIX_REPO_GPG_KEY unset (or pass --unsigned for LAN testing)
  one-time key setup: gpg --quick-gen-key 'Pocknix Packaging <you@example.com>' ed25519 sign 2y"
  need_tool gpg
  log "signing ${#pkgs[@]} packages with ${POCKNIX_REPO_GPG_KEY}"
  for p in "${pkgs[@]}"; do
    # re-sign only when missing or older than the package (idempotent republish)
    if [ ! -f "${p}.sig" ] || [ "${p}" -nt "${p}.sig" ]; then
      gpg --detach-sign --no-armor --yes -u "${POCKNIX_REPO_GPG_KEY}" "${p}" \
        || die "gpg sign failed for ${p} (root-owned file? chown or sudo -E)"
    fi
  done
  log "rebuilding signed repo database"
  ( cd "${LOCALREPO}" && repo-add --sign --key "${POCKNIX_REPO_GPG_KEY}" -q "${REPO_DB}" "${pkgs[@]}" ) \
    || die "repo-add --sign failed (is repo-add installed? 'pacman' package on the VM)"
  # export the public key next to the repo so devices can fetch + lsign it
  gpg --export --armor "${POCKNIX_REPO_GPG_KEY}" > "${LOCALREPO}/pocknix-repo.gpg"
  ok "signed: packages + ${REPO_DB} + pocknix-repo.gpg"
else
  warn "publishing UNSIGNED (LAN testing only — device stanza needs SigLevel = Optional TrustAll)"
fi

if [ -n "${POCKNIX_REPO_RCLONE_REMOTE}" ]; then
  need_tool rclone
  log "syncing -> ${POCKNIX_REPO_RCLONE_REMOTE}"
  # order matters for a window-free publish: packages+sigs first, database last, so a
  # client never sees a db entry whose package isn't uploaded yet
  rclone copy --include '*.pkg.tar.*' "${LOCALREPO}" "${POCKNIX_REPO_RCLONE_REMOTE}"
  rclone copy --include 'pocknix.db*' --include 'pocknix.files*' --include 'pocknix-repo.gpg' \
    "${LOCALREPO}" "${POCKNIX_REPO_RCLONE_REMOTE}"
  # prune package versions that no longer exist locally (keeps the bucket bounded)
  rclone sync "${LOCALREPO}" "${POCKNIX_REPO_RCLONE_REMOTE}"
  ok "published to ${POCKNIX_REPO_RCLONE_REMOTE}"
else
  warn "POCKNIX_REPO_RCLONE_REMOTE unset — nothing uploaded (repo prepared in ${LOCALREPO})"
fi

if [ "${serve}" -eq 1 ]; then
  need_tool python3
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  log "serving ${LOCALREPO} on http://${ip:-<this-host>}:8000 (Ctrl-C to stop)"
  log "device stanza:  [pocknix]  SigLevel = Optional TrustAll  Server = http://${ip:-<vm-ip>}:8000"
  python3 -m http.server 8000 -d "${LOCALREPO}"
fi
