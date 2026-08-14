# pocknix-os

> Questions, bug reports, or just want to hang out? Join the [pocknix Discord](https://discord.gg/vcDtuNfmC)!

**pocknix-os is an Arch Linux ARM (ALARM) based distro for Retroid and AYN Snapdragon handhelds.** Using the Steam ARM client, it turns these handhelds into devices that feel like a Steam Deck - power on, land in SteamOS gaming mode, pick a game, and play - but it does so on a fully mutable and performance-tuned Arch Linux base, so it's closer to something like CachyOS Handheld Edition than to real SteamOS, Bazzite, or armada.

Pocknix balances mutability and flexibility with stability and ease of operation. It runs on a fully mutable ALARM base, but by default enforces a **locked** mode: `pacman` is pointed at our own version-controlled mirror of ALARM's package repo, containing a snapshot of just the subset of packages Pocknix needs, plus our own custom packages - similar to SteamOS's model. Unlike SteamOS, though, advanced Linux users and developers can easily switch to **rolling** mode, which repoints the `pacman` conf at the full ALARM repo (for everything other than Pocknix's own packages) and turns Pocknix into a true rolling Arch distro.

As any Arch user knows, rolling updates can mean unexpected breakage, so staying in the default locked mode is the supported flow and recommended for most users. Extra applications can be installed via the included **Discover** Flatpak store.

> [!WARNING]
> pocknix-os is **experimental** software. Install and use it at your own risk.
>
> **The default password (`pocknix`) is publicly known**, so it is strongly recommended you change it: run `passwd` (and `sudo passwd root`) after first boot. From v0.3 onwards, SSH is disabled by default.

## Key features

- **Performance tuned.** Almost all of the graphics and display stack is recompiled with SoC-specific tuning, and Pocknix runs the ROCKNIX kernel with some key additions:
  - **The gaming-focused `scx_lavd` CPU scheduler**, enabled by default, for smooth, consistent frame pacing.
  - **UHS-I SDR104 microSD support** ported from Armbian's downstream `sdhci-msm` driver, lifting microSD reads from ~13 MB/s to ~85 MB/s on SM8550 devices.
- **Real sleep and wake.** Suspend/resume works, but is still **experimental on SM8550 devices**.
- **Plasma Mobile rather than regular Plasma**, for a touch-optimized desktop experience that suits these small screens better than Plasma Desktop. For those who want it, the ability to switch desktop mode to a full Plasma Desktop session will be added in a coming update.
- **Mutable.** The root filesystem is writeable, and advanced users can switch to rolling mode for a full rolling Arch experience.
- **Per-game performance settings**, including the ability to swap in different Turnip driver versions per game. Per-game configs can be exported as JSON files and shared with other Pocknix users.
- **Package-based updates for fast iteration.** SteamOS on ARM is still very young and iterating quickly. Pocknix is built with this in mind: rather than full images, updates are delivered through `pacman`, so components can be updated or swapped out at bleeding-edge cadence.

## Supported devices

| Device | SoC family | Status |
|---|---|---|
| Retroid Pocket Flip 2 | SM8250 | ✅ Supported |
| Retroid Pocket 5 | SM8250 | ✅ Supported |
| Retroid Pocket 6 | SM8550 | ✅ Supported |
| AYN Odin 2 | SM8550 | ✅ Supported |
| AYN Odin 2 Portal | SM8550 | ✅ Supported |
| AYN Odin 2 Mini | SM8550 | ✅ Supported |
| AYN Thor | SM8550 | 📋 Planned |
| Retroid Pocket Nova | SM8550 (QCS8550) | 📋 Planned |
| AYN Odin 3 | SM8750 | 📋 Planned |

## How to install

Grab the image for your device from the [latest release](https://github.com/shuuri-labs/pocknix-os/releases/latest), decompress it (`zstd -d`, 7-Zip, or let your flasher handle it), and flash it to a microSD card (Balena Etcher, `dd`, etc.). Then follow the steps below.

> **Minimum SD card size**: 64 GB works but gets tight fast once games are installed; 128 GB or larger is recommended.

The flashed SD card carries ROCKNIX's install kit in its `rocknix_abl` folder (visible from Android when the card is inserted). To install it:

1. Copy the `rocknix_abl` folder from the SD card to the root of Android's internal storage.
2. Open **Settings → Handheld Settings → Advanced → Run Script as Root**, navigate to the `rocknix_abl` folder you just copied, and run `backup_abl.sh` (saves your stock bootloader next to the scripts) followed by `flash_abl.sh`.
3. **(Optional, but recommended)** copy the `abl_a.img`/`abl_b.img` backups from inside the `rocknix_abl` folder to somewhere safe off the device - if you later install Pocknix to internal storage, the Android partition is factory-reset, ABL backups included.
4. Boot into the ABL menu: hold **Volume −** while powering on or rebooting. Set the boot mode to **Linux** and the boot source to **SD Card**. **SM8550 users must also set the device model to match their device**; SM8250 users can skip this.
5. Insert the flashed microSD and boot. pocknix-os comes up from the SD card.

> **Although installing the ROCKNIX ABL is recommended, SM8250 users can boot Pocknix without it**: flash a Pocknix SD, insert it, boot while holding **Volume −**, switch the boot mode, and boot.

## How to update

Updates ship through the Pocknix pacman repo - kernel included, no reflashing. Three ways to get them:

- **Pocknix Control (recommended)**: open the Quick Access Menu in game mode, go to the **Pocknix Control** plugin's **Updater** tab, and tap **Update** - checks for and applies updates without leaving game mode.
- **Pocknix Tools**: switch to desktop mode and launch the **Pocknix Tools** app, then select the update option.
- **pacman**: run `sudo pacman -Syu` in a terminal, like any Arch system.

Note that the Steam client updates independently - Steam will notify you when an update is available.

## Installing to internal storage

Running from the SD card works, but the OS and your games load much faster from internal storage. Installing there requires resizing Android's `userdata` partition, which **essentially factory-resets the Android side** (Android itself stays bootable; only user data is wiped). Two ways, both from a system booted off the SD:

- **Pocknix Installer**: switch to desktop mode and launch the **Pocknix Installer** shortcut.
- **Terminal**: run `pocknix-install-internal` (do a `--dry-run` first and read the plan).

See [Install to internal storage](docs/install-to-internal.md) for the full walkthrough, including how to uninstall and restore the space to Android.

## How to play games

### Picking a Proton

Download a game, then **set a compatibility tool for it**: open the game's **Properties → Compatibility**, tick **"Force the use of a specific Steam Play compatibility tool"**, and pick **Proton-GE 11 (ARM64)** or **Proton-CachyOS 11 (ARM64)** - both ship with Pocknix and either is a good default; if a game misbehaves or runs poorly on one, try the other. This is a per-game setting, so repeat it for each title you install.

If a game misbehaves on both, the normal (x86) Protons should "just work" too, but performance will be worse than the native ARM builds - only reach for one when you cannot get a game to boot at all on an ARM Proton. Note: only Proton 10 and below work on SM8250 devices - see the end of this section.

**SM8550 users have two additional ARM compat tools worth trying:**

- **Proton Experimental (ARM64)**, Valve's rolling preview build: the newest fixes land here first, but being a moving target, a Steam update can also change how it behaves. Given how new Proton for ARM is, though, it's often the best option for compatibility and performance.
- **Proton 11 (ARM64)**, Valve's stable ARM Proton build: may offer better compatibility or performance than GE or Cachy for some titles.

**Proton Experimental and Proton 11 (ARM64) are not available on SM8250 devices**: DXVK 3 depends on 8-bit storage, which Mesa (the GPU driver) does not support on Adreno a6xx GPUs. Our SM8250 builds of the GE and Cachy Protons are patched to replace DXVK 3 with DXVK 2.7, and Valve's (x86) Proton 10 and below ship older DXVK versions. Proton 11 (x86) may not work on SM8250 devices for the same reason.

## Emulation

pocknix-os ships **ES-DE** (EmulationStation Desktop Edition) with a set of preconfigured emulators. Drop your ROMs into `~/Emulation` and they show up ready to play, no per-emulator setup needed.

**Star a game as a favorite in ES-DE and it appears in your Steam library**, so you can launch it straight from Big Picture / game mode alongside your Steam titles.

See the [emulation docs](docs/emulation-setup.md) for where ROMs and BIOS files go, and how to tweak per-emulator settings.

Supported systems:

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
| Nintendo Switch | Eden |
| Sega Master System / Genesis / Game Gear / Sega CD | RetroArch (Genesis Plus GX) |
| Sega Saturn | RetroArch (YabaSanshiro) |
| Sega Dreamcast | RetroArch (Flycast) |
| PlayStation | RetroArch (DuckStation) |
| PlayStation 2 | ARMSX2 |
| PlayStation Portable | PPSSPP |
| Arcade / Neo Geo | RetroArch (FBNeo) |

## Pocknix Control

**Pocknix Control** is a Decky plugin in the Steam session (open the Quick Access Menu): a control panel for tuning the handheld and managing the system without leaving the couch. Six tabs:

- **Games**: per-game (or global) tweaks - **FEX Preset** trades x86 translation accuracy for speed, **Audio Buffer** absorbs crackle in busy scenes.
- **Add Non-Steam Game**: Steam's own "Add a Non-Steam Game" dialog does not work on pocknix-os (Steam is an X11 app and Plasma Mobile cannot summon new windows for it), so Pocknix Control provides the feature natively in game mode instead.
- **Power**: fan curve (Quiet / Moderate / Performance) and CPU scheduler mode, applied live.
- **LED Control**: adjust the stick RGB LED colours and brightness.
- **Storage**: format a microSD card for Steam, Deck-compatible, straight from game mode.
- **Updater**: check for and install system updates from the Quick Access Menu.

See the [Pocknix Control docs](docs/pocknix-control.md) for the full tour.


## Known issues

- **The Steam session can take a while to come up** - on first boot or after a Steam client update, entering game mode may leave you staring at a black screen for a *long* while, especially when running off an SD card. Be patient and leave the device to do its thing - it will come up. Better ways to show what is happening during these waits are being explored.
- **Controller support in desktop mode requires Steam to be running** - launch Steam from the desktop session to get controller input there. Even then, emulator controller mappings may not be correct in desktop mode. This is being worked on.
- **Gyro does not work yet.** The motion sensors are not wired up, so games and emulators that use gyro aim or tilt controls will not see any input. Getting them working is on the list.
- **MangoHud incurs a slight performance penalty.** It is fine for dialing in settings, but turn it off during real gameplay. I consider this a feature, not a bug - instead of staring at performance metrics (we're all guilty), just enjoy your games! 😃

## Building from source

pocknix-os builds a full image (kernel included) from this repo. The build needs an **aarch64 Linux host with root** (it chroots); an Arch/Fedora VM on Apple Silicon or an ARM cloud box both work. Quick start:

```bash
make check          # preflight (runs anywhere, no root)
sudo make kernel    # compile the kernel -> boot image
sudo make build     # bootstrap + packages + assemble the rootfs
sudo make sd-image  # flashable SD image -> build/image/<soc>/
```

`make help` lists every target. Kernel enablement is committed under `kernel/`; only stock Linux source and firmware are fetched at build time.

## Contributing

Contributions are welcome - emulator configs, testing on devices I do not own, and docs fixes are especially useful. [CONTRIBUTING.md](CONTRIBUTING.md) covers where changes go, how to build and test just the part you touched, what your testing should cover, and what a PR needs to include (notably: steps I can follow to re-test it on my own devices).

## Thanks and references

pocknix-os stands on the work of others:

- [**ROCKNIX**](https://github.com/ROCKNIX/distribution) - the kernels, drivers, and device enablement pocknix builds on. This project simply would not exist without it.
- [**armada**](https://github.com/shuuri-labs/armada) - a sibling RP6 project (Fedora bootc), used as a reference for the session wiring and install-to-internal flow.
- [**thorch-os**](https://github.com/thorch-os/thorch) - the model for the self-contained, reproducible build harness this repo is shaped after. The SM8550 suspend/resume patches are also lifted from here.

And on the wider ecosystem pocknix ships on top of, with thanks to all who build it:

- [**Valve**](https://www.valvesoftware.com/) - Steam, gamescope, Proton, and the whole SteamOS handheld stack that makes this kind of device possible.
- [**FEX-Emu**](https://github.com/FEX-Emu/FEX) - the x86-on-ARM emulation that lets x86 games run at all.
- [**Mesa**](https://www.mesa3d.org/) and the **Turnip** driver - the open-source graphics stack driving the Adreno GPU.
- [**Arch Linux ARM**](https://archlinuxarm.org/) - the aarch64 base and package repositories.
- [**KDE**](https://kde.org/) and the **Plasma Mobile** team - the touch-friendly desktop session.
- The **Linux kernel**, **Armbian**, and the many upstream projects whose work this builds on.

## A note on AI

In the interest of transparency: I do use AI as a tool - debugging and performance work, comparing against upstream, research, boilerplate, and drafting docs like this one. The architecture and every design decision are mine, and nothing lands without me understanding and verifying it. I would consider myself an "AI sceptic"; however, I'll admit it's been a real force multiplier for a lone developer working on this project.

## License

pocknix-os is licensed [GPL-2.0-or-later](LICENSE.md). Vendored third-party components keep their upstream licenses - see [docs/licensing.md](docs/licensing.md) for the breakdown.
