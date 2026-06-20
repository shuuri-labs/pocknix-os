# Phase 3b — x86 game content via FEX + Proton (scoped plan)

**Status: STARTED (2026-06-20).** Piece 1 (the FEX-with-thunks build) is scaffolded —
`packages/fex-emu/` — pending its first VM build. The native ARM Steam client + Big-Picture UI
run with **no FEX** (see [`../steam-native-arm-status.md`](../steam-native-arm-status.md) —
superseded for the client, still relevant for context — and `progress.md`). FEX is needed
**only for x86 _game_ content** (Proton).

_Last updated: 2026-06-20._

---

## RESOLVED: the thunk-build crux (2026-06-20)

The plan's biggest unknown — "the thunk build (ROCKNIX needs nix; generic FEX lacks thunks)" —
is **answered**. Decisions, with the research that settled them:

- **Option A (grab a prebuilt ALARM/AUR/holo fex-with-thunks) is DEAD.** AUR `fex-emu` has the
  historical ALARM blocker (no x86 cross-toolchain → no thunks; FEX issue #1996). Valve's
  **holo-core-aarch64-preview ships NO fex at all** (swept all 4,550 core+extra pkgs, 0 matches).
  Nobody in the Arch ecosystem publishes aarch64 FEX with thunks.
- **We do Option B, ported from armada — and armada already killed the nix dependency.**
  `github.com/virtudude/armada-packages/fex` builds FEX-with-thunks **without nix**: it DROPS
  ROCKNIX's nix patch (0004) and cross-compiles the x86 *guest* thunks with plain
  `clang -target x86_64/i686-linux-gnu --sysroot=<x86 dev sysroot>`, driven by two
  `toolchain_x86_{32,64}.cmake` files. The sysroot is just x86 glibc/libstdc++/kernel-headers
  (both bitnesses) — armada builds it from Fedora RPMs; **we build it from pinned Arch x86_64 +
  lib32 packages (`archive.archlinux.org`)** so the whole build stays inside our `make packages`
  chroot. Patches: 0001/0002/0003/0005/**0006** (0006 = armada-original, fixes glibc≥2.41 SVE
  math-header leakage in thunkgen — our Arch glibc is 2.43, so required). FEX commit pinned to
  `a04b0241` (same as ROCKNIX + armada).
- **Arch-vs-Fedora gotcha baked in:** Fedora puts 32-bit libs in `/usr/lib`, Arch in `/usr/lib32`;
  the 32-bit toolchain file adds an explicit `-L<sysroot>/usr/lib32`. The C++ header triple dir is
  `x86_64-pc-linux-gnu` (Arch) vs `x86_64-redhat-linux` (Fedora). Most-likely first-build failure
  point = 32-bit guest-thunk link; iterate on real `makepkg` output.

`packages/fex-emu/` = the build only (mirrors armada's `fex-emu.spec` output: `/usr/bin/FEX*`,
`/usr/lib/fex-emu/HostThunks{,_32}`, `/usr/share/fex-emu/GuestThunks{,_32}`, binfmt.d drop-ins).
Our config/rootfs/binfmt-enable/Turnip/Proton wiring = the later pieces below.

---

## The key fact (answered)

**Proton 11 ARM is NOT self-contained.** The CachyOS arm64 Proton is the Wine/Proton layer
(WoW64 / ARM64EC target); the x86→ARM translation is **FEX**, which must be installed and wired at
the **OS level**. Both our reference distros prove this — neither relies on Proton bundling FEX:

| Piece | ROCKNIX (`compat/fex-emu`) | armada (`build_files/30-install-steam-session.sh`) |
|---|---|---|
| **FEX** | **source build**, pinned commit `a04b0241…`, `BUILD_THUNKS=True` (clang/LLVM + ninja + qt6 + **nix** for guest thunks); patches for llvm18 ICE, char-signedness, sysroot hostlibs | **prebuilt rpm** (`ghcr.io/virtudude/armada-packages/fex`) built **with thunks** ("Fedora's FEX lacks thunks") |
| **x86 RootFS** | `Config.json RootFS="ArchLinux"` (x86 Arch rootfs) | `fex-emu-rootfs-fedora` → `default.erofs` (+ `erofs-fuse`/`erofs-utils`) |
| **Thunks** | built host+guest: `ThunkHostLibs=/usr/lib/fex-emu/HostThunks`, `ThunkGuestLibs=/usr/share/fex-emu/GuestThunks`; `ThunksDB` asound/drm/Vulkan/WaylandClient/GL (default 0, toggled per-game) | shipped in rpm; same thunk set |
| **Native GPU passthrough** | copies **`libvulkan_freedreno.so`** (Turnip) into `/usr/share/fex-emu/` so the Vulkan thunk hits the real Adreno driver | via thunks |
| **binfmt** | `systemd-binfmt` registers FEX for x86/x86_64; start_steam **disables** it (`echo 0 > /proc/sys/fs/binfmt_misc/x86*`) during the **native** launch, re-enables at end (`systemctl restart systemd-binfmt`) | `systemd-binfmt`; units order `After=systemd-binfmt.service` |
| **Proton** | FEX wraps even the x86 _client_ (`FEX /usr/bin/steam …`); Proton 11 arm64 for games | **CachyOS Proton 11** `proton-cachyos-11.0-YYYYMMDD-slr-arm64` → `compatibilitytools.d` (pin sha512); toolmanifest patched to call a wrapper |
| **Per-game FEX config** | `start_steam.sh` writes `Config.json ThunksDB` from ES per-game settings | `armada-proton-wrapper` (py) writes a per-game `FEX_APP_CONFIG` (thunk on/off + profile) then exec's real Proton |

So: **FEX (with thunks) + x86 rootfs + binfmt + native-Vulkan passthrough + a Proton build + a
per-game config shim.** Six pieces, all OS-level.

> Caveat: the `-slr` in the Proton name = Steam Linux Runtime; Valve/CachyOS are trending toward
> putting more FEX inside the runtime, so this *may* get more self-contained later. As of the current
> working armada, it is not.

---

## Recommended approach for pocknix-os

Lean on **armada's model** (prebuilt-style) over ROCKNIX's from-source where we can — ROCKNIX's FEX
build drags in **nix** for the guest thunks (`curl nixos.org/nix/install` mid-build), clang/LLVM, and
qt6; that's the single gnarliest build in either distro. Decision points:

1. **FEX package (`packages/compat/fex-emu`)** — the heavy item.
   - Option A (preferred if viable): a **prebuilt aarch64 FEX _with thunks_** (like armada's rpm) —
     but Arch/ALARM/AUR `fex-emu` likely **lacks thunks**; verify before relying on it. No thunks =
     x86 games emulate the whole GL/Vulkan stack = unusably slow.
   - Option B: **build from source via makepkg**, `-DBUILD_THUNKS=True`, mirroring ROCKNIX's CMake
     opts + patches, but try to **avoid the nix dance** (investigate whether guest-thunk gen can use
     our toolchain directly). This is the real work.
   - Either way: ship `HostThunks` + `GuestThunks`, base `Config.json`, and copy the native
     **`libvulkan_freedreno.so` (Turnip)** in for the Vulkan thunk.
2. **x86-64 RootFS** — fetch via `FEXRootFSFetcher` (Ubuntu/Arch x86 squashfs/erofs), ship it in the
   image (hundreds of MB–GB → bumps image size + `SD_SLACK_MIB`), mount via squashfuse/erofsfuse.
   Point `Config.json RootFS=` at it.
3. **binfmt** — `systemd-binfmt` drop-in registering FEXInterpreter for x86/x86_64. Consider ROCKNIX's
   toggle (disable during native-client ops) — but our client is already native, so likely just leave
   it on (armada does). Validate the native session still behaves with binfmt active.
4. **Proton** — download **CachyOS Proton 11 arm64** at build (pin sha512), drop into
   `/usr/share/steam/compatibilitytools.d`, patch `toolmanifest.vdf` to call a wrapper.
5. **Per-game FEX-config wrapper** — small shim (armada-proton-wrapper style) that sets
   `FEX_APP_CONFIG` / thunk toggles per appid. Start with thunks ON globally; add per-game tweaks later.
6. **Default compat tool** — set Proton as the default so x86 titles use it (armada
   `set-steam-default-compat.py`).

## Build/wiring order (when we start)
1. `packages/compat/fex-emu` (FEX + thunks) → local repo; install via `install_local_packages`.
2. x86 rootfs artifact + fuse mount tooling → image; `Config.json` wired.
3. binfmt drop-in (probably in `pocknix-bsp` or a new `pocknix-fex` pkg) + enable `systemd-binfmt`.
4. Proton download/pin in `build-image.sh` (or a `pocknix-proton` pkg) → compatibilitytools.d.
5. Proton wrapper + default-compat seed.
6. On-device: install an x86 title, verify it runs + uses Turnip (thunks), tune `ThunksDB`/TSO.

## Risks / open questions
- **Thunk build** is the crux (ROCKNIX needed nix; generic FEX lacks thunks). Biggest unknown.
- **Image size / storage** — x86 rootfs + Proton + games need real space; folds into the deferred
  first-boot root-fs **expand** TODO.
- **TSO / perf** — `Config.json TSOEnabled=1` (x86 memory-ordering correctness); check SM8550 cores
  for hardware TSO (`HardwareTSO`) to avoid the software-barrier cost.
- **`libvulkan_freedreno.so` provenance** — ROCKNIX copies it from its toolchain; we'd take ALARM's
  Turnip (already validated on-device).
- Reference: armada `build_files/30-install-steam-session.sh`, `system_files/usr/libexec/armada/
  armada-proton-wrapper`, `usr/share/armada/fex-profiles.json`; ROCKNIX `compat/fex-emu/package.mk` +
  `config/fex-emu/Config.json` (vendored at `vendor/rocknix-sm8550/reference/compat/fex-emu/`).
