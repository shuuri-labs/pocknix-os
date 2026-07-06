# Emulation setup

The emulation layer (`packages/pocknix-emulation` + friends) is "drop files in, play":
ES-DE is the frontend, RetroArch + standalone emulators do the work, and starred
favorites appear in the Steam library automatically. This doc covers what a user has
to supply and where it goes.

## Folder layout

Everything lives under `~/Emulation` (created on first login by `pocknix-roms-init`):

```
~/Emulation/
  ROMs/<system>/     games, one folder per system (gba, snes, ps2, switch, …)
  BIOS/              all BIOS / firmware / key files (see table below)
  Saves/             in-game saves (RetroArch tier)
  States/            save states (RetroArch tier)
  README.txt         short version of this doc, refreshed each login
```

A single copy of `~/Emulation` is self-contained — ROMs, BIOS, saves all travel together.

> NB the original dev device predates this layout and still uses `~/ROMs` with a nested
> `bios/` — seeds never migrate an existing setup. Fresh images get `~/Emulation`.

## BIOS files — names and locations

All BIOS files go in `~/Emulation/BIOS/` (flat, except where noted). **Exact filenames
matter**:

| System | Expected file(s) | Notes |
|---|---|---|
| **PS2 (ARMSX2)** | **`ps2-bios.bin`** | **Rename your BIOS dump to exactly this.** The seeded ARMSX2 config (`armsx2-PCSX2.ini.in`) points at `~/Emulation/BIOS/ps2-bios.bin`, which is what makes PS2 zero-setup — wrong name = ARMSX2 reports no BIOS found. Any region dump works (PS2 emulation isn't region-locked). |
| PS1 | `scph5501.bin` (US), `scph5500.bin` (JP), `scph5502.bin` (EU) | Standard libretro names, as dumped |
| Dreamcast | `dc/dc_boot.bin`, `dc/dc_flash.bin` | Note the `dc/` subfolder — Flycast's convention |
| GBA | `gba_bios.bin` | Optional (mGBA HLEs it); improves accuracy |
| Sega CD | `bios_CD_U.bin`, `bios_CD_E.bin`, `bios_CD_J.bin` | Genesis Plus GX names |
| Switch (Eden) | `prod.keys` + firmware | Drop in `BIOS/` or the folder Eden names on first run |
| PS3 (RPCS3) | `PS3UPDAT.PUP` | Installed via the RPCS3 GUI (File → Install Firmware), not a folder drop |
| Xbox (xemu) | BIOS/flash + HDD image | Selected in xemu's first-run settings; keep the files in `BIOS/` |

If a game won't boot, the emulator's error message names the exact file it wants —
missing/misnamed BIOS is the most common cause.

## Getting games into Steam

Star a game in ES-DE (Favorite button) → quit ES-DE → re-enter Game Mode → the game is
in the Steam library (in a "Pocknix" collection), launched via `pocknix-play`. Un-star
to remove. The sync (`pocknix-steam-sync`) runs at game-session start, while Steam is
down — favorites always appear on the *next* Game Mode entry, never mid-session.

## What's preconfigured (no user action)

- **RetroArch tier** (~25 systems): controller profiles (Steam Input virtual X360 pad),
  120Hz-panel pacing (swap interval 2), left-stick-as-dpad, per-system tuning seeds
  (GBA: integer scale + lcd3x).
- **ARMSX2 (PS2)**: setup wizard skipped, Vulkan renderer, full pad bindings, 2.5x
  upscale (~1120p), big-core pinning. User supplies `ps2-bios.bin` + games, nothing else.
- **ES-DE**: scans `~/Emulation/ROMs`, emulator lookup wired to the pocknix install
  paths (`es_find_rules.xml`).

## Per-system status (on-device verification)

| System | Emulator | Status |
|---|---|---|
| GBA | RetroArch/mGBA | ✅ verified end-to-end (controls, pacing, shader, Steam launch) |
| PS2 | ARMSX2 | ✅ verified end-to-end (Ape Escape 2: smooth @2.5x, pad works) |
| Other RetroArch systems | various cores | shares GBA's plumbing; untested per-system |
| Switch | Eden | installed, untested (needs user prod.keys) |
| PS3 | RPCS3 | installed, untested (expect "advanced tier" perf) |
| Xbox | xemu | installed, untested |
| PS Vita | Vita3K | installed, untested (content installs via GUI) |
| GC/Wii | Dolphin | pending VM source build |
| 3DS | Azahar | pending VM source build (riskiest build) |
| Wii U | Cemu via FEX | experimental; Android-port/Waydroid routes under consideration |
