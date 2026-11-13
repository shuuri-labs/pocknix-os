# Pocknix Control

**Pocknix Control** is pocknix-os's built-in Decky plugin: a control panel inside the Steam
session for tuning the handheld and managing the system without leaving the couch (or touching
a terminal).

Open the **Quick Access menu** in the Steam session, then pick **Pocknix Control** under the
plug icon. The plugin is split into tabs (Stick Lights only on boards with stick LEDs) - switch
between them with **L1/R1** or by tapping the icons:

| Tab | What it does |
|---|---|
| 🎮 Games | Fan curve, CPU scheduler and game tweaks, globally or per game |
| 💡 Stick Lights | Stick light colour and brightness (boards with stick LEDs only) |
| ➕ Add Game | Add non-Steam games |
| 🔄 Updater | Check for and install system updates, roll back the last update |

Settings save automatically as you change them. Controller calibration is in Pocknix Tools: see
[controller-calibration.md](controller-calibration.md).

## Games

### Game tweaks

Tweaks can be set for every game (the **Default** entry in the **Game** dropdown) or per game.
Every installed Steam game is listed, and so are non-Steam shortcuts (marked `· non-Steam`), apart
from Pocknix Tools and the Pocknix Store, which are settings apps rather than games.
If you open the menu while a game is running, that game is preselected. To give one game its
own settings, select it and turn on **Use Per-Game Settings**; with it off, the game uses
**Default**. **Reset This Game**, at the bottom, clears a game's own settings again.

Three sections follow: **Performance**, **Game Tweaks** and **Advanced**. While a game is running,
each setting that reaches it says whether a change **applies now** or on the **next launch**. With
no game running, everything applies when a game starts, apart from the Default **Fan Curve** and
**CPU Scheduler**, which also run the device outside games. A game's settings are also reachable
from its library page: **Manage → Pocknix Settings**.

**Performance**

- **Fan Curve**: **Quiet**, **Moderate**, or **Performance**. Per game it can stay on **Default**
  (the dropdown shows which curve that is); a change reaches a game that is already running.
- **CPU Scheduler**: **Autopilot** (the `scx_lavd` default - adapts to load on the fly) or
  **Performance** (keeps the CPU aggressive at the cost of battery and heat). Per game it
  can stay on **Default**; a change reaches a game that is already running.

**Game Tweaks**

- **Proton Version** (per game only): the compatibility tool Steam launches the game with,
  the same setting as the game's **Properties → Compatibility**. Proton-GE and Proton-CachyOS
  show up in this list once you install them from the **Pocknix Store** (Compatibility). On
  **Steam default**, it names the version Steam picks for the game.
- **FEX Preset**: **Default**, **Fast**, or **Compatible**. Trades x86 translation accuracy
  for speed. Try **Fast** for more FPS; switch to **Compatible** if a game misbehaves
  (crashes, glitched physics, odd audio).
- **Mesa Version** (per game only): which Turnip (GPU driver) build the game runs on. The
  first entry is the system driver and the default. "git" is a recent snapshot of Mesa's
  development branch: newer fixes, less tested. Any drivers you added yourself come after it
  (see [Adding your own Turnip driver](#adding-your-own-turnip-driver)). Everything except the
  default works with ARM Proton versions only; an x86 Proton always uses its default driver.
- **Keep Images Compressed**: off by default. Keeps more of the game's images compressed in GPU
  memory, which can raise FPS when the game is limited by memory bandwidth. Works with ARM Proton
  and emulators on the system or "git" Mesa; an x86 Proton and your own drivers ignore it. Turn it
  off if colours look wrong (red and blue swapped, black or white overlays).
- **Audio Buffer**: **Game default**, **60**, **90**, or **120 ms**. Raising the buffer
  absorbs audio crackle in busy scenes (an FEX audio-mixer quirk) at the cost of a little
  extra audio latency. 120 ms clears crackle and is inaudible in most games. Keep it low (or
  on Game default) for timing-sensitive titles - rhythm games, fighting games, anything where
  you play to the beat or need tight audio cues.
- **Disable Touchscreen**: switches the touchscreen off while the game runs, so a thumb
  resting on the screen edge cannot fire stray taps. It comes back as soon as the game exits.
  While it is off, touch is off everywhere, the Steam overlay and on-screen keyboard included;
  use the controls there. It works for every game Steam launches, native and emulators included.
- **Disable Xalia**: on by default, which saves CPU in every game. Xalia lets a controller work
  menus built only for a mouse, so turn this off for a game like that when you can't tap the
  screen (for example, docked).

**Advanced**

- **Fastest Core First**: off by default. Games already run on the fast cores only; this makes
  the fastest one the game's first CPU, which helps games that do most of their work on
  one core. Hidden on boards where no core is faster than the rest. A CPU topology set in the game's
  launch options wins.
- **Environment Variables** (per game only): **Add Environment Variable** picks from common
  fixes:
  - **DirectX 12 feature level**: for DirectX 12 games that won't start or say your graphics card
    isn't supported. 12.1 fixes most.
  - **DirectX 12 shader model**: lower it if a DirectX 12 game crashes or shows broken graphics.
  - **Write a Proton log**: saves `steam-<game id>.log` in your home folder. Remove it when you're
    done, as logging slows the game down.

  **Remove** takes one off. Variables saved on **Default** by an older version still apply to every
  game and show there with a **Remove** button. For anything not in the list, use the game's
  [launch options](steam-games.md#launch-options), which win over both.

### Adding your own Turnip driver

You can try a community Turnip build on one game without replacing the system driver:

1. Download a **Linux** build for aarch64 (glibc). Android builds made for Winlator or
   emulator apps (most "Turnip" zips, for example TurnipZ) can't load on Pocknix and won't be
   listed.
2. Make a folder for it in `~/.local/share/pocknix/turnip/`, for example
   `~/.local/share/pocknix/turnip/my-turnip/`, and unzip it there. The folder must contain
   `libvulkan_freedreno.so`; a `meta.json` next to it with a `"name"` field sets the name shown
   in the list.
3. Reopen the game's tweaks: the driver shows up under **Mesa Version** as
   its name followed by "(ARM only)". Pick it for the game.

If the game then fails to start or shows no picture, set Mesa Version back to the default.
Deleting the folder removes the driver; a game still set to it falls back to the default.

## Stick Lights

Boards with stick LEDs get this tab. **Enable**, **Link Left & Right** to give both sticks one
colour, **Side Lights** to match the side lighting to the sticks, then colour and brightness per
stick.

## Add Game

Steam's own **Add a Non-Steam Game** dialog does not work on pocknix-os, so add them here:

1. In the **Add Game** tab, press **Add Non-Steam Game**.
2. A file picker opens in your home directory. Navigate to the executable you want
   (a Linux binary, script, or Windows `.exe`) and select it.
3. Give it a name, and choose whether to **Launch with Proton**. This switches on
   automatically for `.exe` files - Windows programs need it, native Linux ones do not.
4. Press **Add to Library**. The game appears in your Steam library right away, and also
   shows up in the **Games** tab's **Game** dropdown so you can give it its own settings.

## Updater

System updates, without leaving game mode:

1. **Check for Updates** lists everything pending (kernel included - updates ship through
   the pocknix pacman repo, so no reflashing).
2. **Install Updates** downloads and installs the lot. Keep the device powered; a running
   game may stutter while it installs.
3. Restart when it finishes to apply everything (**Restart Now** appears right there).

The update keeps running even if you close the Quick Access menu - reopen the tab to check
on progress. If you prefer, the same update is just `sudo pacman -Syu` in a terminal, or
**Pocknix Tools** → **System** → **Update now**.

If the tab says **OpenABL needed**, install the OpenABL bootloader from **Pocknix Tools** →
**Advanced** → **Bootloader** first: future updates won't install without it.

### Rolling back an update

Every update takes a snapshot first. If one breaks something, press **Roll Back Last Update**,
confirm, and **Reboot Now**: the system comes back as it was before the update, and your games,
saves and settings are untouched. To go back further, or when game mode itself is broken, see
[snapshots and rollback](snapshots.md).
