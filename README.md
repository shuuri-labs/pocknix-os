<h1 align="center">pocknix-os</h1>

<h3 align="center">Arch Linux for Snapdragon handhelds, with SteamOS gaming mode</h3>

<p align="center">Power on, land in Steam, pick a game, play. On a fully mutable, performance-tuned Arch base.</p>

<p align="center">
  <a href="LICENSE.md"><img alt="license: GPL-2.0-or-later" src="https://img.shields.io/badge/license-GPL--2.0--or--later-blue"></a>
  <a href="https://discord.gg/jEpwudj4Fx"><img alt="chat on Discord" src="https://img.shields.io/badge/chat-Discord-5865F2?logo=discord&logoColor=white"></a>
</p>

<p align="center">
  <a href="docs/install.md"><b>Install pocknix</b></a> ·
  <a href="docs/README.md"><b>Documentation</b></a> ·
  <a href="docs/known-issues.md"><b>Known issues</b></a>
</p>

> [!WARNING]
> pocknix-os is experimental software. Install it at your own risk.

## What you get

- **SteamOS gaming mode** on the Steam ARM client, with Proton picked for you.
- **Performance tuning that just works.** pocknix builds its own kernel, based on the [ROCKNIX](https://github.com/ROCKNIX/distribution) kernel, and tunes it, the CPU scheduler and the graphics stack for smooth frame times out of the box. All you do is set a frame cap.
- **A full, mutable Arch system underneath**: a touch-friendly desktop mode, Flatpak apps via Discover, and updates through `pacman`, no reflashing.
- **Locked by default, rolling if you want it.** Out of the box `pacman` points at our own tested snapshot of the Arch Linux ARM packages pocknix needs, so updates arrive together and stay stable, like SteamOS. Advanced users can switch to **rolling** mode, which points `pacman` at the full Arch Linux ARM repo and makes pocknix a true rolling Arch distro, with the occasional breakage that comes with it.

## Supported devices

| Device | SoC family | Status |
|---|---|---|
| Retroid Pocket Flip 2 | SM8250 | ✅ Supported |
| Retroid Pocket 5 | SM8250 | ✅ Supported |
| Retroid Pocket 6 | SM8550 | ✅ Supported |
| AYN Odin 2 | SM8550 | ✅ Supported |
| AYN Odin 2 Portal | SM8550 | ✅ Supported |
| AYN Odin 2 Mini | SM8550 | ✅ Supported |
| AYN Thor | SM8550 | 🧪 Beta |
| Retroid Pocket Nova | SM8550 | 🧪 Beta |
| AYN Odin 3 | SM8750 | 🚧 In progress |

## Get started

1. **Install**: flash the image for your device from the [latest release](https://github.com/shuuri-labs/pocknix-os/releases/latest) and follow the [install guide](docs/install.md).
2. **Play**: download a game, launch it, then open the Quick Access Menu → **Performance** and set a **Framerate Limit**. That's it.
   - *Optional*: if it doesn't feel smooth, try toggling the game's own vsync setting.
3. **Update**: Quick Access Menu → **Pocknix Control** → **Updater** → **Check for Updates** → **Install Updates**.

## Docs

- [Install guide](docs/install.md): flashing, the bootloader, first boot
- [Install to internal storage](docs/install-to-internal.md): faster loads, uninstalling, restoring the stock bootloader
- [Pocknix Control](docs/pocknix-control.md): per-game settings, fan curve, adding non-Steam games, updates
- [Emulation](docs/emulation-setup.md): ES-DE, supported systems, ROMs and BIOS
- [Android apps](docs/waydroid.md): Waydroid
- [Snapshots and rollback](docs/snapshots.md): recovering from a bad update
- [Known issues](docs/known-issues.md)
- [Contributing and building from source](CONTRIBUTING.md)

## Thanks

Built on [ROCKNIX](https://github.com/ROCKNIX/distribution), [Arch Linux ARM](https://archlinuxarm.org/), Valve's SteamOS stack, [FEX-Emu](https://github.com/FEX-Emu/FEX), [Mesa](https://www.mesa3d.org/) and [KDE Plasma Mobile](https://plasma-mobile.org/), with reference from [armada](https://github.com/armada-os/armada) and [thorch-os](https://github.com/thorch-os/thorch).

## License

[GPL-2.0-or-later](LICENSE.md). Third-party components keep their own licenses: see [docs/licensing.md](docs/licensing.md).
