#!/usr/bin/env bash
# check.sh — sanity-check the project + (when present) the built artifacts.

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
for d in config config/packages scripts packages/shared packages/soc packages/gpu "devices/${DEVICE}"; do
  [ -d "${POCKNIX_ROOT}/${d}" ] && note "dir: ${d}/" "ok" || { note "dir: ${d}/" "MISSING"; fail=1; }
done

# --- package placement: shared/ vs soc/ vs gpu/ ----------------------------
# The dir names the build scope: shared/ builds once into [pocknix-shared], soc/ per SoC
# gated by ./socs, gpu/ per SoC gated by ./gpus against its profile's GPU_GEN. A PKGBUILD
# elsewhere is invisible to the build, a missing or unknown gate silently drops a package
# from every repo, and another dir's gate file means the package sits in the wrong dir.
while IFS= read -r p; do
  note "package: ${p#"${POCKNIX_ROOT}"/}" "OUTSIDE shared/, soc/ and gpu/: never built"; fail=1
done < <(find "${POCKNIX_ROOT}/packages" -maxdepth 3 -name PKGBUILD \
           ! -path "*/packages/shared/*" ! -path "*/packages/soc/*" ! -path "*/packages/gpu/*" 2>/dev/null)
_gens=" $(for _d in "${POCKNIX_ROOT}"/devices/*/profile.conf; do profile_get "${_d%/profile.conf}" GPU_GEN; echo; done | sort -u | paste -sd ' ' -) "
for p in "${POCKNIX_ROOT}"/packages/gpu/*/; do
  [ -d "${p}" ] || continue
  n="$(basename "${p}")"
  [ ! -f "${p}/socs" ] || { note "gpu pkg: ${n}" "has a socs file (per-SoC packages live in packages/soc/)"; fail=1; continue; }
  [ -f "${p}/gpus" ] || { note "gpu pkg: ${n}" "MISSING gpus file"; fail=1; continue; }
  read -r _gpus < "${p}/gpus" || true   # a 0-byte file fails read; the empty check reports it
  bad=0
  for g in ${_gpus}; do
    case "${_gens}" in *" ${g} "*) ;; *) note "gpu pkg: ${n}" "gpus names '${g}', which no profile's GPU_GEN is"; fail=1; bad=1 ;; esac
  done
  [ -n "${_gpus}" ] || { note "gpu pkg: ${n}" "empty gpus file"; fail=1; bad=1; }
  [ "${bad}" -eq 0 ] && note "gpu pkg: ${n}" "gpus: ${_gpus}"
done
for p in "${POCKNIX_ROOT}"/packages/soc/*/; do
  [ -d "${p}" ] || continue
  n="$(basename "${p}")"
  [ ! -f "${p}/gpus" ] || { note "soc pkg: ${n}" "has a gpus file (GPU-gated packages live in packages/gpu/)"; fail=1; continue; }
  if [ ! -f "${p}/socs" ]; then
    note "soc pkg: ${n}" "MISSING socs file"; fail=1; continue
  fi
  read -r _socs < "${p}/socs" || true
  [ -n "${_socs}" ] || { note "soc pkg: ${n}" "empty socs file"; fail=1; continue; }
  bad=0
  # "all" = every kernel/<soc>, so a new SoC needs no socs edits; it never mixes with names.
  if [ "${_socs}" = all ]; then note "soc pkg: ${n}" "socs: all"; continue; fi
  for s in ${_socs}; do
    [ -f "${POCKNIX_ROOT}/kernel/${s}/kernel.conf" ] || { note "soc pkg: ${n}" "unknown SoC '${s}' in socs"; fail=1; bad=1; }
  done
  [ "${bad}" -eq 0 ] && note "soc pkg: ${n}" "socs: ${_socs}"
done
for p in "${POCKNIX_ROOT}"/packages/shared/*/socs "${POCKNIX_ROOT}"/packages/shared/*/gpus; do
  [ -e "${p}" ] || continue
  note "shared pkg: $(basename "$(dirname "${p}")")" "has a ${p##*/} file (shared builds are SoC-blind: move it to packages/soc/ or packages/gpu/, or delete the file)"; fail=1
done

# A package we author ships under the repo's license; repackaged third-party content keeps
# its upstream license and names it in a comment on the license= line.
_lic=""
while IFS= read -r _f; do
  _l="$(grep -n '^license=' "${POCKNIX_ROOT}/${_f}" | head -1)"
  case "${_l#*:}" in "license=('GPL-2.0-or-later')"|*"#"*) continue ;; esac
  _lic="${_lic} ${_f}:${_l%%:*}"
done < <(git -C "${POCKNIX_ROOT}" grep -l -F 'url="https://github.com/shuuri-labs/pocknix-os"' \
           -- 'packages/shared/*/PKGBUILD' 'packages/soc/*/PKGBUILD' 'packages/gpu/*/PKGBUILD' 'devices/*/PKGBUILD')
if [ -z "${_lic}" ]; then note "package licenses" "ok"
else note "package licenses" "not GPL-2.0-or-later and no '# <third-party>' note:${_lic}"; fail=1; fi
for f in config/pocknix.conf config/pacman.conf.in config/packages/base.list \
         "devices/${DEVICE}/profile.conf" "kernel/${SOC}/kernel.conf"; do
  [ -f "${POCKNIX_ROOT}/${f}" ] && note "file: ${f}" "ok" || { note "file: ${f}" "MISSING"; fail=1; }
done
note "device" "${DEVICE} (${DEVICE_PRETTY:-?}) on ${SOC}"

# Prints "<field>=<entry>" for each replaces=/conflicts= entry in PKGBUILD $1. Shared PKGBUILDs
# run nothing at top level and have no split bodies, so sourcing reads them exactly.
pkg_relations() {
  ( set +eu; . "$1" >/dev/null 2>&1
    printf 'replaces=%s\n' "${replaces[@]}"; printf 'conflicts=%s\n' "${conflicts[@]}" ) | grep -v '=$' || true
}

# Prints one problem per line: a relation in shared dir $1 with no row in allow file $2, or a
# row whose relation is gone. $1/$2 let the self-test point it at doctored copies.
check_shared_relations() {  # $1 = packages/shared dir, $2 = allow file
  local f p e r rest rows="" have=""
  while IFS= read -r r; do
    case "${r}" in ''|'#'*) continue ;; esac
    p="${r%% :: *}"; rest="${r#* :: }"; e="${rest%% :: *}"
    case "${rest}" in *' :: '?*) rows="${rows}${p} ${e}"$'\n' ;; *) echo "${2##*/}: malformed row '${r}'" ;; esac
  done < "$2"
  for f in "$1"/*/PKGBUILD; do
    p="${f%/PKGBUILD}"; p="${p##*/}"
    for e in $(pkg_relations "${f}"); do
      have="${have}${p} ${e}"$'\n'
      printf '%s' "${rows}" | grep -qxF "${p} ${e}" || echo "${p}: ${e} has no row in ${2##*/}"
    done
  done
  while read -r p e; do
    printf '%s' "${have}" | grep -qxF "${p} ${e}" || echo "${2##*/}: '${p} :: ${e}' matches no PKGBUILD entry"
  done < <(printf '%s' "${rows}")
}

# [pocknix-shared] reaches every SoC's fleet in one publish, and replaces= uninstalls on -Syu, so
# each such entry in a shared package names its reason in scripts/shared-conflicts.allow.
_allow="${POCKNIX_ROOT}/scripts/shared-conflicts.allow"
_bad="$(check_shared_relations "${POCKNIX_ROOT}/packages/shared" "${_allow}" | paste -sd ';' -)"
if [ -z "${_bad}" ]; then note "shared replaces/conflicts" "ok"
else note "shared replaces/conflicts" "${_bad}"; fail=1; fi
_t="$(mktemp -d)"
mkdir -p "${_t}/stray"
printf "pkgname=stray\nreplaces=('gone'\n  # a comment\n  'old<1')\n" > "${_t}/stray/PKGBUILD"
_out="$(check_shared_relations "${_t}" "${_allow}")"
if printf '%s\n' "${_out}" | grep -q '^stray: replaces=old<1 has no row'; then
  note "shared replaces/conflicts self-test" "ok"
else note "shared replaces/conflicts self-test" "a shared replaces= with no allow row went unflagged"; fail=1; fi
rm -rf "${_t}"

# --- scripts executable ----------------------------------------------------
for s in sync.sh bootstrap.sh build-image.sh build-kernel.sh build-packages.sh \
         build-sd-image.sh stage-repo.sh stage-check.sh publish-repo.sh install.sh check.sh check-docs.sh render-bsp.sh; do
  [ -x "${POCKNIX_ROOT}/scripts/${s}" ] && note "exec: scripts/${s}" "ok" || { note "exec: scripts/${s}" "not +x"; fail=1; }
done

# --- pocknix-perfd factory profiles ---------------------------------------
if out="$(python3 "${POCKNIX_ROOT}/scripts/check-power-profiles.py" 2>&1)"; then note "power profiles" "ok"
else note "power profiles" "BROKEN"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi

# --- speaker DSP profiles: every board's profile exists, parses and renders ---
if out="$(python3 "${POCKNIX_ROOT}/scripts/check-speaker-dsp.py" 2>&1)"; then note "speaker DSP profiles" "ok"
else note "speaker DSP profiles" "BROKEN"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi

# --- code comments: no dead repo paths, provenance or ledger facts ------------
if out="$(python3 "${POCKNIX_ROOT}/scripts/check-comments.py" 2>&1)"; then note "code comments" "ok"
else note "code comments" "STALE"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi

# --- SoC families: what a new SoC or board must carry (all SoCs, not just DEVICE) ----
# An unreferenced board never loads.
# devices/README.md's key table as "<key> required|optional" (the Absent column says "required"
# or what an absent key means) plus its "Env overrides" names as "<key> env". A table that stops
# parsing empties REQUIRED_KEYS, which the family-key loop below fails on.
_doc="${POCKNIX_ROOT}/devices/README.md"
_keys="$(awk -F'|' '/^\| `POCKNIX_/ { k = $2; a = $4; gsub(/^ +| +$/, "", a)
           while (match(k, /POCKNIX_[A-Z0-9_]+/)) { print substr(k, RSTART, RLENGTH), (a == "required" ? "required" : "optional"); k = substr(k, RSTART + RLENGTH) } }' "${_doc}"
         sed -n '/^Env overrides/,/^$/p' "${_doc}" | grep -oE 'POCKNIX_[A-Z0-9_]+' | sed 's/$/ env/' || true)"

# Prints "<key> <file>" for each POCKNIX_* name that device.conf consumers $@ expand but never
# assign: assigned names are the script's own state, not keys.
contract_reads() {  # $@ = consumer files
  local f k
  for f in "$@"; do
    for k in $(grep -oE '\$\{?POCKNIX_[A-Z0-9_]+' "${f}" | sed -E 's/^\$\{?//' | sort -u); do
      grep -qE "(^|[[:space:];])(export[[:space:]]+)?${k}=" "${f}" || echo "${k} ${f#"${POCKNIX_ROOT}"/}"
    done
  done
}

# Prints one problem per line: a name consumers $2.. read that the key list $1 lacks.
check_contract() {  # $1 = "<key> <kind>" lines, $2.. = consumer files
  local known="$1" k f
  shift
  contract_reads "$@" | while read -r k f; do
    printf '%s\n' "${known}" | grep -q "^${k} " || echo "${f} reads ${k}, which devices/README.md's key table lacks"
  done
}

# The consumers are whatever names device.conf or cores.sh, so a key a script starts reading
# must get a table row saying whether every board sets it.
mapfile -t _consumers < <(cd "${POCKNIX_ROOT}" && git grep -l -F -e /usr/lib/pocknix/device.conf \
  -e /usr/lib/pocknix/cores.sh -- packages devices overlay ':!*/PKGBUILD' | sed "s|^|${POCKNIX_ROOT}/|")
_bad="$(check_contract "${_keys}" "${_consumers[@]}" | paste -sd ';' -)"
if [ -z "${_bad}" ]; then note "device.conf keys vs consumers" "ok (${#_consumers[@]} consumers)"
else note "device.conf keys vs consumers" "${_bad}"; fail=1; fi
_t="$(mktemp -d)"
printf '. /usr/lib/pocknix/device.conf\necho "${POCKNIX_PANEL_W:-1080} ${POCKNIX_BOGUS:-x}"\n' > "${_t}/stray"
_out="$(check_contract "${_keys}" "${_t}/stray")"
if printf '%s\n' "${_out}" | grep -q 'reads POCKNIX_BOGUS, which' && ! printf '%s\n' "${_out}" | grep -q PANEL_W; then
  note "device.conf keys self-test" "ok"
else note "device.conf keys self-test" "a consumer reading an undocumented key went unflagged"; fail=1; fi
rm -rf "${_t}"

# Lays out boards dir $1 as family $2's BSP installs it (with what scripts/render-bsp.sh renders:
# device.conf and family.conf) in a scratch dir (printed). Installed paths point into it, so
# nested sources (variant -> base -> family.conf) and the dispatcher resolve against the tree.
stage_boards() {  # $1 = boards dir, $2 = SoC
  local t r f dev="${POCKNIX_ROOT}/devices/$2"
  t="$(mktemp -d)"; r="$(mktemp -d)"
  BOOTLOADER="$(profile_get "${dev}" BOOTLOADER)" SD_FAT_LABEL="$(profile_get "${dev}" SD_FAT_LABEL)" \
    ROOT_LABEL="$(profile_get "${dev}" ROOT_LABEL)" "${POCKNIX_ROOT}/scripts/render-bsp.sh" "$1" "${r}" ||
    { rm -rf "${t}" "${r}"; return 1; }
  for f in "$1"/*.conf "${r}"/*.conf; do
    sed -e "s|/usr/lib/pocknix/boards/|${t}/|g" -e "s|/proc/device-tree/model|${t}/model|g" "${f}" > "${t}/${f##*/}"
  done
  rm -rf "${r}"
  printf '%s' "${t}"
}

# Prints "<key>=<value>" for each POCKNIX_* key board $3 of family $2 resolves from boards dir $1.
board_values() {  # $1 = boards dir, $2 = SoC, $3 = board
  local t rc=0
  t="$(stage_boards "$1" "$2")" || return 1
  env -i bash -c '. "$1" >/dev/null || exit 1; for k in ${!POCKNIX_@}; do printf "%s=%s\n" "${k}" "${!k}"; done' sh "${t}/$3.conf" || rc=1
  rm -rf "${t}"
  return "${rc}"
}

# A consumer missing a key runs on its fallback, so a required key's must be the reference
# board's value and an optional key's must change nothing (0 or empty). A fallback naming
# another variable defers to it and is skipped. Allow file $3 rows ("<key> :: <reason>") are the
# exceptions; a row that matches no fallback fails, so the list only shrinks.
check_fallbacks() {  # $1 = "<key> <kind>" lines, $2 = "<key>=<value>" reference, $3 = allow file, $4.. = consumers
  local known="$1" ref="$2" allow="$3" f k v kind want r used=" "
  shift 3
  while IFS= read -r r; do
    f="${r%%:\$\{*}"; r="${r#*\$\{}"; k="${r%%:-*}"; v="${r#*:-}"; v="${v%\}}"
    kind="$(printf '%s\n' "${known}" | awk -v k="${k}" '$1 == k { print $2; exit }')"
    case "${kind}" in required|optional) ;; *) continue ;; esac
    if grep -q "^${k} :: " "${allow}"; then used="${used}${k} "; continue; fi
    if [ "${kind}" = required ]; then
      want="$(printf '%s\n' "${ref}" | sed -n "s/^${k}=//p")"
      [ "${v}" = "${want}" ] || echo "${f#"${POCKNIX_ROOT}"/}: required ${k} falls back to '${v}', the reference board has '${want}'"
    else
      case "${v}" in ''|0) ;; *) echo "${f#"${POCKNIX_ROOT}"/}: optional ${k} falls back to '${v}', not 0 or empty" ;; esac
    fi
  done < <(grep -oHE '\$\{POCKNIX_[A-Z0-9_]+:-[^${}]*\}' "$@")
  while IFS= read -r r; do
    case "${r}" in ''|'#'*) continue ;; esac
    case "${used}" in *" ${r%% :: *} "*) ;; *) echo "${allow##*/}: '${r%% :: *}' matches no fallback" ;; esac
  done < "${allow}"
}

# The reference board is the committed default image target's fallback (first models row).
_ref_soc="$(sed -nE 's/^: "\$\{DEVICE:=([a-z0-9]+)\}".*/\1/p' "${POCKNIX_ROOT}/config/pocknix.conf")"
_ref_boards="${POCKNIX_ROOT}/devices/${_ref_soc}/packages/pocknix-bsp-${_ref_soc}/boards"
_ref_board="$(awk '!/^[[:space:]]*(#|$)/ { print $1; exit }' "${_ref_boards}/models" 2>/dev/null || true)"
_fb_allow="${POCKNIX_ROOT}/scripts/fallbacks.allow"
if [ -z "${_ref_board}" ]; then _bad="no reference board (config/pocknix.conf DEVICE default -> boards/models)"
elif ! _ref="$(board_values "${_ref_boards}" "${_ref_soc}" "${_ref_board}")"; then _bad="reference board ${_ref_board} fails to source"
else _bad="$(check_fallbacks "${_keys}" "${_ref}" "${_fb_allow}" "${_consumers[@]}" | paste -sd ';' -)"; fi
if [ -z "${_bad}" ]; then note "device.conf fallbacks" "ok (reference ${_ref_board})"
else note "device.conf fallbacks" "${_bad}"; fail=1; fi
_t="$(mktemp -d)"
printf '%s\n' 'w=${POCKNIX_PANEL_W:-1}' 'h=${POCKNIX_PANEL_H:-1920}' 'o=${POCKNIX_PANEL_OUTPUT:-DSI-9}' \
  'r=${POCKNIX_ROTATE:-${POCKNIX_DESKTOP_ROTATE:-left}}' > "${_t}/stray"
_out="$(check_fallbacks "${_keys}" $'POCKNIX_PANEL_W=1080\nPOCKNIX_PANEL_H=1920\nPOCKNIX_DESKTOP_ROTATE=left' \
          /dev/null "${_t}/stray")"
if grep -q "required POCKNIX_PANEL_W falls back to '1'" <<< "${_out}" && grep -q 'optional POCKNIX_PANEL_OUTPUT' <<< "${_out}" &&
   ! grep -qE 'PANEL_H|ROTATE' <<< "${_out}"; then note "device.conf fallbacks self-test" "ok"
else note "device.conf fallbacks self-test" "a wrong fallback went unflagged (or a right one was flagged)"; fail=1; fi
rm -rf "${_t}"

# family.conf must carry the SoC and the install-to-internal contract, and every board must
# resolve each key the table marks required from the two (the consumers fall back to RP6 values
# without one, which is wrong on any other panel or disk).
REQUIRED_FAMILY_KEYS="POCKNIX_SOC POCKNIX_INTERNAL_DISK POCKNIX_BOOT_GPT_NAME
  POCKNIX_BOOT_STYLE POCKNIX_BOOT_FAT_LABEL POCKNIX_ROOT_LABEL"
REQUIRED_KEYS="$(printf '%s\n' "${_keys}" | awk '$2 == "required" { print $1 }' | paste -sd ' ' -)"
for _k in ${REQUIRED_FAMILY_KEYS} POCKNIX_DEVICE; do
  case " ${REQUIRED_KEYS} " in *" ${_k} "*) ;;
    *) note "device.conf required keys" "${_k} is not marked required in devices/README.md"; fail=1 ;; esac
done

# Sources $2 with nothing else set; prints "<unset keys>|<POCKNIX_SOC>".
resolve_keys() {  # $1 = keys, $2 = file
  env -i bash -c '. "$1" >/dev/null || exit 1; for k in $2; do eval "[ -n \"\${${k}:-}\" ]" || printf "%s " "${k}"; done
    printf "|%s" "${POCKNIX_SOC:-}"' sh "$2" "${1//$'\n'/ }"
}

# Sources the rendered $1/device.conf as a board reporting model $2 (empty = no model file)
# and expects "<POCKNIX_DEVICE>|<POCKNIX_BOARD_UNKNOWN>" = $3, with nothing on stdout.
probe_model() {  # $1 = scratch dir, $2 = model, $3 = expected
  local got
  rm -f "$1/model"; [ -z "$2" ] || printf '%s\0' "$2" > "$1/model"
  got="$(env -i sh -c '. "$1" > "$1.out" || exit 1; printf "%s|%s" "${POCKNIX_DEVICE:-}" "${POCKNIX_BOARD_UNKNOWN:-}"' \
    sh "$1/device.conf")" || got="(fails)"
  [ "${got}" = "$3" ] || echo "device.conf: model '$2' gives ${got}, want $3"
  [ ! -s "$1/device.conf.out" ] || echo "device.conf: model '$2' prints to stdout"
}

# Prints one problem per line for a BSP's boards/; nothing means it is fine. $2 lets the
# self-test below point it at a doctored copy.
check_boards() {  # $1 = SoC, $2 = boards dir
  local soc="$1" boards="$2" t f n b m r rows="" first="" firstm="" got want
  for f in family.conf models; do
    [ -f "${boards}/${f}" ] || { echo "missing boards/${f}"; return; }
  done
  t="$(stage_boards "${boards}" "${soc}")" || { echo "scripts/render-bsp.sh fails for ${soc}"; return; }
  r="$(resolve_keys "${REQUIRED_FAMILY_KEYS}" "${t}/family.conf")" || echo "family.conf fails to source"
  m="${r%%|*}"; [ -z "${m}" ] || echo "family.conf lacks ${m% }"

  while read -r b m; do
    case "${b}" in ''|'#'*) continue ;; esac
    [ -n "${m}" ] || { echo "models: ${b} has no model"; continue; }
    case "${m}" in *[\"\\\$\`]*) echo "models: '${m}' would need shell quoting" ;; esac
    [ -f "${boards}/${b}.conf" ] || echo "models: '${m}' names a missing boards/${b}.conf"
    # The dispatcher matches /proc/device-tree/model verbatim, so a typo never selects its board.
    git -C "${POCKNIX_ROOT}" grep -qF -- "model = \"${m}\";" -- "kernel/${soc}/dts" ||
      echo "models: '${m}' is the model of no dts under kernel/${soc}/dts"
    [ -n "${first}" ] || { first="${b}"; firstm="${m}"; }
    rows="${rows}${b}|${m}"$'\n'
  done < "${boards}/models"
  for m in $(printf '%s' "${rows}" | cut -d'|' -f2- | sort | uniq -d | tr ' ' '\001'); do
    echo "models: '${m//$'\001'/ }' is listed twice"
  done
  # The fallback board is the family's reference board: the first one its README bullet names.
  want="$(sed -nE "s/^\* \*\*${soc}\*\* \([^)]*\): ([^,;(]*[^,;( ]).*/\1/p" "${POCKNIX_ROOT}/devices/README.md")"
  [ "${firstm}" = "${want}" ] ||
    echo "models: first row (the fallback) is '${firstm}', devices/README.md names '${want}' first"

  for f in "${boards}"/*.conf; do
    n="${f##*/}"; b="${n%.conf}"
    [ "${n}" = family.conf ] && continue
    # Reachable = a models row, or sourced by another board (variants source their base).
    printf '%s' "${rows}" | grep -q "^${b}|" ||
      grep -qsE "^[[:space:]]*\. /usr/lib/pocknix/boards/${n//./\\.}([[:space:]]|\$)" \
        $(ls "${boards}"/*.conf | grep -v "/${n}\$") || echo "${n} is in no models row and sourced by no board"
    grep -qx "POCKNIX_DEVICE=${b}" "${f}" || echo "${n} must set POCKNIX_DEVICE=${b} itself"
    r="$(resolve_keys "${REQUIRED_KEYS}" "${t}/${n}")" || { echo "${n} fails to source"; continue; }
    m="${r%%|*}"; [ -z "${m}" ] || echo "${n} lacks ${m% }"
    [ "${r#*|}" = "${soc}" ] || echo "${n} says POCKNIX_SOC=${r#*|}"
  done

  # The rendered dispatcher: each row picks its board, anything else the first board flagged
  # unknown, and nothing reaches stdout (cores.sh sources it inside $(...)).
  if sh -n "${t}/device.conf" 2>/dev/null; then
    while IFS='|' read -r b m; do
      probe_model "${t}" "${m}" "${b}|"
    done < <(printf '%s' "${rows}")
    probe_model "${t}" "Some Unknown Board" "${first}|1"
    probe_model "${t}" "" "${first}|1"
  else
    echo "rendered device.conf is not POSIX sh"
  fi
  rm -rf "${t}"
}

# Prints one problem per line: meta PKGBUILD $1 must list (depends or optdepends) every
# $3/*/gpus package listing GPU_GEN $2 and none that omits it, so a meta carrying another
# generation's packages fails. Metas run nothing at top level, so sourcing reads the arrays exactly.
check_meta_gpus() {  # $1 = meta PKGBUILD, $2 = GPU_GEN, $3 = packages/gpu dir
  local deps g n
  deps=" $( (set +eu; . "$1" >/dev/null 2>&1; printf '%s ' "${depends[@]}" "${optdepends[@]%%:*}") ) "
  for g in "$3"/*/gpus; do
    [ -f "${g}" ] || continue
    n="${g%/gpus}"; n="${n##*/}"
    if grep -qw -- "$2" "${g}"; then
      case "${deps}" in *" ${n} "*) ;; *) echo "${1##*/devices/} lacks ${n} (its gpus lists $2)" ;; esac
    else
      case "${deps}" in *" ${n} "*) echo "${1##*/devices/} lists ${n}, whose gpus omits $2" ;; esac
    fi
  done
}

# A variable as kernel/<soc>/kernel.conf resolves it, in a clean environment like profile_get.
kernel_get() {  # $1 = SoC, $2 = variable name
  env -i bash -c '. "$1" && printf "%s" "${!2:-}"' sh "${POCKNIX_ROOT}/kernel/$1/kernel.conf" "$2"
}

# Prints one problem per line for a SoC family; nothing means it is fine.
check_family() {  # $1 = SoC
  local soc="$1" dev="${POCKNIX_ROOT}/devices/$1" bsp="${POCKNIX_ROOT}/devices/$1/packages/pocknix-bsp-$1"
  local f p grub ids sel b m pb pm ok gen meta rel
  for f in "devices/${soc}/profile.conf" "devices/${soc}/tuning.conf" "kernel/${soc}/kernel.conf"; do
    [ -f "${POCKNIX_ROOT}/${f}" ] || echo "missing ${f}"
  done
  # The shared kernel recipe takes its pkgrel from here; makepkg dies on a missing one.
  if [ -f "${POCKNIX_ROOT}/kernel/${soc}/kernel.conf" ]; then
    rel="$(kernel_get "${soc}" KERNEL_PKGREL)"
    case "${rel}" in
      ''|*[!0-9]*|0*) echo "kernel/${soc}/kernel.conf KERNEL_PKGREL='${rel}' is not a positive integer" ;;
    esac
  fi
  [ -f "${dev}/profile.conf" ] || return
  [ -f "${POCKNIX_ROOT}/kernel/${soc}/PATCHES.md" ] || echo "missing kernel/${soc}/PATCHES.md"
  for p in DEVICE_BSP_PKG DEVICE_META_PKG; do
    [ -f "${dev}/packages/$(profile_get "${dev}" "${p}")/PKGBUILD" ] || echo "${p} has no package under devices/${soc}/packages/"
  done
  check_boards "${soc}" "${bsp}/boards"
  gen="$(profile_get "${dev}" GPU_GEN)"
  meta="${dev}/packages/$(profile_get "${dev}" DEVICE_META_PKG)/PKGBUILD"
  case "${gen}" in
    a[0-9]xx) [ ! -f "${meta}" ] || check_meta_gpus "${meta}" "${gen}" "${POCKNIX_ROOT}/packages/gpu" ;;
    *) echo "profile GPU_GEN '${gen}' is not an Adreno generation (a6xx, a7xx, ...)" ;;
  esac
  # The build renders the cmdline from the profile; a committed copy would be a second source.
  [ ! -e "${bsp}/root/usr/lib/pocknix/kernel-cmdline" ] ||
    echo "BSP commits root/usr/lib/pocknix/kernel-cmdline, which the build renders from the profile"
  # Without it the on-device boot image rebuild skips silently, leaving the old kernel booting.
  [ "$(profile_get "${dev}" BOOTLOADER)" != qcom-abl ] || grep -q 'staged/kernel-cmdline' "${bsp}/PKGBUILD" ||
    echo "qcom-abl BSP PKGBUILD does not install staged/kernel-cmdline"
  [ -f "${bsp}/boards/models" ] || return 0
  # arm-efi picks the dtb before Linux runs, so GRUB needs a menuentry per board too.
  grub="${POCKNIX_ROOT}/packages/soc/pocknix-bootloader-${soc}/grub.cfg.in"
  if [ -f "${grub}" ]; then
    sed -n 's|^[[:space:]]*linux /KERNEL ||p' "${grub}" | grep -qvx '@KERNEL_CMDLINE@' &&
      echo "a grub.cfg.in menuentry spells out a cmdline instead of @KERNEL_CMDLINE@"
    ids="$(sed -nE "s/^menuentry .* --id '([^']+)'.*/\1/p" "${grub}" | sort -u | paste -sd ' ' -)"
    [ "${ids}" = "$(grep -vE '^[[:space:]]*(#|$)' "${bsp}/boards/models" | awk '{print $1}' | sort -u | paste -sd ' ' -)" ] ||
      echo "grub.cfg menuentry ids (${ids}) differ from the boards/models boards"
  fi
  # board-select maps the booted model back to a board; a panel variant (<board>-<x>,
  # "<model> <X>") rides its base board's arm.
  sel="${bsp}/root/usr/lib/pocknix/pocknix-${soc}-board-select"
  if [ -f "${sel}" ]; then
    local pairs
    pairs="$(sed -nE 's/^[[:space:]]*"([^"]+)"\)[[:space:]]+booted=([^ ;]+).*/\2|\1/p' "${sel}")"
    while IFS='|' read -r pb pm; do
      grep -qxE "${pb}[[:space:]]+${pm}" "${bsp}/boards/models" ||
        echo "board-select maps '${pm}' to ${pb}, boards/models does not"
    done <<< "${pairs}"
    while read -r b m; do
      case "${b}" in ''|'#'*) continue ;; esac
      ok=0
      while IFS='|' read -r pb pm; do
        { [ "${b}" = "${pb}" ] && [ "${m}" = "${pm}" ]; } && ok=1
        case "${b}|${m}" in "${pb}"-*"|${pm} "*) ok=1 ;; esac
      done <<< "${pairs}"
      [ "${ok}" = 1 ] || echo "board-select has no arm for '${m}' (${b})"
    done < "${bsp}/boards/models"
  fi
}

# Either half alone is a family: a profile without a kernel dir must fail, not go unchecked.
for _soc in $(cd "${POCKNIX_ROOT}" && ls -d kernel/*/kernel.conf devices/*/profile.conf 2>/dev/null |
              cut -d/ -f2 | sort -u); do
  _bad="$(check_family "${_soc}" | paste -sd ';' -)"
  if [ -z "${_bad}" ]; then note "family: ${_soc}" "ok"; else note "family: ${_soc}" "${_bad}"; fail=1; fi
done

# A board nothing selects never loads, so check_boards must flag one: a copy of a family's
# boards/ plus a stray board has to fail.
_t="$(mktemp -d)"
_bsp="${POCKNIX_ROOT}/devices/${SOC}/packages/pocknix-bsp-${SOC}"
cp -R "${_bsp}/boards" "${_t}/"
printf '. /usr/lib/pocknix/boards/family.conf\nPOCKNIX_DEVICE=stray\n' > "${_t}/boards/stray.conf"
_out="$(check_boards "${SOC}" "${_t}/boards")"
if printf '%s\n' "${_out}" | grep -q '^stray.conf is in no models row'; then
  note "board check self-test" "ok"
else note "board check self-test" "a board in no models row went unflagged"; fail=1; fi
rm -rf "${_t}"

# The meta rule must catch a missing gpus package: a meta listing all of one generation's
# gpus packages but the first has to be flagged for exactly that one.
_t="$(mktemp -d)"; _gen=""; _n=""; _deps=""
for _g in "${POCKNIX_ROOT}"/packages/gpu/*/gpus; do
  [ -f "${_g}" ] || continue
  [ -n "${_gen}" ] || read -r _gen _ < "${_g}" || true
  grep -qw -- "${_gen}" "${_g}" || continue
  _p="${_g%/gpus}"; _p="${_p##*/}"
  if [ -z "${_n}" ]; then _n="${_p}"; else _deps="${_deps} '${_p}'"; fi
done
if [ -z "${_n}" ]; then note "device meta GPU rule self-test" "skipped (no gpus packages)"
else
  printf 'depends=(%s)\n' "${_deps}" > "${_t}/PKGBUILD"
  if [ "$(check_meta_gpus "${_t}/PKGBUILD" "${_gen}" "${POCKNIX_ROOT}/packages/gpu")" = \
       "${_t}/PKGBUILD lacks ${_n} (its gpus lists ${_gen})" ]; then
    note "device meta GPU rule self-test" "ok"
  else note "device meta GPU rule self-test" "a ${_gen} meta without ${_n} went unflagged (or flagged more)"; fail=1; fi
fi
rm -rf "${_t}"

# A device package's root/ is copied as is, so the git mode is the installed mode: a script
# committed 644 installs 644 and never runs.
_mode=""
while read -r _m _ _ _f; do
  [ "$(head -c2 "${POCKNIX_ROOT}/${_f}" 2>/dev/null)" = '#!' ] && _want=100755 || _want=100644
  [ "${_m}" = "${_want}" ] || _mode="${_mode} ${_f}"
done < <(git -C "${POCKNIX_ROOT}" ls-files -s -- 'devices/*/packages/*/root/*' | grep -v '^120000 ')
if [ -z "${_mode}" ]; then note "device root/ modes" "ok"
else note "device root/ modes" "shebang and exec bit disagree:${_mode}"; fail=1; fi

# A common-skip line that names no kernel/common patch (after a rename) would silently
# let that patch apply again.
_stale=""
for _s in "${POCKNIX_ROOT}"/kernel/*/common-skip; do
  [ -f "${_s}" ] || continue
  while IFS= read -r _p; do
    [ -f "${POCKNIX_ROOT}/kernel/common/patches/${_p}" ] || _stale="${_stale} ${_s#"${POCKNIX_ROOT}"/}:${_p}"
  done < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "${_s}")
done
if [ -z "${_stale}" ]; then note "kernel common-skip" "ok"; else note "kernel common-skip" "not in kernel/common/patches:${_stale}"; fail=1; fi

SOC_ID_RE='(^|[^a-z0-9])sm[0-9]{4}([^0-9]|$)'
# Prints one problem per line for "<path>:<line>:<text>" hits on stdin: a chip id in a code line
# (comments stripped) that no row of allow file $1 covers, or a row that matches nothing.
check_soc_ids() {  # $1 = allow file
  local r h p n t i used=" "
  local -a globs=() res=()
  while IFS= read -r r; do
    case "${r}" in ''|'#'*) continue ;; *' :: '*' :: '?*) ;; *) echo "${1##*/}: malformed row '${r}'"; continue ;; esac
    globs+=("${r%% :: *}"); r="${r#* :: }"; res+=("${r%% :: *}")
  done < "$1"
  while IFS= read -r h; do
    p="${h%%:*}"; t="${h#*:}"; n="${t%%:*}"; t="${t#*:}"
    t="$(sed -E 's/^[[:space:]]*#.*//; s/[[:space:]]#.*//' <<< "${t}")"
    grep -qiE "${SOC_ID_RE}" <<< "${t}" || continue
    for i in "${!globs[@]}"; do
      # shellcheck disable=SC2053  # the row's glob is meant to glob
      [[ "${p}" == ${globs[i]} ]] && grep -qiE -- "${res[i]}" <<< "${t}" && { used="${used}${i} "; continue 2; }
    done
    echo "${p}:${n} names a chip"
  done
  for i in "${!globs[@]}"; do
    case "${used}" in *" ${i} "*) ;; *) echo "${1##*/}: '${globs[i]} :: ${res[i]}' matches nothing" ;; esac
  done
}

# Shared code that names today's chips mishandles the next one; the chip trees, the family
# docs and packages/soc/<name>-<soc>/ are where chip names belong.
_allow="${POCKNIX_ROOT}/scripts/soc-ids.allow"
_bad="$(git -C "${POCKNIX_ROOT}" grep -n -I -i -E "${SOC_ID_RE}" -- . ':!devices/' ':!kernel/' \
          ':(exclude,glob)**/PATCHES.md' ':!CONTRIBUTING.md' ':!README.md' ':!docs/' ':(exclude,glob)**/*.allow' \
          ':(exclude,glob)packages/soc/*-sm[0-9][0-9][0-9][0-9]/**' | check_soc_ids "${_allow}" | paste -sd ';' -)"
if [ -z "${_bad}" ]; then note "chip ids outside chip trees" "ok"
else note "chip ids outside chip trees" "${_bad}"; fail=1; fi
_id="sm""8750"   # split so this line is no hit itself
_out="$(printf '%s\n' "packages/shared/pocknix-steam/pocknix-steam:1:  [ \"\${s}\" = ${_id} ]" \
          "packages/shared/pocknix-steam/pocknix-steam:2:  # ${_id} probes late" | check_soc_ids "${_allow}")"
if grep -q '^packages/shared/pocknix-steam/pocknix-steam:1 names a chip' <<< "${_out}" && ! grep -q 'steam:2' <<< "${_out}"; then
  note "chip ids self-test" "ok"
else note "chip ids self-test" "a stray chip id in shared code went unflagged (or a comment was flagged)"; fail=1; fi

# Docs name only what the tree has; structural READMEs follow their dirs and keep no versions.
if "${POCKNIX_ROOT}/scripts/check-docs.sh"; then note "docs match the tree" "ok"
else note "docs match the tree" "see the lines above"; fail=1; fi

# Each patch dir's PATCHES.md names exactly its patches; the self-test plants each kind of drift.
if out="$(python3 "${POCKNIX_ROOT}/scripts/check-patches.py" 2>&1)"; then note "patch ledgers" "ok"
else note "patch ledgers" "DRIFT"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi
if python3 "${POCKNIX_ROOT}/scripts/check-patches.py" --selftest >/dev/null 2>&1; then note "patch ledgers self-test" "ok"
else note "patch ledgers self-test" "a planted drift went unflagged (or a clean ledger was flagged)"; fail=1; fi

# --- kernel enablement present? (committed; refreshable via sync) -----------
_npatch=$(find "${KERNEL_DIR}/patches" "${POCKNIX_ROOT}/kernel/common/patches" -name '*.patch' 2>/dev/null | wc -l | tr -d ' ')
if [ "${_npatch:-0}" -gt 0 ]; then
  note "kernel: enablement (kernel/${SOC}/ + common/)" "${_npatch} patches"
else
  note "kernel: enablement (kernel/${SOC}/ + common/)" "run 'make sync'"
fi
# vendor/ is sync reference only (gitignored); no build reads it
if [ -d "${VENDOR_DIR}/rocknix-${SOC}/reference" ]; then
  note "vendor: reference" "synced"
else
  note "vendor: reference" "run 'make sync' (build host)"
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
