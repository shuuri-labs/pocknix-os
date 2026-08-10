# pocknix-os

An Arch Linux ARM distro for **Retroid and AYN Snapdragon handhelds**. It runs Steam's native
ARM client and boots straight into gamescope-backed SteamOS mode, tuned for each device's
Qualcomm SoC.

Questions, bug reports, or just want to hang out? Join the [pocknix Discord](https://discord.gg/vcDtuNfmC).

> [!WARNING]
> pocknix-os is **experimental** software. Install and use it at your own risk. 

> [!WARNING]
> **SSH is enabled by default** and the default password (`pocknix`) is publicly known, so it is
> strongly recommended you change it: run `passwd` (and `sudo passwd root`) after first boot.

## About

pocknix-os turns these handhelds into devices that feel like a Steam Deck: power one on and
you land in Big Picture, pick a game, and play. Under the hood it is a real mutable Arch
system, so closer to something like **CachyOS than real SteamOS, Bazzite, or armada**. Nothing
is locked down or image-based:

- **Mutable.** The root filesystem is writable. Install anything you like with `pacman`.
- **Updates through pacman.** No image swaps or A/B reboots. `sudo pacman -Syu` and you are
  current. Shipping updates as packages rather than system images is deliberate: fixes and
  improvements land the moment they are ready, for speed of iteration in a niche this new.
- **Performance tuned per SoC.** A custom kernel with the `scx_lavd` scheduler for
  smooth, low-latency frame pacing, and core packages (the graphics stack and compositor)
  compiled for modern Snapdragon instruction sets rather than a generic ARM baseline.
- **Sleep and wake.** Suspend/resume works, but is still **experimental**.

Two sessions ship side by side: the **Steam** session (gamescope + native ARM64 Steam in Big
Picture) and a **Plasma Mobile desktop** session. The desktop uses **Plasma Mobile rather than
regular Plasma** on purpose: it is far more touch-friendly, with larger touch targets and
gesture navigation that might be preferable on such small screens.

> The default password for both the `root` and `deck` users is **pocknix**. If the device
> locks in desktop mode, tap the little keyboard icon to turn the on-screen numpad into a
> keyboard and type `pocknix` to log back in.

**Android apps via Waydroid.** pocknix-os includes Waydroid, so you can run Android apps,
including apps from the Google Play Store, right on the device. Download an APK and a handler
opens it, installs it, and adds a shortcut to Plasma Mobile, so the app behaves just like a
native one.

## Supported devices

| Device | SoC Family | Status |
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

## The kernel

pocknix-os builds a kernel per SoC family, based on the **ROCKNIX kernels** with tweaks
layered on top:

- **`scx_lavd` scheduler** for smoother, more consistent frame rates than the stock scheduler, as well as better power efficiency. 
- **Panel driver fixes** (e.g. locking the RP6 panel to a single stable 120Hz mode).
- **UHS-I SDR104 microSD support** ported from Armbian's downstream `sdhci-msm` driver, lifting
  microSD reads from ~13 MB/s to ~85 MB/s.
- **SteamOS microSD support** (`CONFIG_UNICODE` for casefolded cards) plus an automount stack,
  so cards formatted on a Steam Deck mount and show up in Steam.
- **Suspend/resume** work merged from the ROCKNIX suspend branch (experimental).

## How to install

Grab the image for your device from the [latest release](https://github.com/shuuri-labs/pocknix-os/releases/latest),
decompress it (`zstd -d`, or let your flasher handle it), and flash it to a microSD card
(Balena Etcher, `dd`, etc.). Then follow the steps for your SoC family below.

> **Minimum SD card size**: 64 GB works but gets tight fast once games are installed;
> 128 GB or larger is recommended.

### SM8550 (Retroid Pocket 6, AYN Odin 2 family)

The stock ABL cannot boot pocknix on these devices - the ROCKNIX ABL bootloader must be
flashed once first. If your device already runs ROCKNIX, skip to step 2. Otherwise the
flashed SD card carries ROCKNIX's install kit in its `rocknix_abl` folder (visible from
Android when the card is inserted):

1. **Flash the ROCKNIX ABL** (one-time, needs rooted Android). Copy the `rocknix_abl`
   folder from the SD card to the root of Android's internal storage, then as root run
   `backup_abl.sh` (saves your stock bootloader next to the scripts) followed by
   `flash_abl.sh`. **Copy the `abl_a.img`/`abl_b.img` backups somewhere safe off the
   device** - installing pocknix to internal storage later wipes Android's user data,
   backups included. `restore_backup_abl.sh` returns the device to fully stock.
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

## How to update

Updates ship through the pocknix pacman repo - kernel included, no reflashing. Three ways
to get them:

- **Pocknix Control (recommended)**: open the Quick Access Menu in game mode, go to the
  **Pocknix Control** plugin's **Updater** tab, and tap **Update** - checks for and
  applies updates without leaving game mode.
- **Pocknix Updater**: switch to desktop mode and launch the **Pocknix Updater** shortcut.
- **pacman**: run `sudo pacman -Syu` in a terminal, like any Arch system.

## Installing to internal storage

Running from the SD card works, but the OS and your games load much faster from internal
storage. Installing there requires resizing Android's `userdata` partition, which
**essentially factory-resets the Android side** (Android itself stays bootable, its user
data is wiped). Two ways, both from a system booted off the SD:

- **Pocknix Installer**: switch to desktop mode and launch the **Pocknix Installer** shortcut.
- **Terminal**: run `pocknix-install-internal` (do a `--dry-run` first and read the plan).

See [Install to internal storage](docs/install-to-internal.md) for the full walkthrough,
including how to uninstall and restore the space to Android.

## How to play games

### Picking a Proton

Download a game, then **set a compatibility tool for it**: open the game's
**Properties → Compatibility**, tick **"Force the use of a specific Steam Play compatibility
tool"** and pick **Proton-GE 11 (ARM64)** or **Proton-CachyOS 11 (ARM64)** — both ship with
pocknix and either is a good default; if a game misbehaves or runs poorly on one, try the
other. This is a per game setting, so repeat it for each title you install.

If a game misbehaves on both, try the other tools:

- **Proton 11 ARM**, Valve's own build: at times, it can be more bleeding edge and may offer
  better compatibility for some titles. Unlike the other two, it needs to be downloaded manually.
  Search for **"Proton 11 ARM"** in your Steam **Library**, download and install it, then
  force it per game the same way as the other two.
- **Proton Experimental (ARM64)**, Valve's rolling preview build: the newest fixes land here
  first, so it is worth a try when a game fails on everything else — but being a moving
  target, a Steam update can also change how it behaves. Download it manually like Proton 11
  ARM (search for **"Proton Experimental ARM64"** in your **Library**), then force it per
  game. Not available on the Retroid Pocket 5 / Flip 2 (see below).
- **The normal (x86) Protons** should "just work" too, but performance will be worse than
  the native ARM builds. Only reach for one when you cannot get a game to boot at all on an
  ARM Proton.

### On the Retroid Pocket 5 and Flip 2

The advice above applies unchanged, with one thing to know: the Snapdragon 865's GPU
driver does not yet support newer Proton builds. Recent DXVK (the DirectX layer inside
Proton) requires a GPU feature these devices do not provide yet, so any recent stock
GE/CachyOS release or Valve's **Proton Experimental (ARM64)** fails to start DirectX
games with "No adapters found". The GE and CachyOS builds pocknix ships on these devices
are current but carry a compatible DXVK on purpose, so they work — as do Valve's
**Proton 11 ARM** and the x86 Protons. Just avoid sideloading newer Proton builds and
expect Proton Experimental to stay broken here for now. Note that **Proton 11 ARM may
eventually stop working too**: when Valve updates it to the newer DXVK already found in
the Experimental builds, it will hit the same wall — the pocknix-shipped GE/CachyOS
tools and the x86 Protons will keep working regardless.

## Emulation

pocknix-os ships **ES-DE** (EmulationStation Desktop Edition) with a set of preconfigured
emulators. Drop your ROMs into `~/Emulation` and they show up ready to play, no per-emulator
setup needed.

**Star a game as a favorite in ES-DE and it appears in your Steam library**, so you can launch
it straight from Big Picture / game mode alongside your Steam titles.

See the [emulation docs](docs/emulation-setup.md) for where ROMs and BIOS files go, and how
to tweak per-emulator settings.

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

**Pocknix Control** is a Decky plugin in the Steam session (open the Quick Access menu): a
control panel for tuning the handheld and managing the system without leaving the couch.
Four tabs:

- **Games**: per-game (or global) tweaks - **FEX Preset** trades x86 translation accuracy
  for speed, **Audio Buffer** absorbs crackle in busy scenes. Also home to **Add Non-Steam
  Game**: Steam's own "Add a Non-Steam Game" dialog does not work on pocknix-os (Steam is an
  X11 app and Plasma Mobile cannot summon new windows for it), so Pocknix Control provides
  the feature natively in game mode instead.
- **Power**: fan curve (Quiet / Moderate / Performance) and CPU scheduler mode, applied live.
- **Storage**: format a microSD card for Steam, Deck-compatible, straight from game mode.
- **Updater**: check for and install system updates from the Quick Access menu.

See the [Pocknix Control docs](docs/pocknix-control.md) for the full tour.

## Known issues

- **The Steam session can take a while to come up**, especially right after a Steam client
  update. On first boot, or when entering game mode after a Steam update, you may be left
  staring at a black screen for a long while. Just be patient and leave the device to do its
  thing - it will come up. Better ways to show what is happening during these waits are
  being explored.
- **Controller support in desktop mode requires Steam to be running** - launch Steam from
  the desktop session to get controller input there. Even then, emulator controller
  mappings may not be correct in desktop mode.
- **On Snapdragon 8 Gen 2 devices** (Retroid Pocket 6, AYN Odin 2 family), **charging during
  sleep can freeze the device mid-sleep**. Prefer charging while the device is powered on, or
  fully powered off.
- **Gyro does not work yet.** The motion sensors are not wired up, so games and emulators
  that use gyro aim or tilt controls will not see any input. Getting them working is on the
  list.
- **MangoHud incurs a slight performance penalty.** It is fine for dialing in settings, but
  turn it off during real gameplay. I consider this a feature, not a bug. Instead of staring
  at performance metrics (we're all guilty), just enjoy your games! :)
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

## Contributing

Contributions are welcome, and emulator configs, testing on devices I do not own, and docs
fixes are especially useful. [CONTRIBUTING.md](CONTRIBUTING.md) covers where changes go, how
to build and test just the part you touched, what your testing should cover, and what a PR
needs to include (notably: steps I can follow to re-test it on my own device).

## Thanks and references

pocknix-os stands on the work of others:

- [**ROCKNIX**](https://github.com/ROCKNIX/distribution) - the kernels, drivers, and device
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

## License

pocknix-os is licensed [GPL-2.0-or-later](LICENSE.md). Vendored third-party components keep
their upstream licenses - see [docs/licensing.md](docs/licensing.md) for the breakdown.
