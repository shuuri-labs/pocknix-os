# Gamescope FPS-gap investigation

> **⚠️ VERDICT DISPUTED (2026-06-30, review pass).** The "architectural / irreducible emulation
> floor" conclusion below is **not supported by this doc's own data** and should NOT be treated as
> settled. The contradiction: ROCKNIX *also runs gamescope*, yet its game uses **~219% CPU** — i.e.
> at **kwin/Plasma efficiency (~216%)**, NOT at pocknix-gamescope's **~282%**. If the cost were
> inherent to gamescope's nested-XWayland present path, ROCKNIX-gamescope would pay ~282% too. It
> doesn't. **gamescope-the-compositor is exonerated; the gap is a pocknix-gamescope-vs-ROCKNIX-gamescope
> *session/config* delta** — the recoverable kind. Compounding this: **pocknix was never profiled at
> all** (every pocknix number is a `ps` snapshot), and ROCKNIX was profiled `-a` system-wide (69%
> idle, hand-rescaled), so the FEX-JIT/DXVK breakdown was never diffed against a matched pocknix
> profile. **Next step is diagnostic, not another A/B:** run `docs/fps-capture.sh` on the SAME scene
> on both OSes and diff `perf-by-dso.txt`. See **["Verdict dispute" below](#verdict-dispute-2026-06-30)**.
>
> **✅ RESOLVED 2026-06-30 (live session).** The dispute was right: it is NOT the irreducible
> emulation floor. A kwin-desktop control (same OS/FEX, only the compositor changed) runs the FEX game
> at 50-56 fps vs gamescope's 30-40, with GPU util 70-80% vs ~50% — so the gap is the **gamescope WSI
> present path starving the GPU**, and the leading suspect is the gamescope WSI Vulkan layer running
> **host-side (aarch64) on pocknix vs guest-side (x86_64) on ROCKNIX**. Several separate bugs (game
> forced to SCHED_RR → hitching; fan curve averaging → throttle; a vsync staircase) were also found
> and fixed. See **["Live on-device A/B session" below](#live-on-device-ab-session-2026-06-30--gap-isolated-to-the-gamescope-wsi-present-path)**.

## TL;DR

pocknix's **game-mode (gamescope) session runs x86/FEX games ~15-20% slower** than the *same*
game on (a) pocknix's own **Plasma** desktop and (b) **ROCKNIX** — both on the same
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
  - **armada** — Fedora bootc, full distro; the parallel fork we share patches/config with
    (`shuuri-labs/armada`). **Not benchmarked here** — referenced only as a source of config/patches,
    not as a known-faster baseline.

## Measured baseline

**Refined ordering (2026-06-30, maintainer):** the three configs are NOT two tiers — they're three:

| Configuration | speed | notes |
|---|---|---|
| **ROCKNIX** gamescope | **fastest** | |
| pocknix **Plasma Mobile** (kwin) | middle — beats pocknix-gamescope, **still a bit behind ROCKNIX** | |
| **pocknix gamescope** | **slowest** | ~40-48 fps; ~282% CPU @ ~45 fps in the orig snapshot |

This splits the problem into **two gaps**:
- **Gap A (big, recoverable): pocknix-gamescope → pocknix-Plasma.** Same box, same OS, same scx_lavd,
  same userspace — so this is purely the **gamescope-session setup** on pocknix. It also proves
  gamescope's present path is *not free* (Plasma beats it on the same box), **but** ROCKNIX-gamescope
  is the fastest of all, so gamescope *can* be cheap — pocknix's gamescope is paying an **avoidable
  surcharge** ROCKNIX's gamescope doesn't. This is the main target.
- **Gap B (small): pocknix-Plasma → ROCKNIX-gamescope.** pocknix's *best* still trails ROCKNIX even
  with no gamescope penalty → a compositor-independent **pocknix-vs-ROCKNIX userspace/base-load**
  margin (cortex-x3 build, Mesa 26.1.2 vs 26.1.3, lean appliance vs full distro, EEVDF vs lavd).
  Diminishing returns; the <1% tuned-userspace finding lives here.

So the goal is concrete: **drag pocknix-gamescope up to ROCKNIX-gamescope** (which would also overtake
pocknix-Plasma). There is real headroom — gamescope is the *fastest* config when set up like ROCKNIX.

Original snapshot (un-matched method, kept for reference): under gamescope ~**282% CPU for ~45 fps**;
under Plasma ~**216% CPU for ~60 fps** → ~70% more CPU per frame under gamescope. GPU ~60% throughout
→ CPU/FEX-bound, not GPU-bound. (Re-measure with `fps-capture.sh` for matched numbers.)

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

> **UPDATE 2026-06-30 — refined by live ROCKNIX profiling (see "Live ROCKNIX measurements" below).**
> The compositor present-path is *part* of it, but a `perf` profile showed the per-frame cost is
> dominated by the **irreducible x86-on-ARM emulation** (FEX-JIT ~45% + DXVK ~24% of *active* CPU),
> which ROCKNIX pays too. The `cortex-x3`-tunable libraries are <1% — **rebuilding tuned userspace
> is not worth it.** The box is mostly idle (latency-bound, not throughput-bound). Net: pocknix has
> matched ROCKNIX's real config levers; the residual is the emulation floor.

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

## Verdict dispute (2026-06-30)

A review pass found the root-cause conclusion above is **logically inconsistent with the measured
data** and rests on an **incomplete evidence base**. Treat it as an open question, not a result.

**1. The data exonerates gamescope.** Lining up the three numbers this doc reports:

| Session | CPU | fps | CPU/frame |
|---|---|---|---|
| pocknix **Plasma** (kwin) | ~216% | ~60 | baseline |
| **ROCKNIX gamescope** | ~219% | ~50–60 | ≈ Plasma |
| **pocknix gamescope** | ~282% | ~45 | **+~30–60%** |

ROCKNIX runs the *same compositor* (gamescope), *same* nested XWayland, *same* Steam-downloaded
Proton — and sits at **~219%, basically kwin efficiency**, far below pocknix-gamescope's ~282%. If
the penalty were inherent to gamescope's present path (the doc's claim), ROCKNIX-gamescope would also
be ~282%. It isn't. So the gap is **pocknix-gamescope vs ROCKNIX-gamescope** — a delta *within the
same compositor* — i.e. a **session/config difference**, not an architectural floor.

**2. The evidence base can't support the verdict.** pocknix was **never profiled** — every pocknix
figure is a `ps`/`top` CPU% snapshot. ROCKNIX was profiled with `perf record -a` (system-wide → 69%
idle), then hand-rescaled. The "pocknix pays the same FEX-JIT+DXVK floor" claim therefore diffs a
ROCKNIX profile against **no pocknix profile at all**. The 282-vs-219 comparison is also cross-OS
`ps` on possibly-different scenes / fps caps / process sets (root vs non-root `deck`).

**3. ARM64EC — checked, likely a red herring, cheap to confirm.** ROCKNIX's profile shows
`libarm64ecfex.dll`; pocknix's `packages/fex-emu/PKGBUILD` builds only `FEXInterpreter` + thunks (no
arm64ec interpreter) and the repo has zero arm64ec wiring. That *looks* damning but almost certainly
isn't: Valve's "Proton 11.0 ARM64" **bundles its own arm64ec FEX**, so an identical Proton means an
identical game emulation path regardless of the system FEX (which only handles the Steam client's own
x86 bits). Rule it out in 30s on the next burn: `grep -i arm64ec /proc/<game-pid>/maps` on **both**
OSes — if both show it, move on; if pocknix's game is *not* on arm64ec, that alone is the whole gap.

**4. What to actually do next (diagnostic, not config A/B).** Almost every config lever is already
ruled out, so the productive work is the missing measurement:
- **`docs/fps-capture.sh`** — run on the SAME steady scene on both OSes; it takes the matched
  `perf record -p <pid> -e task-clock` profile (the one pocknix never got), a matched per-thread CPU
  snapshot, the arm64ec check, present/refresh parity, and a config snapshot. Then
  `diff -y fps-capture-rocknix-*/perf-by-dso.txt fps-capture-pocknix-*/perf-by-dso.txt`.
- **Read the diff against levers:** pocknix higher in `[kernel.kallsyms]` → futex/syscall/scheduling
  = session overhead (deck cgroup/bwrap, `mesa_glthread`'s extra thread, glthread on the CEF UI) →
  *config*; higher in `[JIT]` → FEX/arm64ec path; higher in `gamescope`/`Xwayland` → present path =
  genuinely structural (only *then* is the verdict right).
- **Prediction:** the extra pocknix cycles land in `[kernel.kallsyms]` (session/scheduling), not in
  JIT/DXVK — consistent with ROCKNIX-gamescope ≈ Plasma — making this a recoverable session-config gap.
- Also possible the 282-vs-219 itself is a measurement artifact (scene/fps-cap/process-set). The
  matched capture settles that too. NB the present-interval check guards the EDID/60Hz angle: if
  pocknix's session lacks a real 60Hz mode it may pace against a different effective refresh.

## Matched capture — ROCKNIX half (2026-06-30, `docs/fps-capture.sh`)

The **proper per-process profile** (the one the doc never had): `perf record -p <game-pid> -e
task-clock` on ROCKNIX, ASBR steady scene. (perf 7.0.11 on ROCKNIX crashes in `addr2line` on the
Proton `.debug` paths — workaround baked into the capture: `--no-inline --symfs=<empty>`.) Raw capture
in scratchpad `captures/fps-capture-rocknix-20260630-144317/`. pocknix half still pending a burn.

**Self% by DSO (game process, active CPU — this is the diff target):**
```
49.89%  [JIT]                  (FEX-translated game code)
19.84%  d3d11.dll              (DXVK)
10.88%  [kernel.kallsyms]      (syscalls/futex/sched on the game's threads)
 5.59%  libvulkan_freedreno.so (Turnip)
 3.89%  ntdll.dll
 2.97%  libarm64ecfex.dll      (FEX arm64ec interpreter — present => arm64ec path ACTIVE)
 2.01%  ntdll.so   1.95% libc.so.6   0.96% winevulkan.so   0.39% ucrtbase.dll   ...
```
This *supersedes* the earlier hand-rescaled `-a` figures (FEX-JIT 45 / DXVK 24 / Turnip 6 / glibc 4).
The shape is the same, so the emulation profile is sound; what's new is a clean per-process baseline
to subtract pocknix from.

**Corrections to assumptions (all measured live this pass):**
- **Governor = `ondemand`** — NOT `schedutil` (this doc) and NOT `performance` (earlier). Big cores
  were clocked high during play (mid 2.71 GHz, prime 2.96 GHz; little 1.79 GHz), so the "clocks dip,
  still faster" framing is wrong *for the big cores*. CPU clock is still not the lever, but for the
  right reason (it's at-clock and latency-bound), not "schedutil dips low".
- **`cpu_capacity` (freq-scaled, live) = 222 / 657 / 1024** — this is the value pocknix must MATCH
  (distinct from the raw `capacity-dmips-mhz` 326/693/1024 the doc cites; different metric).
- **PSI is ON** on ROCKNIX (`/proc/pressure/cpu` populated). So **`CONFIG_PSI=off` is NOT a
  ROCKNIX-matching lever** — kill that "future" idea; the faster box runs with PSI on.
- **Scheduler = plain EEVDF, no scx.** pocknix runs scx_lavd — a real session difference to A/B in
  the eventual diff (lavd vs EEVDF on the *same* matched scene).
- **Hot thread placement:** the heavy `RenderThread` ran on **cpu7 (prime)** at ~58%, main thread on
  a mid, dxvk-cs on a mid. The doc's "game runs on a LITTLE core and still wins" was reading the
  aggregate on the main-thread line — the *hot* render thread is on the prime. Placement still isn't
  the lever, but the "little-core" claim was an artifact.
- **arm64ec CONFIRMED active** (`libarm64ecfex.dll` mapped; exe → wine-preloader, ARM64EC Proton).
  When pocknix is captured, confirm the same — if pocknix's game lacks it, that's the gap.

**The FEX-config finding (important — re-examine the "kept win"):** the FEX config actually in effect
for the game is the **Proton-bundled** one (`FEX_APP_CONFIG_LOCATION` → the Proton tree's
`share/fex-emu/Config.json`), which is *minimal*:
```
ProfileStats=1, X87ReducedPrecision=1, TSOEnabled=1, VectorTSOEnabled=0,
MemcpySetTSOEnabled=0, HalfBarrierTSOEnabled=1, MaxInst=500, Multiblock=1
```
The per-app `compatdata/<appid>/proton-fex-config.json` is empty `{}`; the AppConfig dir has no ASBR
entry. Since **both** OSes run the same Steam-downloaded Proton, both games get this *same minimal
Proton config*, merged over the distro/global FEX config. Implication: pocknix's elaborate
`packages/fex-emu/Config.json` (`MaxInst=5000`, DynamicL1Cache, DisableL2Cache, …) governs the
**Steam client's** x86, not necessarily the game's hot path (Proton's `MaxInst=500` wins for the
game). The doc's "ROCKNIX FEX JIT config → +1-2 fps" win needs re-checking against what FEX actually
merges for the game — **verify on the pocknix capture** (`fex-config.txt` + `/dev/shm/fex-*-stats`).

**Session/launch deltas worth the diff** (both run gamescope; these are the within-compositor diffs):
ROCKNIX launches `-W 1080 -H 1920 ... --use-rotation-shader` + the Steam appliance flags
(`-nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders`); pocknix uses `1920×1080 +
--force-composition-rotation` and lacks the appliance flags. gamescope unpinned (`Cpus_allowed 0-7`).
GPU `simple_ondemand` pegged 680 MHz, Turnip Mesa 26.1.2.

## Live on-device A/B session (2026-06-30) — gap ISOLATED to the gamescope WSI present path

A full matched on-device session (SSH, same RP6, same ASBR scene) resolved the verdict dispute and
found several distinct bugs that were all muddled together as "the 15-20% gap."

### The breakthrough — the kwin desktop control
Same FEX game, same pocknix install, switching **only the compositor**:

| Session | menus | gameplay | GPU util |
|---|---|---|---|
| pocknix **gamescope** | 50-60 | **30-40** | **~50%** |
| pocknix **Plasma (kwin)** | 60 | **50-56** | **70-80%** |
| ROCKNIX gamescope | 60-62 | 55-60 | — |

Same OS / background / FEX / lavd / daemons in both pocknix rows → **the gap is 100% the gamescope
session, NOT distro background overhead.** Under kwin the GPU is **fed (70-80%)**; under gamescope it
is **starved (~50%)** — the game blocks on gamescope's present/buffer cycle. pocknix's
userspace/FEX/Turnip are fine; kwin runs the FEX game within ~3-4 fps of ROCKNIX.

### The lead — gamescope WSI layer on the wrong side of the FEX thunk
The game loads a *different* gamescope WSI layer on each OS (from the matched perf captures):
- **ROCKNIX:** `libVkLayer_FROG_gamescope_wsi_x86_64.so` — **guest (x86)** side: present-sync happens
  inside emulation; FEX thunks only the final native present. One clean handoff.
- **pocknix:** `libVkLayer_FROG_gamescope_wsi_aarch64.so` — **host (ARM)** side: every
  `vkQueuePresentKHR`/`vkAcquireNextImageKHR` crosses the FEX thunk *then* does gamescope's WSI sync
  on the host. Hypothesis: that serializes the buffer return across the thunk → GPU starvation.

This fits every fact: gamescope-specific (kwin has no WSI layer → 70-80%), FEX-specific (native ARM
games don't cross the thunk → no gap), present-path blocking (cores idle between frames, GPU starved,
*less* total CPU but more CPU/frame).

**ROOT CAUSE CONFIRMED — pocknix is missing the guest-side (x86_64) gamescope WSI layer.**
- `ENABLE_GAMESCOPE_WSI=1` is a **red herring**: gamescope force-sets it (plus `GAMESCOPE_LIMITER_FILE`,
  `vk_khr_present_wait=true`, `STEAM_GAMESCOPE_DYNAMIC_FPSLIMITER=1`, …) on *every* child, so it stays
  in the game env even when removed from the launcher. Removing it changed nothing. Not a lever.
- pocknix ships **only the host layer**: `/usr/lib/libVkLayer_FROG_gamescope_wsi_aarch64.so` +
  `/usr/share/vulkan/implicit_layer.d/VkLayer_FROG_gamescope_wsi.aarch64.json`. There is **no x86_64
  layer anywhere** (not in `steamrtarm64`, compatibilitytools, or — by inference — the FEX guest
  rootfs `ArchLinux.sqsh`). ROCKNIX and a real Steam Deck ship the **x86_64** layer *inside the guest*.
- So on pocknix every `vkAcquireNextImageKHR`/`vkQueuePresentKHR` blocks **across the FEX thunk** on
  gamescope (gamescope sets `vk_khr_present_wait=true` → the app waits on present completion). That
  per-present thunk tax starves the GPU, and it scales with present frequency — **which is exactly why
  a `-r 60` session improved fps** (half the presents = half the thunk crossings). ROCKNIX's WSI sync
  is guest-side (pre-thunk), so 120Hz costs it nothing extra.

**THE FIX (to implement + test):** cross-build `libVkLayer_FROG_gamescope_wsi` for **x86_64** (pocknix
already has the x86 cross-toolchain in `packages/fex-emu`) — or lift ROCKNIX's prebuilt `.so` — and
ship it **with its `.json` manifest inside the FEX guest rootfs** (`/usr/share/vulkan/implicit_layer.d/`
in `ArchLinux.sqsh`), matching ROCKNIX/the Deck. Then the guest Vulkan loader loads it guest-side and
present-sync no longer crosses the thunk.

**STOPGAP (validated):** running the gamescope session at `-r 60` instead of `-r 120` measurably helps
(halves the per-present thunk/composite overhead). Not the real fix (ROCKNIX runs 120 fine), but free.

### Confirmed fixes this session
1. **Hitching (random GPU→0% stalls):** the *entire game* ran as **SCHED_RR rtprio 40** — Wine
   promotes it because `deck` has `rtprio 98` (granted in `limits.d` for gamescope) — with the RT
   throttle disabled → priority-inversion stalls. Demoting the game to SCHED_OTHER **fixed the
   hitching**. RT threads also bypass *both* lavd and EEVDF, which is why earlier scheduler A/Bs were
   meaningless. Interim fix on device: a watcher (`pocknix-rt-demote-watch`). **Proper fix TBD:** stop
   Wine RT-promoting the game without breaking gamescope's own RR (gamescope gets RR from the root
   `pocknix-gamescope-rt` service, so `deck`'s `rtprio 98` limit may be droppable — needs verifying).
2. **Fan curve** averaged all CPU/GPU zones → the X3 prime hotspot hit 93°C (past its 90°C trip) and
   throttled while the fan sat at PWM 153 (60%). **Fixed: drive off the hottest zone** (commit
   `4de213b`).
3. **Unmatched graphics settings** inflated the early numbers; at matched settings the per-DSO CPU
   profile is **identical** to ROCKNIX (FEX-JIT ~50-53 / DXVK ~20 / kernel ~11).
4. **`GAMESCOPE_DISABLE_ASYNC_FLIPS`** was a 120/3 = **40fps vsync staircase**; removed (the game can
   now exceed 40). Minor on its own.
5. **`-noshaders`** added to the Steam client flags (matches ROCKNIX; stops fossilize background
   shader compilation).

### Ruled out — valid, on-device, matched (supersedes earlier invalid A/Bs)
- **Thermal *throttling*:** `scaling_max_freq` holds at 2956800 even at 94°C; the 595 MHz dips are
  cores **idling between frames**, not a throttle ceiling. 94°C is real (and the fan fix helps) but is
  **not** the fps cap.
- **Rogue process / IRQ storm:** idle is **91% idle**; biggest consumer is `mangoapp` (~19% of one
  core); the top "interrupt" is reschedule-IPI (FEX thread wakeups), no device storm. No thief.
- **scx_lavd:** adds CPU pressure (PSI 15-19 vs ROCKNIX 10) but **zero fps change** once the game is
  SCHED_OTHER. (The original "no difference" was invalid — the game was RR, bypassing the scheduler.)
- **CPU clock:** cores pinned at max (2.0/2.8/2.96 GHz, *higher* than ROCKNIX's ondemand) yet slower.
- **Present mode (mailbox), rotation method** (`--use-rotation-shader` also needs a gamescope patch
  pocknix doesn't ship) — both user-confirmed not the fix.

### Key numbers
- Matched per-DSO Self% (game process, task-clock): essentially identical on both OSes.
- perf samples over 20s: **pocknix 59,590 vs ROCKNIX 64,689** → pocknix uses *less* total CPU at
  *lower* fps = more CPU **per frame** + waiting (the GPU-starvation signature).

## Unexplored / future

The one genuinely-unexplored angle is **profiling where the game's extra per-frame CPU actually
goes under gamescope** — `perf record` on the game / XWayland / gamescope threads, gamescope vs
Plasma, to localize whether it's XWayland round-trips, the WSI buffer handoff, or FEX re-translation
through the nested X server. That would *localize* the architectural cost rather than guess at it,
but it's a profiling session, not a quick A/B. **`CONFIG_PSI=off`** (an armada/SteamOS gaming tweak)
was also identified but never tested — a remaining minor lever.

## Investigations to run ON ROCKNIX (dual-boot)

The biggest weakness in this whole effort is that we mostly **inferred** ROCKNIX's behaviour from
source rather than measuring a *running* instance. ROCKNIX can be booted on the same device without
disturbing the internal install — see *"Temporarily boot the SD"* in
[`install-to-internal.md`](install-to-internal.md). Two open questions are worth driving from a live
ROCKNIX:

### 1. What actually causes the gamescope perf difference

Run the **same game, same scene** on ROCKNIX and capture, side-by-side with pocknix:

- **Per-thread CPU at a matched fps** — the money shot; directly tests the "~70% more CPU/frame"
  finding:
  ```sh
  ps -eLo psr,pcpu,tid,comm --sort=-pcpu | head -15
  ```
  Does ROCKNIX's `*.exe` use *less* CPU at *higher* fps, and on which core? If yes, it's a per-frame
  cost difference and the next step localizes it.
- **Localize the per-frame cost with a profiler** — the one thing that turns "architectural" into a
  named culprit:
  ```sh
  perf record -g -p <game-pid> -- sleep 10 ; perf report   # also profile the gamescope + Xwayland PIDs
  ```
  Compare hot stacks vs pocknix: is the extra time in XWayland round-trips, the Vulkan/WSI buffer
  handoff, or FEX re-translation through the nested X server?
- **Diff the present-path stack we only guessed at:**
  ```sh
  cat /proc/$(pidof gamescope)/cmdline | tr '\0' ' '; echo
  cat /proc/$(pidof gamescope)/environ | tr '\0' '\n' | grep -iE 'MESA|TU_|DXVK|PROTON|GAMESCOPE|FEX|vblank'
  vulkaninfo --summary | grep -iE 'driverName|driverInfo'      # Turnip version/patches
  # ROCKNIX's live FEX config + the per-app AppConfig / thunk set actually applied to the game
  ```
- **Confirm the config assumptions** (we asserted these from source):
  ```sh
  cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor          # performance?
  cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "EEVDF (no scx)"
  cat /sys/devices/system/cpu/cpu0/cpu_capacity /sys/devices/system/cpu/cpu7/cpu_capacity  # 326 / 1024?
  [ -r /proc/pressure/cpu ] && echo "PSI on" || echo "PSI off"
  grep Cpus_allowed_list /proc/$(pidof gamescope)/status                # is ROCKNIX's gamescope pinned?
  ```
  If ROCKNIX's game uses ~the same CPU/frame and the win is elsewhere, the residual is the userspace
  *build* (Turnip / glibc / xwayland / Proton-DXVK) — a thousand cuts, not a knob.

## Live ROCKNIX measurements + verdict (collected 2026-06-30)

ROCKNIX booted on the same RP6 (via the SD-boot toggle) running the **same Steam game (ASBR)**.
Summarised captures:

**Governor / scheduler / toolchain — corrects earlier *assumptions*:**
- CPU governor is **`schedutil`**, NOT `performance` (clocks dip below 2 GHz) — and it's *still
  faster* than pocknix at near-max clocks → **CPU clock is not the lever.** Scheduler: plain
  **EEVDF** (no scx/lavd).
- Toolchain (`projects/ROCKNIX/devices/SM8550/options`): `TARGET_CPU=cortex-x3
  +fp16+crypto+i8mm+bf16+memtag+sm4+sha3`, **SVE/SVE2 off**. Whole userspace (glibc, Turnip, …) is
  built cortex-x3 — **except FEX**, which `fex-emu/package.mk` remaps to **`TUNE_CPU=cortex-a78`**
  (it migrates across all cores). *(pocknix's FEX should be a78, not the x3 I set earlier.)*

**Per-thread CPU (`ps -eLo psr,pcpu,tid,comm`):**
```
PSR %CPU  COMMAND
  0  219  ASBR.exe        <- game on a LITTLE (A510) core, unpinned, and STILL faster
  3  23.5 steamwebhelper
  4  13.7 mangoapp
  3  10.0 wineserver
  5   8.7 Xwayland
  3   8.2 gamescope-wl
```
Game ≈ **219%** vs pocknix ~282% → ROCKNIX does **less CPU/frame**; placement is irrelevant.

**gamescope launch (`/proc/$(pidof gamescope)/cmdline`):**
```
gamescope -W 1080 -H 1920 -r 120 --xwayland-count 2 --mangoapp --backend drm \
  --force-orientation left --use-rotation-shader -e -- steam -steamdeck -steamos3 -gamepadui \
  -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders
```
vs pocknix: native-orientation `-W 1080 -H 1920` (we use 1920×1080), `--use-rotation-shader` (we use
#2228 composite), and the **Steam appliance flags** `-nobootstrapupdate -skipinitialbootstrap
-norepairfiles -noshaders` (we lack these). environ: only `GAMESCOPE_MODE_SAVE_FILE` +
`GAMESCOPE_FAKE_OUTPUT_MM=508x286` — **not** the gamescope-session-plus env vars, so those aren't its secret.

**GPU (`/sys/class/devfreq/*.gpu/`):** `simple_ondemand`, cur/max **680 MHz** — *same as pocknix* →
GPU clock not the lever (lower GPU util at the same clock = less GPU work/frame).

**Stack:** Turnip **Mesa 26.1.2** (cortex-x3-built + ir3 SM8550 patch; pocknix = ALARM stock 26.1.3).
Proton = Steam-downloaded **Valve Proton 11.0 (ARM64)**, *identical* to pocknix → DXVK/Proton **not**
a differentiator (ROCKNIX's own dxvk/wine pkgs are for its *non-Steam* Wine path).

**`perf record -a -e cpu-clock` (Self%):**
```
69.0%  [kernel.kallsyms]   <- MOSTLY IDLE: game uses ~2.5/8 cores; 5.5 idle = ~69%
14.2%  [JIT]  (FEX-translated game)
 7.5%  d3d11.dll  (DXVK)
 1.9%  libvulkan_freedreno  (Turnip)
 1.3%  libc.so.6
 1.1%  libarm64ecfex.dll   (ROCKNIX Proton uses the ARM64EC path)
 <1%   gamescope / Xwayland / mangoapp / libgallium
```
Rescaled to the ~31% **active** CPU: FEX-JIT ~45%, DXVK ~24%, Turnip ~6%, glibc ~4%.

**Verdict:**
1. Per-frame cost = **irreducible x86-on-ARM emulation** (FEX-JIT + DXVK) — not rebuildable; ROCKNIX
   pays it too.
2. cortex-x3-tunable libs (Turnip + glibc) ≈ **<1% overall** → **do not rebuild tuned userspace.**
3. Box mostly idle → **latency-bound, not throughput-bound** → max clocks don't help (why schedutil wins).
4. ROCKNIX's edge = its **FEX config** (matched, +1-2 fps) + a thin tuned-userspace margin (<1%). No hidden lever.

**Still-applicable config (not yet done):** Steam appliance flags (`-noshaders` *conditional* on a
cold shader cache + the no-update/bootstrap/repair flags); FEX `TUNE_CPU` **x3 → a78**; optionally
drop lavd `--performance` for plain schedutil (power/thermals, zero fps cost).

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
