# Pocknix Tools

**Pocknix Tools** is the settings app for the things Steam doesn't manage: system updates and
rollback, the fan while charging, remote access, where your games live, which desktop desktop mode
starts, controller calibration, and the internal storage install.

It works the same in game mode and desktop mode, by touch or with the controller. In game mode,
open its tile in your Steam library (it is added the first time you sign in to Steam). In desktop
mode, it is in the app menu and on the Plasma Mobile dock.

| Page | What it does |
|---|---|
| System | Check for and install updates, roll back an update, fan while charging |
| Network | SSH, file sharing, Tailscale, WireGuard |
| Emulation | Choose your ROMs folder |
| Desktop | Choose the desktop that desktop mode starts |
| Controller | Check and calibrate the sticks and triggers |
| Advanced | Bootloader, install to internal storage, package base |

Anything that takes a while shows its progress in a log. Updates, rollbacks and the Advanced
steps keep running if you close Pocknix Tools (or Steam closes it); open it again to see where
they are.

## System

The top row shows the Pocknix version and the package base: **Locked** (the tested Pocknix
base, the normal case) or **Rolling** (see [Advanced](#advanced)).

- **Updates**: **Check** lists what is pending, then **Update now** installs it. Updates take
  a snapshot first. If the update brought a new kernel, Tools offers to restart.
- **Roll back an update**: every snapshot, newest first. Press and hold **Roll back** on one,
  then restart. Your games, saves and settings are never touched. Booted from the SD with Pocknix
  also on internal storage, an **Internal install** list does the same for the internal copy.
- **Fan while charging**: the slowest the fan runs while the device is plugged in, also while it
  sleeps and once the battery is full. **Low** is the default; **Off** leaves the fan to the
  temperature alone, so a device charging overnight stays silent.

How snapshots work, and what to do when the device won't boot at all:
[snapshots and rollback](snapshots.md).

## Network

- **Remote login (SSH)**: lets you log in as deck from another computer. It warns you first:
  Pocknix ships with a well-known default password, so change it before turning SSH on (`passwd`
  in a terminal, then `sudo passwd root`). Logging in as root over SSH is always off; use deck
  and `sudo`. SSH stays on after a restart until you turn it off.
- **File sharing (SMB)**: shares your home folder with computers on your network. The first time,
  it asks for deck's password, and you sign in to the share as deck with it. If you change deck's
  password later, turn sharing off and on again. How to connect from Windows, macOS or Linux:
  [copying files over the network](emulation-setup.md#copying-files-over-the-network).
- **Tailscale** (install it from the [Pocknix Store](pocknix-store.md), under Network): **Sign
  in** shows a QR code to scan with your phone, or a link to open on any device; the page updates
  once you have signed in. Tick **Use my own server (Headscale)** before signing in to use your
  own server. The switch turns the connection on and off; **Sign out** forgets the account.
- **WireGuard** (install it from the Pocknix Store, under Network): **Import .conf** adds a
  tunnel from your VPN provider or your own server. A new tunnel is added switched off and never
  connects on its own: switch it on here when you want it.

In game mode, the on-screen keyboard for a password or server address is **STEAM + X**.

## Emulation

**ROMs folder** is where ES-DE and the emulators look for your games, `~/Emulation/ROMs` unless
you change it. **Change** offers internal storage, each SD card, or the default folder, and lets
you browse to any folder on them. Close ES-DE and the emulators first.

Nothing is moved: copy your games into the new folder yourself (a folder is created for each
system). Tiles you made with Steam ROM Manager still point at the old folder, so open Steam ROM
Manager and add them again. More in [emulation setup](emulation-setup.md).

Until emulation is installed, the page says so and points you to the Pocknix Store (Emulation).

## Desktop

Lists the desktops you have installed and which one desktop mode starts. **Use** picks one for
the next time you enter desktop mode; in desktop mode, Tools offers to switch right away (that logs
you out, so save your work first).

Plasma Mobile comes with Pocknix. Plasma Desktop is in the Pocknix Store, under Desktop mode.
Other desktops, like GNOME or Hyprland, appear here too once installed (that needs rolling mode,
see [Advanced](#advanced)).

## Controller

Live readings for both sticks and triggers, **Calibrate**, and **Reset to Defaults**. Full
guide: [controller calibration](controller-calibration.md).

## Advanced

Steps that change the bootloader, the internal storage or where packages come from. Each one
asks you to press and hold before it starts, and keeps running if Tools closes.

- **Bootloader (ABL)**: shows whether the bootloader is up to date, and **Install** updates
  it. Keep the device plugged in.
- **Internal storage**: **Install** puts Pocknix on internal storage next to Android (the slider
  sets how much space Android keeps; Android is factory-reset), **Remove** gives the space back.
  Read [install to internal storage](install-to-internal.md) before either.
- **Package base**: **Locked** (recommended) gets every package from the tested Pocknix base.
  **Switch to rolling** moves to live Arch Linux ARM packages instead. That is unsupported: any
  Arch update can break the Steam session, graphics or booting until the next Pocknix release.
  **Return to locked** brings every base package back to the tested version.

## From a terminal

Every page is a front end for a command you can also run over SSH:

```bash
sudo pocknix-update --check                # what an update would install (System)
pocknix-update                             # install it (asks first)
pocknix-rollback --list                    # snapshots you can roll back to
pocknix-fan-mode charging                  # fan while charging, 0-255 (sudo pocknix-fan-mode charging 0)
pocknix-ssh status                         # SSH on or off (sudo pocknix-ssh on|off)
pocknix-share status                       # file sharing (sudo pocknix-share off)
pocknix-roms-init --where                  # the ROMs folder (pocknix-roms-init --roms <dir>)
pocknix-desktop-select list                # desktops; pocknix-desktop-select <name>
pocknix-gamepad-calibration status --json  # calibration state
sudo pocknix-update-abl                    # bootloader (Advanced)
pocknix-base status                        # locked or rolling
```
