# Emulation

pocknix-os offers **ES-DE** as the frontend, with RetroArch and a few standalone emulators doing
the work. It is "drop your files in and play": no per-emulator setup, and ES-DE plus every
emulator can get a tile in your Steam library when installed from the Pocknix Store.

## Supported systems

| System | Emulator |
|---|---|
| NES / Famicom | RetroArch (FCEUmm) |
| SNES / Super Famicom | RetroArch (Snes9x) |
| Nintendo 64 | RetroArch (Mupen64Plus-Next) |
| Game Boy / Game Boy Color | RetroArch (Gambatte) |
| Game Boy Advance | RetroArch (mGBA) |
| Nintendo DS | RetroArch (melonDS) |
| Nintendo 3DS | Azahar |
| GameCube / Wii | Dolphin |
| Wii U | Cemu |
| Nintendo Switch | Eden or Ryujinx (bring your own build, see [below](#using-your-own-emulator-build)) |
| Sega Master System / Genesis / Game Gear / Sega CD | RetroArch (Genesis Plus GX) |
| Sega Saturn | RetroArch (YabaSanshiro) |
| Sega Dreamcast | RetroArch (Flycast) |
| PlayStation | RetroArch (DuckStation) |
| PlayStation 2 | ARMSX2 |
| PlayStation Portable | PPSSPP |
| PlayStation 3 | RPCS3 |
| PlayStation Vita | Vita3K |
| Xbox | xemu |
| Arcade / Neo Geo | RetroArch (FBNeo) |

## Installing it

Emulation is optional, so a fresh install does not have it. Open the **Pocknix Store** (its tile
in your Steam library, or the app menu in desktop mode) and either:

- **Install all**: ES-DE, Steam ROM Manager and every emulator, kept up to date as one set.
- **Pick**: tap an emulator, then *Install*. Install only the ones you want; ES-DE is its own
  entry.

Every install runs a full system update first, so it can take a while; everything is ready when
it finishes, with no restart or logout needed. Closing the store does not stop it, and opening it
again shows the progress.

Tap an installed emulator to *Remove* it, or use *Remove all*. Removing one emulator from an
*Install all* set keeps the others installed. Your ROMs, BIOS files, saves and emulator settings
stay where they are, so installing again later picks up exactly where you left off.

## Where your files go

Everything lives under `~/Emulation` (created for you on first login):

```
~/Emulation/
  ROMs/<system>/     your games, one folder per system (gba, snes, psx, ps2, ...)
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
`/run/media/deck/<card label>/ROMs`). Move your files there, then rescan. `BIOS/`, `Saves/`, and `States/`
stay in `~/Emulation`.

Steam ROM Manager, Dolphin, Cemu and Ryujinx were pointed at the ROM folder when they were set up, and
keep the old one. In the **Pocknix Store**, tap each of them and pick *Restore default settings*
(your old file is kept as a `.bak-<date>` copy), then *Add Games* and *Save to Steam* in Steam ROM
Manager again so your game tiles use the new paths.

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
| **Nintendo Switch** | `prod.keys`, `title.keys` + firmware | Not in `BIOS/`. Eden: keys in `~/.local/share/eden/keys/`, firmware `.nca` files in `~/.local/share/eden/nand/system/Contents/registered/`. Ryujinx: keys in `~/.config/Ryujinx/system/`, firmware installed from its own menu. |

If a game will not boot, the emulator's error message usually names the exact file it is missing.
A missing or misnamed BIOS is the most common cause.

## Copying files over the network

Rather than shuttling a microSD card back and forth, you can turn the device into a network
share and drag files straight onto it from another computer. It works out of the box in macOS
Finder, Windows Explorer and Linux file managers - no extra software on either end.

Turn it on in either place:

- **Game Mode**: Quick Access Menu → **Pocknix Control** → **Library** → *Share my home folder*
- **Desktop**: **Pocknix Tools** → *File sharing (SMB) is off - turn it on...*

The first time, you will be offered a small download (Samba is not shipped in the image, so
devices that never share a file never pay for it). It then stays on across reboots until you
turn it off in the same place.

Once it is on, open one of these from the other computer:

| | |
|---|---|
| macOS | Finder → the device appears in the sidebar under **Network**, or press ⌘K and enter `smb://pocknix.local` |
| Windows | Explorer address bar: `\\pocknix.local` |
| Linux | Files → *Other Locations* → `smb://pocknix.local` |

**Connect as Guest - there is no password.** Two shares appear:

- **deck** - your home folder, so `Emulation/` for ROMs and BIOS, and the per-emulator folders
  described above for firmware and keys
- **sdcard** - whatever is in the SD card slot

> [!WARNING]
> There is no password, so **anyone on the same network** can read and write everything in your
> home folder - not just games and saves, but your Steam login and SSH keys too. Sharing is
> limited to private home-network address ranges, so joining public wifi does not expose the
> device, but treat it as "on while I am at home" rather than something to leave running.

## Getting games into Steam

After an install, the Pocknix Store offers to add a Steam tile for each new emulator (ES-DE and
Steam ROM Manager included). Later, tap an installed emulator to switch its tile on or off, or use
*Add Steam tiles* for all of them. If Steam cannot take new tiles right then (still starting, for
example), wait or close Steam, then try again. Updates never add a tile or bring back one you
deleted, and installing an emulator with pacman adds none either: run
`pocknix-tiles enable <emulator>` from a desktop terminal (for example `pocknix-tiles enable
dolphin`, or `esde` for ES-DE). Adding tiles also removes ES-DE favourite tiles left by an older
Pocknix. Removing an emulator removes its tile. The emulator tiles open the emulator's own menu
with the normal controller layout. Menus built for a mouse (Dolphin, Azahar, Cemu, RPCS3) can be
driven with Steam's mouse controls, or pick another layout for the tile in Steam; Steam keeps
that choice even if the emulator is reinstalled.

ES-DE favourites are not added to Steam. To put individual games in your library, with cover
art, use **Steam ROM Manager**. It needs Steam closed while it saves, so it runs in Desktop Mode:

1. Open the *Steam ROM Manager* tile in Game Mode and confirm the switch to Desktop Mode (or
   open it from the desktop app menu with Steam closed). It opens by itself.
2. It comes set up with one parser per system, pointing at your ROM folder, each launching
   games the same way ES-DE does, and at the Steam account you are signed in to (it asks if none
   was signed in yet).
3. Choose *Add Games*, then *Save to Steam*. Artwork comes from SteamGridDB, fetched on the
   device.
4. Close it and return to Game Mode from the desktop: the games are in your library.

Its window is sized to fit your screen. If part of it is still cut off, try a smaller scale once
from a desktop terminal (`POCKNIX_SRM_SCALE=1.4 steam-rom-manager`), then keep the one that fits:

```
mkdir -p ~/.config/plasma-workspace/env
echo 'export POCKNIX_SRM_SCALE=1.4' > ~/.config/plasma-workspace/env/srm-scale.sh
```

It applies from the next switch to Desktop Mode, the tile included. Delete the file to go back to
the automatic size.

Avoid SRM's own emulator presets: they start the emulators directly and skip the Pocknix
launch settings (CPU pinning, RetroArch frame pacing). *Restore default settings* on Steam ROM
Manager in the Pocknix Store restores the Pocknix SRM parsers.

## Tweaking individual emulator settings

Defaults are tuned for the RP6, but you can change per-emulator settings any time:

- **RetroArch systems** (NES, SNES, N64, Game Boy, GBA, DS, Genesis, Saturn, Dreamcast,
  PlayStation, Arcade, and more): while a game is running, open the **RetroArch Quick Menu**
  (click both sticks in, L3 + R3, on the controller, or press F1 on a keyboard). From there you can
  change the core options, video/shader settings, controls, and save an override that applies to
  that game or that whole system.
- **Standalone emulators** (ARMSX2 for PS2, RPCS3 for PS3, Vita3K for PS Vita, Dolphin for
  GameCube/Wii, Cemu for Wii U, PPSSPP for PSP, Azahar for 3DS, xemu for the original Xbox,
  Eden or Ryujinx for Switch): each has its own in-app settings menu. Launch the emulator
  from the desktop to reach its full configuration UI.

Pocknix sets each emulator up once, the first time it is installed (an Eden or Ryujinx build you
drop in: the first time it launches). After that the settings are
yours: updates never change them. Tap an emulator in the **Pocknix Store** and pick *Restore
default settings* to put it back to the current Pocknix defaults, keeping your old file as a
`.bak-<date>` copy.

ES-DE's system list and emulator lookup (`~/ES-DE/custom_systems/es_systems.xml` and
`es_find_rules.xml`) are links to the Pocknix copies, so they stay in step with updates. To use
your own, replace the link with a real file, for example
`cp --remove-destination /usr/share/pocknix-emulation/es_systems.xml ~/ES-DE/custom_systems/`,
then edit it. Restoring the ES-DE defaults puts the link back.

## Using your own emulator build

Every standalone emulator has a folder under `~/Emulation/emulators/`: `eden`, `ryujinx`,
`armsx2`, `rpcs3`, `vita3k`, `xemu`, `dolphin`, `cemu`, `azahar`, `ppsspp`. Put **one** file in
it, an AppImage or a binary, and Pocknix launches that instead of its own build, from ES-DE and
from Steam alike, with the same pre-made settings. Remove the file to go back to the
built-in one. A folder with more than one file is ignored.

**Nintendo Switch is bring-your-own only.** Pocknix ships no Switch emulator. Drop an Eden or a
Ryujinx build into its folder and it is set up on first launch: controller, fullscreen, vsync and
resolution. With both present, choose which one runs in ES-DE under *Other Settings, Alternative
Emulators*; Steam tiles follow that choice. If you had Eden installed by an earlier Pocknix
version, it is moved into `~/Emulation/emulators/eden/` for you and keeps working.

## What is already set up for you

- **RetroArch**: controller mapping, 120Hz-panel frame pacing, and sensible per-system tuning
  (for example integer scaling and an LCD shader on GBA).
- **PlayStation 2 (ARMSX2)**: setup wizard skipped, Vulkan renderer, controller bound, and
  upscaling enabled. You only supply `ps2-bios.bin` and your games.
- **Nintendo Switch (Eden or Ryujinx, your own build)**: controller bound, fullscreen, vsync and
  resolution tuned for the panel. You supply the emulator, your keys and firmware (see above)
  and your games.
- **ES-DE**: scans `~/Emulation/ROMs` and already knows where every emulator is installed.
