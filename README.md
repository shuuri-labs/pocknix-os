# pocknix-os

An Arch Linux ARM distro for the **Retroid Pocket 6**. It runs Steam's native ARM client and
boots straight into gamescope-backed SteamOS mode, tuned for the RP6's Qualcomm SM8550.

## About

pocknix-os turns the RP6 into a handheld that feels like a Steam Deck: power it on and you land
in Big Picture, pick a game, and play. Under the hood it is a real mutable Arch system, so
closer to something like **CachyOS than real SteamOS, Bazzite, or armada**. Nothing is locked
down or image-based:

- **Mutable.** The root filesystem is writable. Install anything you like with `pacman`.
- **Updates through pacman.** No image swaps or A/B reboots. `sudo pacman -Syu` and you are current.
- **Performance tuned for the SM8550.** A custom kernel with the `scx_lavd` scheduler for
  smooth, low-latency frame pacing, and core packages (the graphics stack and compositor)
  compiled for modern Snapdragon instruction sets rather than a generic ARM baseline.
- **Sleep and wake.** Suspend/resume works, but is still **experimental**.

Two sessions ship side by side: the **Steam** session (gamescope + native ARM64 Steam in Big
Picture) and a **Plasma Mobile desktop** session. The desktop uses **Plasma Mobile rather than
regular Plasma** on purpose: it is far more touch-friendly, with larger touch targets and
gesture navigation that might be preferable on such small screens.

**Android apps via Waydroid.** pocknix-os includes Waydroid, so you can run Android apps,
including apps from the Google Play Store, right on the device. Download an APK and a handler
opens it, installs it, and adds a shortcut to Plasma Mobile, so the app behaves just like a
native one.

## Supported devices

| Device | SoC Family | Status |
|---|---|---|
| Retroid Pocket 6 | SM8550 | ✅ Supported |
| Retroid Pocket 5 | SM8250 | ✅ Supported |
| Retroid Pocket Flip 2 | SM8250 | 🧪 Untested (should work - virtually identical to the RP5) |
| AYN Odin 2 | SM8550 | 🧪 Untested |
| AYN Odin 2 Portal | SM8550 | 🧪 Untested |
| AYN Odin 2 Mini | SM8550 | 🧪 Untested |
| AYN Odin 3 | SM8750 | 🚧 In progress |
| AYN Thor | SM8550 | 📋 Planned |

> **Why is the AYN Thor only "planned"?** The Thor is a dual-screen device, and pocknix gaming
> is built around gamescope, which is single-screen by design. Making the second screen useful
> means getting Plasma Mobile working in a dual-screen layout, plus controller support inside
> Plasma Mobile (outside of Steam), which is still being worked on. I also do not have a
> dual-screen device on hand to test against yet.

## The kernel

pocknix-os is based on the **ROCKNIX SM8550 kernel** with tweaks layered on top:

- **`scx_lavd` scheduler** for smoother, more consistent frame rates than the stock scheduler.
- **RP6 panel driver fixes** locking it to a single stable 120Hz mode.
- **UHS-I SDR104 microSD support** ported from Armbian's downstream `sdhci-msm` driver, lifting
  microSD reads from ~13 MB/s to ~85 MB/s.
- **SteamOS microSD support** (`CONFIG_UNICODE` for casefolded cards) plus an automount stack,
  so cards formatted on a Steam Deck mount and show up in Steam.
- **Suspend/resume** work merged from the ROCKNIX suspend branch (experimental).

## How to install

Grab the image for your device from the [latest release](https://github.com/shuuri-labs/pocknix-os/releases/latest),
decompress it (`zstd -d`, or let your flasher handle it), and flash it to a microSD card
(Balena Etcher, `dd`, etc.). Then follow the steps for your SoC family below.

### SM8550 (Retroid Pocket 6, AYN Odin 2 family)

1. **Install the ROCKNIX ABL bootloader** (follow ROCKNIX's instructions). The stock ABL
   cannot boot pocknix on these devices.
2. **Boot into ABL.** Hold **Volume -** while powering on or rebooting. Set your device and
   boot mode there.
3. **Insert the flashed microSD and boot.** pocknix-os comes up from the SD card.

> The internal ROCKNIX install boots first. To boot pocknix from SD you may need to uninstall
> ROCKNIX from internal storage. A **Pocknix Installer** app in the desktop session can install
> pocknix to internal storage and manage Android/ROCKNIX boot for you.

### SM8250 (Retroid Pocket 5, Retroid Pocket Flip 2)

**No ROCKNIX bootloader is needed** - the stock (factory) ABL boots pocknix directly via
UEFI GRUB. You only need to switch its boot mode away from Android:

1. **Boot into the stock ABL menu.** Hold **Volume -** while powering on or rebooting.
2. **Switch the boot mode from Android** to SD/alternative boot.
3. **Insert the flashed microSD and boot.** pocknix-os comes up from the SD card.

> Android stays untouched on internal storage; switch the boot mode back in the same menu
> to return to it.

## How to play games

1. In your Steam **Library**, search for **"Proton 11 ARM"**, then download and install it.
2. Download a game.
3. In the game's **Properties → Compatibility**, force it to use **Proton 11 ARM**.
4. Play.

x86 games run through FEX (x86-on-ARM translation) plus Proton, so many Windows titles "just work". Generally, performance should match or exceed PC emulation under Android through apps like Gamehub/Game Native. Compatibility (the amount of games that boot at all) is likely a little worse, but trust in Gabe - Valve and their contractors are working on it and things are improving rapidly. 

## Emulation

pocknix-os ships **ES-DE** (EmulationStation Desktop Edition) with a set of preconfigured
emulators. Drop your ROMs into `~/Emulation` and they show up ready to play, no per-emulator
setup needed.

**Star a game as a favorite in ES-DE and it appears in your Steam library**, so you can launch
it straight from Big Picture / game mode alongside your Steam titles.

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

**Pocknix Control** is a Decky plugin in the Steam session (open the Quick Access menu) for
tuning the handheld without leaving the couch.

**Performance**

- **Fan Curve**: Quiet, Moderate, or Performance. Applies live, no restart.
- **CPU Scheduler**: Autopilot (the `scx_lavd` default, adapts on the fly) or Performance.

**Per-game tweaks** (apply on the next game launch)

- **FEX Preset**: Default, Fast, or Compatible. Trades x86 translation accuracy for speed.
  Try Fast for more FPS, Compatible if a game misbehaves.
- **Audio Buffer**: Game default, 60, 90, or 120 ms. Raising the buffer absorbs crackle in
  busy scenes (an FEX audio-mixer quirk) at the cost of a little extra audio latency. 120 ms
  clears crackle and is inaudible in most games. Keep it low (or on Game default) for
  timing-sensitive titles where audio latency matters, such as rhythm games, fighting games,
  or anything where you play to the beat or need tight audio cues.

Settings can be global or set per game.

## Known issues

- **The Steam session can take a while to come up**, especially right after a Steam client
  update. Be patient - it will get there.
- **On Snapdragon 8 Gen 2 devices** (Retroid Pocket 6, AYN Odin 2 family), **charging during
  sleep can freeze the device mid-sleep**. Prefer charging while the device is powered on, or
  fully powered off.
- **Not all pre-baked emulator configs have been validated yet.** So far **Eden** (Switch),
  **ARMSX2** (PS2), and **RetroArch mGBA** (Game Boy Advance) are confirmed good; the rest
  ship with sensible defaults but have not been checked on device. More are being worked
  through, and community help is very welcome - if you dial in a config, please submit it.
  Note that some emulators may also need CPU core pinning (`taskset`) to perform well; if
  yours does, include the pinning in your submission.

## Building from source

pocknix-os builds a full image (kernel included) from this repo. The build needs an
**aarch64 Linux host with root** (it chroots); an Arch/Fedora VM on Apple Silicon or an
ARM cloud box both work. Quick start:

```bash
make check          # preflight (runs anywhere, no root)
sudo make kernel    # compile the kernel -> boot image
sudo make build     # bootstrap + packages + assemble the rootfs
sudo make sd-image  # flashable SD image -> build/image/<soc>/
```

`make help` lists every target. Kernel enablement is committed under `kernel/`; only stock
Linux source and firmware are fetched at build time.

## Thanks and references

pocknix-os stands on the work of others:

- [**ROCKNIX**](https://github.com/ROCKNIX/distribution) - the kernel, drivers, and RP6
  enablement pocknix builds on. This project simply would not exist without it.
- [**armada**](https://github.com/shuuri-labs/armada) - a sibling RP6 project (Fedora bootc),
  used as a reference for the session wiring and install-to-internal flow.
- [**thorch-os**](https://github.com/thorch-os/thorch) - the model for the self-contained,
  reproducible build harness this repo is shaped after.

And on the wider ecosystem pocknix ships on top of, with thanks to all who build it:

- [**Valve**](https://www.valvesoftware.com/) - Steam, gamescope, Proton, and the whole SteamOS
  handheld stack that makes this kind of device possible.
- [**FEX-Emu**](https://github.com/FEX-Emu/FEX) - the x86-on-ARM emulation that lets x86 games
  run at all.
- [**Mesa**](https://www.mesa3d.org/) and the **Turnip** driver - the open-source graphics stack
  driving the Adreno GPU.
- [**Arch Linux ARM**](https://archlinuxarm.org/) - the aarch64 base and package repositories.
- [**KDE**](https://kde.org/) and the **Plasma Mobile** team - the touch-friendly desktop
  session.
- The **Linux kernel**, **Armbian**, and the many upstream projects whose work this builds on.

## A note on AI

In the interest of transparency: I do use AI as a tool - debugging and performance work,
comparing against upstream, research, boilerplate, and drafting docs like this one. The
architecture and every design decision are mine, and nothing lands without me understanding
and verifying it. I would consider myself an "AI sceptic", however, I'll admit it's been a
real force multiplier for a lone developer working on this project.
