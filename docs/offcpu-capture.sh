#!/bin/sh
# offcpu-capture.sh — off-CPU (blocking/wait) profiler for the gamescope fps-gap investigation.
#
# WHY THIS EXISTS (see docs/gamescope-fps-investigation.md):
#   The gap is firmly localized to pocknix's gamescope session (~10ms/frame), but every ON-CPU
#   measurement is IDENTICAL to ROCKNIX/kwin — because the cost is the game's render/present thread
#   BLOCKING (off-CPU, waiting), which on-CPU profiling (fps-capture.sh / perf task-clock) literally
#   cannot see. This captures off-CPU time WITH STACKS, so we can see *what* the thread waits on
#   (futex / poll on the compositor socket / DRM ioctl / the Vulkan present-wait) and for how long.
#
# THE KILLER COMPARISON: run this on the SAME pocknix install in BOTH sessions on the SAME scene:
#   1. gamescope (Steam game mode)  — the SLOW case
#   2. Plasma/kwin desktop          — the FAST case (launch the same game on the desktop)
# Same OS/FEX/Turnip in both, so whatever off-CPU wait is BIGGER under gamescope is the gap.
# Also run on ROCKNIX-gamescope (the other fast case) if available, for a third point.
#
# USAGE:
#   1. Get the game into the steady, repeatable scene; leave it running.
#   2. ssh in as root and run:  sh offcpu-capture.sh   (optional: sh offcpu-capture.sh <game-pid>)
#   3. Re-run in the OTHER session on the SAME scene.
#   4. Copy the output dirs off and diff offcpu-by-symbol.txt (see DIFFING at the bottom).
#
# prereqs / platform: needs EITHER a perf built with BUILD_BPF_SKEL=1 (for --off-cpu) OR a kernel
# with CONFIG_FTRACE + sched tracepoints (for the sched:sched_switch fallback).
#   - pocknix: kernel has FTRACE on (enabled for scx_lavd) -> the fallback works; run it here.
#   - ROCKNIX: its perf lacks the BPF skel AND its kernel ships FTRACE off -> off-CPU profiling is
#     IMPOSSIBLE there (the script detects this and writes CANNOT-OFFCPU.txt). Don't bother on ROCKNIX.
# pocknix: pacman -S --needed perf   (already installed if you ran fps-capture.sh)

set -u

# --------------------------------------------------------------------------------------------------
# Environment + session detection (so gamescope vs kwin captures are labelled and never confused)
# --------------------------------------------------------------------------------------------------
HOST="$(cat /proc/sys/kernel/hostname 2>/dev/null || hostname 2>/dev/null || echo unknown)"
case "$HOST" in SM8550*) OS=rocknix ;; pocknix*) OS=pocknix ;; *) OS="$HOST" ;; esac

if pidof gamescope >/dev/null 2>&1; then SESSION=gamescope
elif pgrep -x kwin_wayland >/dev/null 2>&1; then SESSION=kwin
elif pgrep -x plasmashell >/dev/null 2>&1; then SESSION=plasma
else SESSION=unknown; fi

if   [ -w /storage ] 2>/dev/null; then OUTBASE=/storage
elif [ -n "${HOME:-}" ] && [ -w "$HOME" ]; then OUTBASE="$HOME"
else OUTBASE=/tmp; fi
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$OUTBASE/offcpu-$OS-$SESSION-$TS"
mkdir -p "$OUT" || { echo "cannot create $OUT" >&2; exit 1; }
log() { echo "[$*]"; }
echo "==> OS=$OS  SESSION=$SESSION  out=$OUT"

# --------------------------------------------------------------------------------------------------
# Locate the game process (the x86 .exe under FEX). Override with $1.
# --------------------------------------------------------------------------------------------------
GAME_PID="${1:-}"
if [ -z "$GAME_PID" ]; then
  GAME_PID="$(ps -eo pid,comm 2>/dev/null \
    | awk '/\.exe$/ && $2 !~ /steam|web|crash|service|reaper|winedev|plugplay|svchost|explorer|rpcss|tabtip/{print $1}' \
    | while read -r p; do c="$(awk '{print $14+$15}' /proc/$p/stat 2>/dev/null)"; echo "$c $p"; done \
    | sort -rn | head -1 | awk '{print $2}')"
fi
[ -n "$GAME_PID" ] && [ -d "/proc/$GAME_PID" ] || { echo "!! no game pid; pass it: sh $0 <pid>" >&2; ps -eo pid,comm|grep -i '\.exe' >&2; exit 1; }
echo "$GAME_PID $(cat /proc/$GAME_PID/comm 2>/dev/null)" | tee "$OUT/game-pid.txt"

# Record the hot threads' tids/names up front (RenderThread etc.) — we focus the off-CPU report on them.
ps -L -o tid,pcpu,comm -p "$GAME_PID" 2>/dev/null | sort -k2 -rn | head -15 > "$OUT/hot-threads.txt"
RENDER_TID="$(awk 'tolower($3) ~ /render/ {print $1; exit}' "$OUT/hot-threads.txt")"
echo "hot threads (off-CPU report focuses on RenderThread tid=${RENDER_TID:-?}):"; cat "$OUT/hot-threads.txt"

# --------------------------------------------------------------------------------------------------
# Does perf support --off-cpu? (it needs a BPF-enabled perf build)
# --------------------------------------------------------------------------------------------------
HAVE_OFFCPU=no
command -v perf >/dev/null 2>&1 || { echo "!! perf not found. pocknix: pacman -S --needed perf" | tee "$OUT/perf-MISSING.txt"; exit 1; }
# `perf record --off-cpu` SILENTLY IGNORES the flag (exit 0 + a warning) when perf was built without
# BUILD_BPF_SKEL=1 — which is the case on ROCKNIX's perf 7.0.11. So checking the exit code is useless;
# check the build option, and also that it doesn't emit the "being ignored" warning.
if perf version --build-options 2>/dev/null | grep -qiE "bpf_skel:[[:space:]]*\[[[:space:]]*on"; then
  if ! perf record --off-cpu -e task-clock -o /dev/null -- true 2>&1 | grep -qi "being ignored\|BUILD_BPF_SKEL\|not supported"; then
    HAVE_OFFCPU=yes
  fi
fi
HAVE_PERF_SCHED=no
perf sched --help >/dev/null 2>&1 && HAVE_PERF_SCHED=yes
echo "perf --off-cpu supported: $HAVE_OFFCPU   perf sched supported: $HAVE_PERF_SCHED"

ESF="$OUT/.emptysymfs"; mkdir -p "$ESF"   # addr2line workaround (perf crashes on Proton .debug paths)
RPT="perf report -i $OUT/perf.data --stdio --no-inline --symfs=$ESF"

# --------------------------------------------------------------------------------------------------
# (A) THE CAPTURE — 20s, on-CPU (task-clock) + off-CPU (block/wait) with call graphs, game PID only.
# --------------------------------------------------------------------------------------------------
if [ "$HAVE_OFFCPU" = yes ]; then
  log "perf record --off-cpu (20s, on+off CPU, game PID $GAME_PID) — HOLD THE SCENE STEADY"
  ( cd "$OUT" && perf record -g --call-graph fp -F 999 -e task-clock --off-cpu -p "$GAME_PID" -- sleep 20 ) \
    > "$OUT/perf-record.log" 2>&1
  # off-CPU time by symbol — THE money table (what the threads block in, by wall-time waited)
  log "report: off-CPU time by symbol (the blocking leaf)"
  $RPT -g none --sort=symbol 2>/dev/null > "$OUT/offcpu-and-oncpu-by-symbol.txt"
  # off-CPU with call graphs — the PATH to the block (so we see vk present-wait vs futex vs poll)
  log "report: off-CPU call graphs (path to the wait)"
  $RPT -g graph,0.5,caller 2>/dev/null > "$OUT/offcpu-callgraph.txt"
  # by DSO too (host lib the wait lives in: gamescope WSI / libvulkan / libc / [kernel])
  $RPT -g none --sort=dso 2>/dev/null > "$OUT/by-dso.txt"
  # focus: just the RenderThread's off-CPU stacks, if we found it
  if [ -n "${RENDER_TID:-}" ]; then
    $RPT -g graph,0.5,caller --tid "$RENDER_TID" 2>/dev/null > "$OUT/offcpu-RENDERTHREAD.txt"
  fi
elif [ -e /sys/kernel/tracing/events/sched/sched_switch ] || [ -e /sys/kernel/debug/tracing/events/sched/sched_switch ]; then
  # Fallback: record sched_switch with stacks → stack captured at each block (needs CONFIG_FTRACE +
  # tracepoints). Works on pocknix (FTRACE on for scx_lavd). NOT on ROCKNIX (FTRACE off).
  log "perf --off-cpu unavailable; FALLBACK: sched:sched_switch with stacks (20s)"
  ( cd "$OUT" && perf record -e sched:sched_switch -g --call-graph fp -p "$GAME_PID" -- sleep 20 ) \
    > "$OUT/perf-record.log" 2>&1
  $RPT -g graph,0.5,caller 2>/dev/null > "$OUT/sched-switch-callgraph.txt"
  $RPT -g none --sort=comm,symbol 2>/dev/null > "$OUT/sched-switch-by-symbol.txt"
else
  cat > "$OUT/CANNOT-OFFCPU.txt" <<MSG
This kernel+perf cannot do off-CPU profiling:
  - perf has no BPF skeleton (--off-cpu is silently ignored: needs perf built with BUILD_BPF_SKEL=1), AND
  - the kernel has no sched_switch tracepoint (needs CONFIG_FTRACE / tracefs).
This is the case on ROCKNIX (FTRACE is off — same reason it can't run scx_lavd). Run this on pocknix
instead: its kernel has FTRACE on, so the sched:sched_switch fallback works even without a BPF-skel perf.
MSG
  echo "!! cannot off-CPU profile here (no BPF-skel perf AND no sched tracepoint). See CANNOT-OFFCPU.txt"
  echo "   The real comparison is pocknix-gamescope vs pocknix-kwin anyway — run it there."
fi

# --------------------------------------------------------------------------------------------------
# (B) perf sched summary — per-thread total off-CPU time + max wait latency (very interpretable).
#     Independent of --off-cpu; works on both perf versions. Records system-wide sched for 10s.
# --------------------------------------------------------------------------------------------------
if [ "$HAVE_PERF_SCHED" = yes ]; then
  log "perf sched record (10s) for per-thread off-CPU/latency summary"
  ( cd "$OUT" && perf sched record -o sched.data -- sleep 10 ) > "$OUT/sched-record.log" 2>&1
  log "perf sched timehist summary (look for the game's RenderThread: high 'wait time' = blocking)"
  perf sched -i "$OUT/sched.data" timehist -s 2>/dev/null > "$OUT/sched-summary.txt"
  perf sched -i "$OUT/sched.data" latency 2>/dev/null > "$OUT/sched-latency-all.txt"
  grep -iE "Task|ASBR|Render|dxvk|Skin|gamescope|Xwayland|----" "$OUT/sched-latency-all.txt" 2>/dev/null \
    | head -40 > "$OUT/sched-latency-game.txt"
else
  echo "perf sched not built into this perf — skipped (the sched:sched_switch record above has the blocking stacks)." \
    > "$OUT/sched-summary.txt"
fi

rmdir "$ESF" 2>/dev/null
echo
echo "==> DONE. Output in: $OUT"
echo "    Copy off:  scp -r root@<ip>:$OUT ."
ls -la "$OUT"

# --------------------------------------------------------------------------------------------------
# DIFFING (on your Mac, after capturing gamescope AND kwin on the same scene):
#
#   # Where does the render/present thread WAIT more under gamescope than kwin?
#   diff -y offcpu-*-kwin-*/offcpu-and-oncpu-by-symbol.txt offcpu-*-gamescope-*/offcpu-and-oncpu-by-symbol.txt
#   # And the path to that wait:
#   less offcpu-*-gamescope-*/offcpu-RENDERTHREAD.txt
#
# READING IT — the 'offcpu-time' event rows are wall-time the thread spent BLOCKED. Compare the
# render/present thread's top off-CPU stacks gamescope-vs-kwin. The leaf names the cause:
#   - blocked in vkAcquireNextImageKHR / gamescope WSI present-wait / vk_khr_present_wait
#       -> the compositor isn't releasing buffers fast enough = the present-path stall we predicted.
#   - blocked in poll/ppoll/recvmsg on the wayland/gamescope socket
#       -> waiting on the compositor's reply each frame (round-trip cost).
#   - blocked in a futex (and the waker is a FEX/wineserver thread)
#       -> intra-game lock convoy, not the compositor (would point back at FEX, not gamescope).
#   - blocked in a DRM ioctl / dma_fence wait
#       -> waiting on the GPU/vblank (but GPU is ~50%, so this should be SMALL).
# Whichever off-CPU bucket is LARGE under gamescope and SMALL under kwin is, at last, the named cause.
# sched-summary.txt / sched-latency-game.txt give the same story as per-thread totals if the
# call-graph stacks are too shallow (FEX/stripped libs) to read.
# --------------------------------------------------------------------------------------------------
