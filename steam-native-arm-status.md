# Native ARM64 Steam on pocknix-os — status, blocker, and precedents

**Goal:** Steam Big Picture (`-gamepadui`) running the **native ARM64 Steam client** inside
`gamescope` (DRM backend) on the Retroid Pocket 6 (Qualcomm SM8550 / Adreno 740), on our
from-scratch Arch Linux ARM base. No FEX for the client (FEX only later for x86 *game* content).

_Last updated: 2026-06-19._

---

## TL;DR

The native ARM64 client **downloads, runs (as aarch64), loads all its libraries, and bootstraps**.
The remaining blocker is **inside Valve's experimental ARM Steam client's gamepad-UI init** — not
the OS. On launch the client fatals with:

```
src/steamexe/updateui_gl.cpp (310) : UpdateUI CreateGlFont regular failed
src/steamUI/Main.cpp (2391) : !"Fatal Error: Could not load module 'bin/vgui2_s.dll'"
execl failed, errno 2
```

`strace` shows `vgui2_s.so` *is* found (it opens successfully), and that the client pulls in the
**`steamrt64` (x86_64) pressure-vessel runtime** for parts of its UI — i.e. the experimental ARM
client mis-selects an x86 runtime and its updater fonts are missing. FEX does **not** address this
(it's not an x86-emulation problem).

---

## What works (validated on-device)

- **gamescope** — our ROCKNIX-patched build (`packages/gamescope`, commit `fe78bc6` + rotation-shader
  patch) drives the RP6 panel: `--backend drm --force-orientation left --use-rotation-shader`,
  1920x1080@120 (panel native 1080x1920@120, `rotation=<270>`). No KMS flip errors.
- **GPU/Vulkan** — Turnip on the Adreno 740 (`DRM_MSM=m` so firmware loads post-rootfs; see
  `docs/`/memory). `vulkaninfo` reports `Turnip Adreno (TM) 740`.
- **Native ARM64 Steam client** — `packages/pocknix-steam` (`pocknix-steam-install` +
  `pocknix-steam`, ported from ROCKNIX `Install Steam.sh` / armada `generate-steam-bootstrap.sh`):
  - runtime: `https://repo.steampowered.com/steamrt3c/images/latest-public-beta/steam-runtime-steamrt-arm64.tar.xz`
  - client manifest: `https://client-update.fastly.steamstatic.com/steam_client_publicbeta_linuxarm64`
    → `bins_linuxarm64_linuxarm64.zip` from `https://client-update.steamstatic.com`
  - installs to `~/.local/share/Steam/steamrtarm64` (+ `linuxarm64`); `file steamrtarm64/steam` =
    `ELF aarch64` (genuinely native — no "Exec format error").
- **Library deps resolved** — the UI module `steamui.so` and everything it `dlopen`s now load:
  - built **`gtk2`** (`packages/gtk2`; EOL/dropped from Arch) for `libgtk-x11-2.0.so.0`;
  - `gdk-pixbuf2` from ALARM for `libgdk_pixbuf-2.0.so.0`;
  - put **`steamrtarm64/` on `LD_LIBRARY_PATH`** (the client bundles `libvpx.so.6` and the
    `libav*` media stack there).
  - `ldd steamui.so` → **no "not found"**.
- **seatd** running (gamescope's DRM seat). DNS via systemd-resolved. Root partition expanded to
  fill the SD (sfdisk + resize2fs).
- **Bootstrap runs** — `steamrtarm64/steam -steamdeck -exitsteam` under **Xvfb** verifies + lays
  out `ubuntu12_32/64`, `steamrt64`, `steamrt64/pv-runtime`, writes to `package/tmp/`.

## The blocker (Valve experimental-client internals)

On the full `-gamepadui` launch (under gamescope, real Xwayland display):

1. **Updater UI fonts missing** — `BFileExists(m_FontFileRegular)` / `m_FontFileLight` fail →
   `UpdateUI CreateGlFont regular failed`. The publicbeta ARM payload appears to lack the updater
   UI fonts (they may only arrive via a *full* self-update, which our bootstrap doesn't trigger —
   it "verifies" and exits because the downloaded client is current).
2. **`vgui2_s` won't load** — `Could not load module 'bin/vgui2_s.dll'`. The `.so` is present and
   `strace` shows it `open`ed successfully from `steamrtarm64/` (fd 8), but it isn't loaded. The
   same strace shows the client opening the **`steamrt64/pv-runtime/steam-runtime-steamrt/…`**
   (x86_64 pressure-vessel) tree — suggesting the experimental ARM client is selecting the wrong
   (x86) runtime for the VGUI module.
3. **`execl failed, errno 2`** — harmless downstream: the client tries to exec
   `/root/.steam/root/steam_msg.sh` (its error-dialog helper) which doesn't exist.

Net: the client gets all the way to **UI init**, then the experimental ARM gamepad-UI fails to
assemble (fonts + runtime/module selection). This is Steam-client-internal.

---

## What we tried (chronological)

| Attempt | Result |
|---|---|
| Stock `steam-launcher` .deb (x86 bootstrap) | Pulled x86 `ubuntu12_32` runtime → `Exec format error` on aarch64. Wrong path; the **native** client is separate. |
| Native client install (ROCKNIX `Install Steam.sh` ported) | Client downloads + runs (aarch64). |
| `gtk2` build + `gdk-pixbuf2` | Fixed `libgtk-x11-2.0.so.0` / `libgdk_pixbuf-2.0.so.0`. |
| `steamrtarm64/` on `LD_LIBRARY_PATH` | Fixed `libvpx.so.6` (client-bundled libs). `ldd steamui.so` clean. |
| `seatd`, `cd` to valid CWD | Fixed seat + a `getcwd` path-resolution failure. |
| Full `.steam` symlinks (`sdk32/64/arm64`, `bin32→ubuntu12_32`, `bin64→ubuntu12_64`) | armada's layout; no change to the fatal. |
| **Xvfb bootstrap** (`steam -exitsteam` under a virtual X display) | Bootstrap now *completes* (verifies, lays out runtimes); was crashing before with no display. Big Picture still fatals. |
| Drop skip-flags (`-noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles`) | No change — those weren't the cause. |
| `~/.local/share/Steam/bin → steamrtarm64` symlink | No change — `bin/vgui2_s.dll` isn't resolved relative to the Steam root. |
| `strace` the launch | Revealed: `vgui2_s.so` *is* opened (fd 8); client pulls the **x86_64 `steamrt64` pv-runtime**; `execl errno 2` = missing `steam_msg.sh`. |

## Open hypotheses / next leads

1. **Updater fonts** — provide `m_FontFileRegular`/`m_FontFileLight`, or force a *full* self-update
   (not verify-only) so the client fetches its complete UI payload (fonts + correct module layout).
2. **Runtime mis-selection** — make the client use the **`steamrtarm64`** runtime instead of
   `steamrt64` (x86_64) for `vgui2_s`. Possibly: remove/empty the x86 runtime dirs, or a config/env
   that pins the arm64 runtime.
3. **Match a known-working tree** — diff `~/.local/share/Steam` against an armada/ROCKNIX device
   that boots Big Picture, and replicate the difference exactly.

---

## Precedents we're following

### ROCKNIX (`packages/emulators/standalone/steam`)
- `start_steam_arm64.sh` launches the **native** client:
  `gamescope … --backend drm --force-orientation <l/r> --use-rotation-shader -e -- \
   steamrtarm64/steam -steamdeck -steamos3 -gamepadui -noverifyfiles -nobootstrapupdate \
   -skipinitialbootstrap -norepairfiles -noshaders` (skip-flags because their install is
   pre-bootstrapped).
- `run_steam_first_launch()` (in `Install Steam.sh`) **bootstraps by running the x86 `/usr/bin/steam
  -exitsteam` under FEX twice**, then the native `steamrtarm64/steam -exitsteam`. So ROCKNIX uses
  **FEX for the first-time setup**, even though the client/games then run native.
- FEX (`packages/compat/fex-emu`) is a heavy from-source build (clang/LLVM + qt6 + nix for thunks).
  Thunks (GL/Vulkan/drm/asound) are for **x86 games**, not the native client.

### armada (github.com/virtudude/armada — Fedora bootc + ROCKNIX device support)
- **No FEX for the client.** `generate-steam-bootstrap.sh` bootstraps the **native arm64** client:
  downloads the same steamrt3c runtime + publicbeta linuxarm64 client, creates the full `.steam`
  symlink set (`sdk32/64/arm64`, `bin32→ubuntu12_32`, `bin64→ubuntu12_64`), then runs
  `steamrtarm64/steam -steamdeck -exitsteam` **under `Xvfb :99` with a 900s timeout** to
  self-update + write `.installed`. **This is the method we replicated.**
- FEX is a **prebuilt package** (`ghcr.io/virtudude/armada-packages/fex` → `fex-emu-*.rpm`); x86
  rootfs is a packaged `default.erofs` (`fex-emu-rootfs-fedora`); thunks enabled for x86 games.
- Steam session via `gamescope-session-steam`; CachyOS Proton 11 (arm64) for x86 game content.

### Key takeaway
Both run the **native ARM client** (the user confirms it performs much better than x86 Steam under
FEX). FEX is needed only for **x86 game content (Proton)**, not the client. armada proves the client
bootstraps **without FEX** (native + Xvfb). Our setup reaches the same bootstrap state; the delta is
the experimental gamepad-UI's font/runtime init, which armada's *fully pre-staged* tree apparently
satisfies and ours (a from-scratch Arch base) does not yet.

---

## Reproduce / inspect

```bash
# install (native, no FEX):  ~/.local/share/Steam/steamrtarm64
pocknix-steam-install
# launch:
pocknix-steam                 # gamescope + native client -gamepadui

# the failing path (strace):
strace -f -e trace=execve,openat -qq \
  env LD_LIBRARY_PATH="$HOME/.local/share/Steam/steamrtarm64:$HOME/.local/share/Steam/lib/aarch64-linux-gnu" \
  "$HOME/.local/share/Steam/steamrtarm64/steam" -steamdeck -steamos3 -gamepadui 2>&1 \
  | grep -iE 'vgui2_s|steamrt64|execve|FontFile'
```

Packages involved: `packages/{gamescope,gtk2,inputplumber,pocknix-bsp,pocknix-steam}`.
