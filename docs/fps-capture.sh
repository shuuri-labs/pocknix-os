#!/bin/sh
# fps-capture.sh — matched gamescope/FEX profiling capture for the pocknix fps-gap investigation.
#
# Run the SAME script, on the SAME in-game scene, on BOTH pocknix and ROCKNIX, so the two captures
# are methodology-identical and can be diffed. Everything the prior investigation got wrong came from
# comparing un-matched measurements (ps snapshots vs a system-wide `perf -a`, different scenes,
# root-vs-deck process sets). This script removes that variable: same tool, same flags, same outputs.
#
# WHY each capture (see docs/gamescope-fps-investigation.md):
#   - The doc's "architectural/irreducible" verdict is contradicted by its own numbers:
#     ROCKNIX-gamescope (~219% CPU) sits at kwin/Plasma efficiency (~216%), NOT at pocknix-gamescope's
#     ~282%. Same compositor, so the gap is a pocknix-vs-ROCKNIX *session/config* delta, not gamescope.
#   - pocknix was NEVER profiled. This takes the missing profile, identically on both sides.
#
# USAGE:
#   1. Boot the OS, launch Steam game mode, get the game into a STEADY repeatable scene (e.g. ASBR
#      character-select or a fixed training-mode camera) and leave it running.
#   2. SSH in as root (ROCKNIX) or root/deck (pocknix) and run:  sh fps-capture.sh
#      Optional: pass the game PID explicitly if auto-detect picks the wrong one: sh fps-capture.sh 1234
#   3. Re-run on the OTHER OS on the SAME scene.
#   4. Copy both output dirs to your Mac and diff (see "DIFFING" at the bottom of this file).
#
# pocknix prereq:  pacman -S --needed perf   (ROCKNIX ships perf already)
# Output goes to a writable dir picked automatically (ROCKNIX: /storage; pocknix: $HOME).

set -u

# ---------------------------------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------------------------------
HOST="$(cat /proc/sys/kernel/hostname 2>/dev/null || hostname 2>/dev/null || echo unknown)"
case "$HOST" in
  SM8550*) OS=rocknix ;;
  pocknix*) OS=pocknix ;;
  *)        OS="$HOST" ;;
esac

# Pick a writable output dir.
if [ -w /storage ] 2>/dev/null; then OUTBASE=/storage
elif [ -n "${HOME:-}" ] && [ -w "$HOME" ]; then OUTBASE="$HOME"
else OUTBASE=/tmp; fi
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$OUTBASE/fps-capture-$OS-$TS"
mkdir -p "$OUT" || { echo "cannot create $OUT" >&2; exit 1; }

log() { echo "[$*]"; }
cap() { _f="$1"; shift; echo "\$ $*" > "$OUT/$_f"; "$@" >> "$OUT/$_f" 2>&1; }

echo "==> OS=$OS  host=$HOST  out=$OUT"

# ---------------------------------------------------------------------------------------------------
# Locate the game process (the x86 .exe under FEX). Override with $1 if needed.
# ---------------------------------------------------------------------------------------------------
GAME_PID="${1:-}"
if [ -z "$GAME_PID" ]; then
  # Prefer a *.exe with the highest CPU that is NOT a Steam/helper exe. Fall back to any *.exe.
  GAME_PID="$(ps -eo pid,comm 2>/dev/null \
    | awk '/\.exe$/ && $2 !~ /steam|web|crash|service|reaper/ {print $1}' \
    | while read -r p; do
        c="$(awk '{print $14+$15}' /proc/$p/stat 2>/dev/null)"; echo "$c $p";
      done | sort -rn | head -1 | awk '{print $2}')"
fi
if [ -z "$GAME_PID" ] || [ ! -d "/proc/$GAME_PID" ]; then
  echo "!! could not auto-detect the game PID. Re-run as: sh $0 <pid>" >&2
  echo "   candidates:" >&2; ps -eo pid,comm 2>/dev/null | grep -i '\.exe' >&2
  exit 1
fi
GAME_COMM="$(cat /proc/$GAME_PID/comm 2>/dev/null)"
echo "==> game PID=$GAME_PID ($GAME_COMM)"
echo "$GAME_PID $GAME_COMM" > "$OUT/game-pid.txt"

# ---------------------------------------------------------------------------------------------------
# (A) THE PROFILE — identical flags both sides. task-clock -p <pid> excludes idle (the prior ROCKNIX
#     profile used -a system-wide, so 69% showed as idle and the breakdown had to be hand-rescaled).
# ---------------------------------------------------------------------------------------------------
if command -v perf >/dev/null 2>&1; then
  log "perf record (20s, task-clock, game PID $GAME_PID) — hold the scene STEADY now"
  ( cd "$OUT" && perf record -g --call-graph fp -F 999 -e task-clock -p "$GAME_PID" -- sleep 20 ) \
    > "$OUT/perf-record.log" 2>&1
  log "perf report (per-DSO Self%) — THIS is the money table to diff"
  ( cd "$OUT" && perf report --stdio --sort=dso --no-inline -g none ) > "$OUT/perf-by-dso.txt" 2>/dev/null
  log "perf report (per-symbol, call-graph) — for drilling into the hot DSO"
  ( cd "$OUT" && perf report --stdio -g graph,0.5,caller ) > "$OUT/perf-by-symbol.txt" 2>/dev/null
else
  echo "!! perf not found. pocknix: pacman -S --needed perf, then re-run. ROCKNIX should ship it." \
    | tee "$OUT/perf-MISSING.txt"
fi

# ---------------------------------------------------------------------------------------------------
# (B) PER-THREAD CPU snapshot — re-establish the 282-vs-219 number with IDENTICAL methodology.
#     Take it WHILE the scene is steady. Try procps ps, fall back to top -H.
# ---------------------------------------------------------------------------------------------------
if ps -eLo psr,pcpu,tid,comm >/dev/null 2>&1; then
  cap per-thread-cpu.txt sh -c 'ps -eLo psr,pcpu,tid,comm --sort=-pcpu 2>/dev/null | head -25'
else
  cap per-thread-cpu.txt sh -c 'top -H -b -n1 2>/dev/null | head -30'
fi
# Game-only thread view + total — directly comparable CPU/frame numerator.
cap game-threads.txt sh -c "ps -L -o psr,pcpu,tid,comm -p $GAME_PID 2>/dev/null || top -H -b -n1 -p $GAME_PID 2>/dev/null"

# ---------------------------------------------------------------------------------------------------
# (C) ARM64EC rule-out — is the GAME on the same emulation path on both OSes?
#     ROCKNIX's profile showed libarm64ecfex.dll. If pocknix's game is NOT on arm64ec, that alone is
#     the gap. Expectation: both show it (Proton bundles its own arm64ec FEX) -> red herring, move on.
# ---------------------------------------------------------------------------------------------------
{
  echo "=== arm64ec / wow64 dlls mapped into the game ==="
  grep -iE 'arm64ec|wow64|fex' /proc/$GAME_PID/maps 2>/dev/null | awk '{print $NF}' | sort -u
  echo "=== FEXInterpreter vs Proton-bundled FEX (which binary is emulating) ==="
  ls -l /proc/$GAME_PID/exe 2>/dev/null
  tr '\0' '\n' < /proc/$GAME_PID/cmdline 2>/dev/null
} > "$OUT/arm64ec-check.txt" 2>&1

# ---------------------------------------------------------------------------------------------------
# (D) PRESENT / REFRESH — verify both sessions actually pace at the same effective rate.
#     If pocknix lacks a real 60Hz mode (the EDID issue) it may vblank against a different rate than
#     ROCKNIX, which would inflate per-frame cost independently of any emulation cost.
# ---------------------------------------------------------------------------------------------------
GS_PID="$(pidof gamescope 2>/dev/null | awk '{print $1}')"
{
  echo "=== gamescope cmdline ==="
  [ -n "$GS_PID" ] && tr '\0' ' ' < /proc/$GS_PID/cmdline; echo
  echo "=== gamescope present/refresh-relevant environ ==="
  [ -n "$GS_PID" ] && tr '\0' '\n' < /proc/$GS_PID/environ \
    | grep -iE 'MESA|TU_|DXVK|PROTON|GAMESCOPE|FEX|vblank|WSI|glthread'
  echo "=== DRM connector current modes ==="
  for m in /sys/class/drm/*/modes; do [ -r "$m" ] && { echo "-- $m"; cat "$m"; }; done
  echo "=== gamescope thread affinity (is it pinned?) ==="
  [ -n "$GS_PID" ] && grep Cpus_allowed_list /proc/$GS_PID/status
} > "$OUT/present-path.txt" 2>&1

# ---------------------------------------------------------------------------------------------------
# (E) CONFIG SNAPSHOT — re-verify the assumptions the doc keeps getting wrong (governor, scheduler,
#     capacities, GPU clock, PSI). Cheap; pins down any drift between the two OSes at capture time.
# ---------------------------------------------------------------------------------------------------
{
  echo "=== cpufreq governor (per policy) ==="
  for g in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do echo "$g: $(cat $g 2>/dev/null)"; done
  echo "=== current cpu freqs ==="
  for f in /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq; do echo "$f: $(cat $f 2>/dev/null)"; done
  echo "=== scheduler (scx active?) ==="
  cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "EEVDF (no scx)"
  echo "=== cpu capacities (expect 326 / 693 / 1024) ==="
  for c in 0 3 7; do echo "cpu$c: $(cat /sys/devices/system/cpu/cpu$c/cpu_capacity 2>/dev/null)"; done
  echo "=== GPU devfreq ==="
  for d in /sys/class/devfreq/*.gpu; do
    [ -d "$d" ] && echo "$d gov=$(cat $d/governor 2>/dev/null) cur=$(cat $d/cur_freq 2>/dev/null) max=$(cat $d/max_freq 2>/dev/null)"
  done
  echo "=== PSI ==="
  [ -r /proc/pressure/cpu ] && { echo "PSI on"; cat /proc/pressure/cpu; } || echo "PSI off"
  echo "=== GPU utilisation (is it GPU-bound? expect NO, ~60%) ==="
  cat /sys/class/drm/*/device/gpu_busy_percent 2>/dev/null || echo "(no gpu_busy_percent)"
  echo "=== Turnip / driver ==="
  command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary 2>/dev/null | grep -iE 'driverName|driverInfo'
} > "$OUT/config-snapshot.txt" 2>&1

# ---------------------------------------------------------------------------------------------------
# (F) FEX config actually in effect for the game (not just the on-disk default).
# ---------------------------------------------------------------------------------------------------
{
  echo "=== FEX env on the game ==="
  tr '\0' '\n' < /proc/$GAME_PID/environ 2>/dev/null | grep -iE 'FEX|TUNE_CPU|RootFS|Thunk'
  echo "=== FEX config files present ==="
  for f in /etc/fex-emu/Config.json ~/.fex-emu/Config.json /usr/share/fex-emu/Config.json; do
    [ -r "$f" ] && { echo "-- $f"; cat "$f"; }
  done
} > "$OUT/fex-config.txt" 2>&1

echo
echo "==> DONE. Output in: $OUT"
echo "    Copy it off the device, e.g.:  scp -r root@<ip>:$OUT ."
ls -la "$OUT"

# ---------------------------------------------------------------------------------------------------
# DIFFING (on your Mac, after copying both fps-capture-pocknix-* and fps-capture-rocknix-* dirs):
#
#   # The money diff — where does pocknix spend MORE CPU per active cycle?
#   diff -y fps-capture-rocknix-*/perf-by-dso.txt fps-capture-pocknix-*/perf-by-dso.txt
#
# READ IT LIKE THIS (config levers, NOT rebuilds):
#   pocknix higher in [kernel.kallsyms]  -> futex/syscall/scheduling = SESSION overhead
#                                           (deck cgroup/bwrap, mesa_glthread's extra thread, glthread
#                                            on the CEF UI) -> session/launch config.   <-- my prediction
#   pocknix higher in [JIT]              -> FEX translation/arm64ec path -> FEX Config.json / arm64ec.
#   pocknix higher in d3d11.dll/DXVK     -> FEX's translation of DXVK -> FEX config.
#   pocknix higher in gamescope/Xwayland -> present path = genuinely structural (then the doc is right).
#
#   If per-thread-cpu/CPU-per-frame is EQUAL once matched, the 282-vs-219 was a measurement artifact
#   (different scene / fps cap / process set) and the "gap" is smaller than believed.
# ---------------------------------------------------------------------------------------------------
