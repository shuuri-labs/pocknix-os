# Emulation

pocknix-os ships **ES-DE** as the frontend, with RetroArch and a few standalone emulators doing
the work. It is "drop your files in and play": no per-emulator setup, and games you favorite in
ES-DE show up in your Steam library automatically.

For the full list of supported systems, see the [README](../README.md#emulation).

## Where your files go

Everything lives under `~/Emulation` (created for you on first login):

```
~/Emulation/
  ROMs/<system>/     your games, one folder per system (gba, snes, ps1, ps2, ...)
  BIOS/              BIOS / firmware / key files (see below)
  Saves/             in-game saves
  States/            save states
```

Drop each game into the folder for its system (`~/Emulation/ROMs/gba/`, `~/Emulation/ROMs/snes/`,
and so on), then rescan in ES-DE. A single copy of `~/Emulation` is self-contained: ROMs, BIOS,
and saves all travel together.

### Putting ROMs on an SD card

The ROM directory can live anywhere, and ES-DE is the single source of truth. Go to **ES-DE Menu
→ Other Settings → ROM directory** and point it at the new location (for example
`/run/media/<card>/ROMs`). Move your files there, then rescan. `BIOS/`, `Saves/`, and `States/`
stay in `~/Emulation`.

## BIOS and firmware

Some systems need BIOS or firmware files that pocknix cannot ship. Put them in
`~/Emulation/BIOS/`, and **use the exact filenames** below:

| System | File(s) | Notes |
|---|---|---|
| **PlayStation 2** | `ps2-bios.bin` | Rename your BIOS dump to exactly this. Any region works. |
| PlayStation | `scph5501.bin` (US), `scph5500.bin` (JP), `scph5502.bin` (EU) | Standard names, as dumped. |
| Dreamcast | `dc/dc_boot.bin`, `dc/dc_flash.bin` | Note the `dc/` subfolder. |
| Sega CD | `bios_CD_U.bin`, `bios_CD_E.bin`, `bios_CD_J.bin` | One per region. |
| Game Boy Advance | `gba_bios.bin` | Optional; improves accuracy. |

If a game will not boot, the emulator's error message usually names the exact file it is missing.
A missing or misnamed BIOS is the most common cause.

## Getting games into Steam

Favorite a game in ES-DE (the Favorite button), quit ES-DE, and re-enter Game Mode. The game
appears in your Steam library in a "Pocknix" collection, ready to launch straight from Big
Picture. Un-favorite to remove it. Favorites are synced when you enter Game Mode, so they show up
on the next entry, never mid-session.

## Tweaking individual emulator settings

Defaults are tuned for the RP6, but you can change per-emulator settings any time:

- **RetroArch systems** (NES, SNES, N64, Game Boy, GBA, DS, Genesis, Saturn, Dreamcast,
  PlayStation, PSP, Arcade, and more): while a game is running, open the **RetroArch Quick Menu**
  (hold Select and press X on the controller, or press F1 on a keyboard). From there you can
  change the core options, video/shader settings, controls, and save an override that applies to
  that game or that whole system.
- **Standalone emulators** (ARMSX2 for PS2, Dolphin for GameCube/Wii, PPSSPP for PSP, Azahar for
  3DS): each has its own in-app settings menu. Launch the emulator from the desktop to reach its
  full configuration UI.

## What is already set up for you

- **RetroArch**: controller mapping, 120Hz-panel frame pacing, and sensible per-system tuning
  (for example integer scaling and an LCD shader on GBA).
- **PlayStation 2 (ARMSX2)**: setup wizard skipped, Vulkan renderer, controller bound, and
  upscaling enabled. You only supply `ps2-bios.bin` and your games.
- **ES-DE**: scans `~/Emulation/ROMs` and already knows where every emulator is installed.
