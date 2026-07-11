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

| Device | Status |
|---|---|
| Retroid Pocket 6 | ✅ Supported |
| Retroid Pocket 5 | 🚧 In progress |
| AYN Odin 2 | 🧪 Untested |
| AYN Odin 2 Portal | 🧪 Untested |
| AYN Odin 2 Mini | 🧪 Untested |
| AYN Odin 3 | 🚧 In progress |
| AYN Thor | 📋 Planned |

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

1. **Install the ROCKNIX ABL bootloader** on your RP6 (follow ROCKNIX's instructions).
2. **Boot into ABL.** Hold **Volume -** while powering on or rebooting. Set your device and
   boot mode there.
3. **Flash the pocknix-os image to a microSD card**, insert it, and boot. pocknix-os comes up
   from the SD card.

> The internal ROCKNIX install boots first. To boot pocknix from SD you may need to uninstall
> ROCKNIX from internal storage. A **Pocknix Installer** app in the desktop session can install
> pocknix to internal storage and manage Android/ROCKNIX boot for you.

## How to play games

1. In your Steam **Library**, search for **"Proton 11 ARM"**, then download and install it.
2. Download a game.
3. In the game's **Properties → Compatibility**, force it to use **Proton 11 ARM**.
4. Play.

x86 games run through FEX (x86-on-ARM translation) plus Proton, so most Windows titles work,
though not everything runs and performance varies by game.

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

## Building from source

pocknix-os builds a full image (kernel included) from this repo. See
[`docs/dev/building.md`](docs/dev/building.md) for host requirements, the aarch64-vs-x86_64 notes, and
`make` quick start. For the phased plan and rationale, see [`plan.md`](plan.md).

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

I am a software engineer with almost 10 years of experience. This project is **not
"vibe-coded"**: the architecture and final design decisions are mine, and I read, understand,
and verify what ships. In the interest of transparency, I do use AI as a tool for:

- **Performance tuning**: interpreting traces and benchmarks, reasoning about scheduler,
  frame-pacing, and kernel/driver knobs.
- **Bug finding and debugging**: chasing hard bugs (panel bring-up, suspend, audio xruns),
  forming and poking holes in hypotheses, reading logs and stack traces.
- **Comparing upstream to mine**: diffing upstream device trees, drivers, and configs against my
  own to spot changes and porting candidates.
- Research and rubber-ducking through unfamiliar subsystems and upstream code.
- Boilerplate, scaffolding, and repetitive edits; codebase search and log/diff summaries.
- Drafting docs like this README, plus reviews, typo-catching, and alternatives I then vet.

AI is a real force multiplier here, but it makes none of the engineering decisions, and nothing
lands without me understanding and verifying it.
