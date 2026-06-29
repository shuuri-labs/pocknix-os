# Gamescope FPS-gap investigation

## TL;DR

pocknix's **game-mode (gamescope) session runs x86/FEX games ~15-20% slower** than the *same*
game on (a) pocknix's own **Plasma** desktop, (b) **ROCKNIX**, and (c) **armada** — all on the same
RP6. After an extensive on-device A/B campaign we **could not close the average-fps gap with any
config or driver lever**. The conclusion is that it is **architectural**: gamescope's
nested-XWayland present path makes the FEX-translated game spend materially more CPU *per frame*
than kwin's path, and the workload is CPU/FEX-bound (GPU ~60%), so that cost lands on the limiter.
It only affects **x86/FEX titles under gamescope** — native-ARM games and the Plasma session do
not pay it.

The campaign still produced real wins (RT-throttle fix for download/load choppiness, scx_lavd
pacing, a gaming sysctl, ROCKNIX's FEX JIT config) — see **[Kept](#kept-real-wins)**.

---

## The setup

- **Device:** Retroid Pocket 6 — Snapdragon 8 Gen 2 (**SM8550**), Adreno 740, kernel 7.0.11.
- **CPU topology:** `cpu0-2` = Cortex-A510 (little), `cpu3-6` = A710/A715 (mid), `cpu7` = Cortex-X3
  (prime). cpufreq policies `policy0` / `policy3` / `policy7`.
- **capacity-dmips-mhz:** `326 / 693 / 1024` — **correct** (set by kernel patch `0102`); the
  scheduler *can* tell the cores apart, so mis-capacity (the "AYN SM8550 perf doc" headline) is
  **not** our problem.
- **Game under test:** JoJo's Bizarre Adventure ASBR (x86 Windows, DX11 → DXVK → Vulkan/Turnip,
  via Proton 11 ARM64 + FEX-Emu).
- **Three reference stacks:**
  - **pocknix** — Arch Linux ARM, full distro, non-root `deck` session.
  - **ROCKNIX** — LibreELEC appliance, **root** session.
  - **armada** — Fedora bootc, full distro (the closest comparable; `shuuri-labs/armada`).

## Measured baseline

| Configuration | fps (same scene) |
|---|---|
| Plasma / ROCKNIX / armada | ~50-60 |
| **pocknix gamescope** | **~40-48** |

Key measurement: under gamescope the game ran at **~282% CPU for ~45 fps**; under Plasma at
**~216% CPU for ~60 fps** → **~70% more CPU per frame under gamescope.** It is *not* getting *less*
CPU (a placement/contention problem) — it is *burning more per frame* (present-path overhead). GPU
sat at ~60% throughout, i.e. **CPU/FEX-bound, not GPU-bound.**

---

## Ruled out (on-device A/B, no average-fps effect)

| Lever | Hypothesis | Result |
|---|---|---|
| CPU governor (performance vs schedutil) | clocks held low | no effect |
| Scheduler (EEVDF vs scx_lavd) | placement / latency | no avg-fps difference |
| CPU placement (force game to X3 prime, cores 5-7 exclusive) | game stranded on a mid core | **no change — placement ruled out** |
| CPU contention (game given 3 exclusive big cores) | compositor steals its cores | no change |
| 3-7 affinity pin | keep threads off the littles | helps vs *unpinned* (avoids A510s), but prime-vs-mid is irrelevant to avg fps |
| RT priority (gamescope SCHED_RR) | compositor starved | no avg-fps effect (it's a pacing thing) |
| GPU clock / devfreq governor | clock dipping mid-frame | already at max, GPU ~60% → not GPU-bound |
| mesa env vars | mesa misconfig | matches the (fast) kwin path |
| FEX env vars / `TUNE_CPU` a78→x3 | translation tuning | negligible |
| FEX TSO opts (Vector/MemcpySet/HalfBarrier) | barrier cost | no difference |
| Present mode (`MESA_VK_WSI_PRESENT_MODE=mailbox`) | present blocking | no difference |
| Rotation pass (composite #2228 vs rotation-shader) | rotation cost | lowered GPU load, no avg-fps change |
| Kernel config | config delta vs ROCKNIX | byte-identical |
| cmdline / IRQ affinity | — | no effect |
| gamescope `--xwayland-count 1` | fewer X servers in the path | **broke** gamepadui (needs 2) |
| Turnip **VM_BIND** patch (game **and** compositor) | redundant per-submit GPU sync | no difference (VM_BIND inactive on 7.0 + CPU-bound) |

## Kept (real wins)

- **Gaming sysctl** — `overlay/usr/lib/sysctl.d/60-pocknix-gaming.conf`, ported from armada:
  - `kernel.sched_rt_runtime_us=-1` — **the load-fragility fix.** gamescope's SCHED_RR compositor
    threads were hitting the default 95%/period RT throttle under load → display stalls. Desktop
    has no RT threads, so it was immune — which is why the symptom was gamescope-only. **This fixed
    the system-wide unresponsiveness during in-game Steam downloads and the in-game choppiness under
    load** — the biggest quality-of-life win of the whole effort.
  - `vm.dirty_bytes=256M` / `vm.dirty_background_bytes=64M` — cap dirty pages so a download flushes
    steadily instead of piling up and stalling in one writeback burst.
  - `+ watermark / page-cluster / watchdog` smoothing. (Omitted armada's `vm.swappiness=180` — that
    needs zram, which pocknix lacks.)
- **scx_lavd `--performance` re-enabled** (kernel sched_ext + BTF + tracing, schedutil default,
  `pocknix-lavd.service`): better 1% lows / pacing, latency-aware placement. Its earlier removal was
  on a misdiagnosis ("tracing overhead hurts fps", contradicted by an on-device A/B showing no fps
  delta).
- **Dropped the 3-7 affinity pin** — lavd does placement, and it needs the A510 littles *free* to
  offload batch work (downloads) so the UI stays responsive; a hard pin fought that.
- **gamescope present-path env** (from ChimeraOS/Bazzite `gamescope-session-plus`):
  `vk_xwayland_wait_ready=false`, `GAMESCOPE_DISABLE_ASYNC_FLIPS=1`, `ENABLE_GAMESCOPE_WSI=1`,
  `mesa_glthread=true`. No avg-fps change, but the SteamOS in-game fps cap now **holds steady**
  instead of overshooting — cleaner frame pacing.
- **ROCKNIX FEX JIT config** in `packages/fex-emu/Config.json` (Multiblock, DynamicL1Cache
  heuristics, DisableL2Cache, the relaxed-but-safe TSO set, MaxInst, etc. — **thunks kept ON**):
  a small but real **+1-2 fps**.
- **FEX `TUNE_CPU=cortex-x3`** (the SM8550 prime, vs the generic a78 default).
- **`limits.d`** (`deck` rtprio/nice/memlock) — the Deck-aligned capability path so gamescope can
  self-RR; lets the `pocknix-gamescope-rt` root helper eventually be retired.

---

## Root-cause conclusion

The residual ~15-20% is the **gamescope-vs-Plasma gap on the same box** — identical FEX, identical
Turnip, identical CPU/GPU config — so it is **100% the compositor/session**. gamescope's
nested-XWayland present path makes the FEX-translated game spend materially more CPU per frame than
kwin's path; on a CPU/FEX-bound workload that lands directly on the limiter. This is
**architectural, not a config knob**, and it is specific to **x86/FEX titles under gamescope** —
native-ARM games and the Plasma session don't pay it.

Why the reference stacks don't show it:
- **Plasma (same box):** kwin's present path is cheaper / more buffered.
- **ROCKNIX:** lean appliance + root session; efficient enough that its RR compositor never hits the
  RT throttle and its userspace present path is tighter.
- **armada:** also a full distro, but it shipped the gaming sysctl (RT throttle off) we were
  missing, plus a patched Turnip and `gamescope-session-plus`.

## Unexplored / future

The one genuinely-unexplored angle is **profiling where the game's extra per-frame CPU actually
goes under gamescope** — `perf record` on the game / XWayland / gamescope threads, gamescope vs
Plasma, to localize whether it's XWayland round-trips, the WSI buffer handoff, or FEX re-translation
through the nested X server. That would *localize* the architectural cost rather than guess at it,
but it's a profiling session, not a quick A/B. **`CONFIG_PSI=off`** (an armada/SteamOS gaming tweak)
was also identified but never tested — a remaining minor lever.

## Side-findings worth keeping

- **ROCKNIX's `ThunksDB` all-0 is *not* "thunks disabled".** It delivers thunks via its custom
  RootFS and uses per-app AppConfigs to turn specific ones *off* (e.g. the GL thunk for the Steam
  CEF UI). pocknix uses global thunks-on; applying ROCKNIX's config verbatim would have left the
  game with no thunks → emulated GPU stack → catastrophic.
- **The game's Turnip is the FEX-bundled one** (`/usr/share/fex-emu/libvulkan_freedreno.so`, owned
  by `fex-rootfs`), loaded *directly* by the FEX host Vulkan thunk — **not** the system
  `/usr/lib/libvulkan_freedreno.so` (which gamescope uses). Any Turnip experiment must patch both.
- **Turnip patches in the references:** ROCKNIX ships an SM8550 ir3 fix
  (`freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering`, a shader-compiler *correctness* fix —
  narrows a too-greedy const-promotion to constant-offset-only); armada ships the batocera
  `fix-freedreno-vulkan` ("VM_BIND fix" — drops redundant per-submit wait/signal fences). pocknix
  runs stock ALARM Turnip. Neither patch moved our fps (correctness vs inactive code path).
- **Steam Deck session model:** non-root `deck` user + `CAP_SYS_NICE` on the gamescope binary +
  `sched_rt_runtime_us=-1` — **not** run-as-root like ROCKNIX. pocknix matches the Deck (non-root
  is required anyway: PipeWire refuses root, Proton/bwrap prefer non-root).
