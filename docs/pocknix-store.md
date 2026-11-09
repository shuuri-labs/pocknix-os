# Pocknix Store

**Pocknix Store** installs and removes the optional parts of Pocknix with one tap: emulators,
extra Proton versions, VPNs, game streaming and Plasma Desktop. A fresh install leaves them out
so the system stays small; add only what you use.

It works the same in game mode and desktop mode, by touch or with the controller. In game mode,
open its tile in your Steam library (it is added the first time you sign in to Steam). In desktop
mode, it is in the app menu.

The store lists what the Pocknix package repository offers, so if it says there is nothing to
show yet, run a system update first (**Pocknix Tools** → **System**).

## Installing and removing

The pages on the left are the sections: **Emulation**, **Compatibility**, **Network**,
**Streaming** and **Desktop mode** (a section shows up once it has something in it). Tap an entry
to open it, then **Install** or **Remove**. A check in the corner of a tile means it is installed.

- **Every install runs a full system update first**, so it can take a while, and an install
  brings your whole system up to date with it. Everything is ready when it finishes: no restart
  or logout.
- Closing the store does not stop an install or a removal. Open it again to see the progress.
- Removing never takes anything another installed entry still needs.
- Some entries show a note when the install finishes, saying where to switch them on.

## What's in each section

- **Emulation**: ES-DE, Steam ROM Manager and the emulators. **Install all** installs the
  whole set and keeps it up to date together, including emulators added to Pocknix later. Or
  pick only the ones you want. Removing one emulator from an Install all set keeps the others.
  **Remove all** uninstalls the lot. Your ROMs, BIOS files, saves and settings always stay, so
  installing again picks up where you left off. Where to put your games:
  [emulation setup](emulation-setup.md).
- **Compatibility**: extra Proton versions, such as Proton-GE and Proton-CachyOS. Once
  installed, pick one per game in Steam (the game's **Properties** → **Compatibility**) or in
  [Pocknix Control](pocknix-control.md). Before removing one, move any game set to it to another
  Proton.
- **Network**: Tailscale and WireGuard. Sign in or import a tunnel in
  [Pocknix Tools](pocknix-tools.md#network) → **Network**.
- **Streaming**: Moonlight, to stream games from your PC.
- **Desktop mode**: Plasma Desktop, the full desktop, next to the Plasma Mobile one Pocknix ships
  with. Choose it in [Pocknix Tools](pocknix-tools.md#desktop) → **Desktop**. If desktop mode
  uses it, pick another desktop there before removing it.

## Steam tiles

After an install, the store offers to add a Steam library tile for each new entry that has one,
such as an emulator or Moonlight. Later, open an installed entry to switch its **Tile in the Steam
library** on or off, or use **Add Steam tiles** on the Emulation page for all of them. Removing an
entry removes its tile.

Steam must be signed in, and it cannot take tile changes while it is starting: if the store says
so, wait a moment or exit Steam, then try again. Updates never add a tile or bring back one you
deleted.

## Restore default settings

An installed emulator's page has **Restore default settings**: it puts back the Pocknix defaults
for that emulator from its next start. Your current settings file is kept as a `.bak` copy next
to the new one. Games, saves and controller profiles are not touched. For Steam ROM Manager this
restores the Pocknix parsers.

## From a terminal

```bash
pocknix-store status --json        # every entry and whether it is installed
sudo pocknix-store install <id>    # ids are in status --json (esde, srm, ppsspp, proton-ge...)
sudo pocknix-store remove <id>
sudo pocknix-store install-all     # emulation: Install all
sudo pocknix-store remove-all      # emulation: Remove all
pocknix-tiles enable <emulator>    # add a Steam tile, from a desktop terminal
```
