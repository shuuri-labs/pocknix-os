# Emulation

pocknix-os offers **ES-DE** as the frontend, with RetroArch and a few standalone emulators doing
the work. It is "drop your files in and play": no per-emulator setup, and ES-DE plus every
installed emulator get their own tile in your Steam library.

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
| Nintendo Switch | Eden or Ryujinx (bring your own build, see [below](#using-your-own-emulator-build)) |
| Sega Master System / Genesis / Game Gear / Sega CD | RetroArch (Genesis Plus GX) |
| Sega Saturn | RetroArch (YabaSanshiro) |
| Sega Dreamcast | RetroArch (Flycast) |
| PlayStation | RetroArch (DuckStation) |
| PlayStation 2 | ARMSX2 |
| PlayStation Portable | PPSSPP |
| Arcade / Neo Geo | RetroArch (FBNeo) |

## Installing it

Emulation is optional, so a fresh install does not have it. Switch to desktop mode, open
**Pocknix Tools** and pick *Install the emulation layer (ES-DE + emulators)*. It is a large
download; everything is ready when it finishes, with no restart or logout needed.

The same entry removes the layer again. Your ROMs, BIOS files, saves and emulator settings stay
where they are, so installing it again later picks up exactly where you left off.

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

ES-DE and each installed emulator have their own tile in your Steam library, added when the
emulator is installed: straight away while Steam is open, or the next time Steam starts if it was
closed. Removing an emulator removes its tile. A tile you delete yourself stays deleted, even when
the emulator updates or is reinstalled. If Steam was still starting up during the install, the
tile is skipped: add it from a desktop terminal with `pocknix-tiles enable <emulator>` (for
example `pocknix-tiles enable dolphin`, or `esde` for ES-DE). The emulator tiles open the emulator's
own menu with the normal controller layout. Menus built for a mouse (Dolphin, Azahar, Cemu,
RPCS3) can be driven with Steam's mouse controls, or pick another layout for the tile in Steam;
Steam keeps that choice even if the emulator is reinstalled.

ES-DE favourites are not added to Steam. To put individual games in your library, with cover
art, use **Steam ROM Manager**. It needs Steam closed while it saves, so it runs in Desktop Mode:

1. Open the *Steam ROM Manager* tile in Game Mode and confirm the switch to Desktop Mode (or
   open it from the desktop app menu with Steam closed). It opens by itself.
2. It comes set up with one parser per system, pointing at your ROM folder, each launching
   games the same way ES-DE does. The first time, it asks which Steam account to add them to.
3. Choose *Add Games*, then *Save to Steam*. Artwork comes from SteamGridDB, fetched on the
   device.
4. Close it and return to Game Mode from the desktop: the games are in your library.

Avoid SRM's own emulator presets: they start the emulators directly and skip the Pocknix
launch settings (CPU pinning, RetroArch frame pacing). *Restore emulator default settings* in
Pocknix Tools also restores the Pocknix SRM parsers.

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

Pocknix sets each emulator up once, the first time it is installed. After that the settings are
yours: updates never change them. **Pocknix Tools** has a *Restore emulator default settings*
entry that puts one emulator, or all of them, back to the current Pocknix defaults, keeping your
old file as a `.bak-<date>` copy.

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
