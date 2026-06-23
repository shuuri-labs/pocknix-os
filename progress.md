# pocknix-os — progress & resume notes

Working notes for picking this back up after a break. For the *why* behind decisions, see
[`plan.md`](plan.md); for *how to run it*, see [`README.md`](README.md); for VM setup +
testing, see [`docs/testing-fedora-vm.md`](docs/testing-fedora-vm.md). This file tracks
**where things stand and what to do next**.

_Last updated: 2026-06-22 — Phase 4 STARTED: Plasma Mobile desktop session + game↔desktop switch scaffolded (untested)._

---

## ⬜→🔨 Roadmap started (2026-06-23): kernel pkg → install-to-internal → waydroid → steam-bake
Agreed order (each de-risks the next): **(1) package the kernel** [keystone: uniform `pacman -U`
deploy, atomic Image+modules, rollback, cheap kernel iteration for waydroid/DTS] → **(2) install.sh
to internal** [fast UFS iteration; ref ROCKNIX `installtointernal`/`update.sh` + armada; ABL/Android
untouched; `KERNEL.bak` rollback] → **(3) waydroid** [research the real missing kernel config —
binder/binderfs/ashmem etc., NO guessing] → **(4) steam bootstrap at build** [bake the client so
first boot needs no network; revisit the OOBE/setup-wizard, which we currently skip via a seeded
OOBE-complete `registry.vdf`]. Internal install is the priority (SD is slow).

### 🔨 (1) Kernel package — Phase 3a DONE in code (untested)
`linux-pocknix` is a **thin** package: it does NOT compile (Fedora host has no makepkg; `make kernel`
already compiles natively). `build-packages.sh` stages `build/kernel/out` into the package
(`./staged`); `package()` lays it out as `/boot/Image` + `/boot/dtbs` + `/usr/lib/modules/<ver>`,
`provides=linux`, `replaces/conflicts=linux-aarch64`, `.install` runs depmod. `install_local_packages`
now installs `pocknix/linux-pocknix` (deterministic `-Rdd linux-aarch64` then `-S`), and the old
hand-rolled `install_kernel()` is gone. `/flash/KERNEL` is still assembled from `build/image/KERNEL`
(make kernel) by build-sd-image — UNCHANGED for now.
**Phase 3b (with install.sh):** an alpm hook + shipped mkbootimg that rebuild `/flash/KERNEL` on
`pacman -U linux-pocknix` on the device (needs `/flash` mounted, which install.sh sets up).
**Test:** `make kernel && sudo make build && sudo make sd-image` — confirm `pacman -Q linux-pocknix`
in the rootfs, `uname -r` ↔ shipped modules match after boot.

Also this session: removed the **USB-C ssh gadget** (phantom "wired" conn; port is dual-role so it's
free for host-mode peripherals) and added the **deck XDG home dirs** + official Steam **icon**.

## ✅ Clean-flash validation (2026-06-23) — surfaced FIVE real bugs, all fixed on-device
First end-to-end `make build → make sd-image → flash` (everything before was hot-deployed onto a
hand-patched device, which hid these). After fixing all five, the full distro works from a clean
build: game mode (Steam + games), Plasma Mobile desktop + full app set, two-way session switching,
Wi-Fi, audio, CAP_SYS_NICE, and desktop-mode Steam/X11. (Device is still hand-patched with the fixes;
a final fresh flash is the only remaining confirmation — all fixes are committed/baked.)
Bugs 4-5 (channel pin, XWayland) below; 1-3 here:
1. **`pacman -S` repo selection** — local pkgs resolved to ALARM's copy because `[pocknix]` is
   appended last and `-S <name>` takes the first repo with the name (not highest version/epoch).
   Fixed by qualifying `pocknix/<name>` in `install_local_packages` (commit bbc1a96).
2. **Wi-Fi dead on clean flash** — config was all correct (backend=iwd, creds, firmware, regdom GB,
   AP scanned) but NM activation dead-ended: `need-auth (no-secrets)` → "No agents were available"
   → iwd aborted. **NetworkManager 1.56's iwd backend does NOT hand the keyfile PSK to iwd.** The
   old device only worked because of a leftover `/var/lib/iwd/<SSID>.psk` from the original
   iwd-direct phase. Fix: `firstboot_config` now ALSO writes `/var/lib/iwd/${SD_WIFI_SSID}.psk`
   (Passphrase) so iwd holds the credential and autoconnects; NM still reflects it for Steam. Plus a
   guard that fails the build if `SD_WIFI_SSID` is set but `SD_WIFI_PSK` is empty. See
   [[steam-network-nm-iwd]].
3. **First-boot network race** — the deck autologin runs `pocknix-steam` immediately, but Wi-Fi
   (iwd assoc + DHCP) takes ~15-30s, so `pocknix-steam-install`'s wget hit "Temporary failure in
   name resolution" and the supervisor loop fast-failed to a shell (its 3 retries are too fast to
   outlast bring-up). Fix: `pocknix-steam-install` `wait_for_network()` polls `getent hosts
   repo.steampowered.com` (up to ~180s) before downloading. (Proper long-term fix is still to bake
   the Steam client at BUILD time so first boot needs no network — PLANNED, see below.)
4. **Steam beta channel flip → game mode hang.** Launching Steam in *desktop* mode (plain
   `/usr/bin/steam`, no `-steamdeck`) flipped `package/beta` from `steamdeck_publicbeta` to
   `steamdeck_stable`; game mode then saw `installed version 0`, dead-ended on "Installing update"
   with steamwebhelper crash-looping, and hung across reboots. The native ARM Big-Picture client
   only works on `steamdeck_publicbeta`. Fix: both launchers re-assert
   `echo steamdeck_publicbeta > package/beta` on EVERY launch (commit 0466ad4). Recovery from a
   flipped state needed `rm -rf ~/.local/share/Steam ~/.steam` + re-bootstrap.
5. **Desktop-mode Steam: "Unable to open display".** The Plasma Mobile session runs kwin WITHOUT
   XWayland — kwin logged `/tmp/.X11-unix does not exist … Failed to establish X11 socket` and ran
   Wayland-only, so X11 Steam had no DISPLAY. gamescope creates that dir itself (game mode fine);
   kwin expects it to exist, and the minimal ALARM base has no xorg-server to ship the tmpfiles
   rule. Fix: pocknix-desktop ships `usr/lib/tmpfiles.d/pocknix-x11.conf`
   (`d /tmp/.X11-unix 1777 root root -`) so systemd-tmpfiles creates it at boot → kwin starts
   XWayland → all X11 apps (incl. desktop Steam) get a DISPLAY (commit e12d2dd).

## ⬜→🔨 Phase 4 STARTED — Plasma Mobile desktop session + session switch — 2026-06-22
First code for the Desktop half of the two-session model and the Game↔Desktop switch. Plan +
risks: [`docs/plasma-mobile-plan.md`](docs/plasma-mobile-plan.md). **All written, NONE tested on
hardware yet** — next is a VM build + on-device test, starting with the rotation crux.

**Entrypoint confirmed (not guessed):** the Plasma 6 mobile session is `/usr/bin/startplasmamobile`
(from `plasma-mobile` 6.7.0, in Arch `extra`/ALARM). It sets the phone/handset env + runs
`plasma-mobile-envmanager --apply-settings`, then execs `startplasma-wayland` (from
`plasma-workspace`) → kwin_wayland on the DRM backend + the mobile shell. It self-handles the D-Bus
session (`plasma-dbus-run-session-if-needed`), so no `dbus-run-session` wrapper is needed.

**New `packages/pocknix-desktop/`** (ships only the launcher/switch scripts; `depends=('bash')`).
The Plasma Mobile stack is installed into the rootfs from `config/packages/desktop.list`
(plasma-mobile/-workspace, kwin, plasma-nano/-nm, powerdevil, plasma-settings, kscreen) — NOT a
`depends()`, because that would drag the whole KDE/Qt tree into the build chroot at makepkg time
(this was the first build failure). **maliit-keyboard is AUR-only** (not in Arch/ALARM) → dropped;
needs its own pocknix package later (like gtk2/inputplumber). Scripts:
- `pocknix-desktop` — launcher, execs `startplasmamobile` as the deck PAM session (same autologin
  path as the game session).
- `pocknix-desktop-rotate` (+ `/etc/xdg/autostart` entry) — **the rotated-DSI crux.** gamescope
  rotates in a shader; kwin drives DRM directly so it needs a REAL output transform. Applies
  rotation+scale via `kscreen-doctor` *after* the session is up (kscreen needs the running daemon),
  autodetects the connected DSI output, overridable `POCKNIX_ROTATE`(left)/`POCKNIX_SCALE`(2)/
  `POCKNIX_OUTPUT`. **Highest risk — validate first; left/right axis differs from gamescope's.**
- `steamos-session-select` — the **real** switch (it was never implemented; the shim only ever
  shipped update/branch/bios stubs). Writes `$XDG_STATE_HOME/pocknix-session` then
  `systemctl --no-block restart getty@tty1` (deck∈wheel → `50-pocknix-deck.rules` grants polkit
  `systemd1.*` so no password; `--no-block` because the restart SIGTERMs our own session). This is
  what Steam's "Switch to Desktop" button invokes.
- `return-to-gamemode.desktop` — Plasma app-grid tile → `steamos-session-select gamescope`.

**Wiring:** `overlay/home/deck/.bash_profile` now reads the choice file (`gamescope`|`plasma`,
**default gamescope** — game mode unchanged) and execs the right launcher;
`build-image.sh install_local_packages` installs `pocknix-desktop` (+ build guard);
`config/packages/desktop.list` updated to the confirmed set (kept as docs — the package pulls it).

### ✅ Validated on hardware (2026-06-22, same session)
Built `pocknix-desktop`, hot-deployed to the device. **Plasma Mobile renders with correct
orientation** (`POCKNIX_ROTATE=left` was right first try — the rotate helper works). Session
switching works **in all paths**: the Plasma "Return to Game Mode" tile, Steam's built-in
gamepadui **"Switch to Desktop"** power-menu button, and manual.

**The switch mechanism: a SUPERVISOR LOOP, not getty-restart (the key fix).** Initial design had
`steamos-session-select` write a choice file + `systemctl restart getty@tty1`. That switched, but
**Steam→Plasma hung** — kwin came up (process alive, owned the DRM fd) but the panel stayed on the
console: `kwin_wayland: atomic commit failed: Permission denied` + `Failed to open …event11
(login1/session/_NN Unknown object)`. Root cause: restarting getty **churns the logind session** —
the old (gamescope) session is torn down as a new one is created, logind reuses session id "1", and
kwin inherits a **stale/closed** session → not `active` on seat0 → no DRM master. Cold boot worked
(one clean active session) which is what isolated it. Steam *did* call the script correctly
(confirmed by instrumenting: `args='plasma' uid=1001`), so the bug was the switch action, not the
invocation. `LIBSEAT_BACKEND=seatd` (kwin via seatd like gamescope) did NOT fix it — the problem was
session activeness, not the seat backend.

**Fix (`~deck/.bash_profile` is now a loop):** the bash login shell stays the session leader and
loops — launch the chosen session, and when its compositor exits, re-read the choice file and launch
the other — so **one long-lived logind session stays active on seat0** the whole time (every switch
now behaves like a cold boot → kwin always gets master). `steamos-session-select` just writes the
choice + `pkill -TERM gamescope/kwin_wayland`; the loop relaunches. **No getty restart, no polkit.**
The gamescope `drmModeRmFB failed` / xkbcomp spam on the console during a switch is just gamescope's
teardown noise — cosmetic. (`LIBSEAT_BACKEND=seatd` kept in the launcher; harmless, known-good.)

**Gotchas resolved on the way:**
- The choice-file `.bash_profile` ships via the image **overlay**, not a package — hot-deploying
  `pocknix-desktop` left the device on the OLD unconditional-`exec pocknix-steam` profile, so the
  switch silently relaunched Steam. Fixed by copying the new `.bash_profile` to the device (the
  clean flash bakes it). LESSON: overlay changes don't ride along with a `pacman -U` of a package.
- **Steam was unlaunchable in desktop mode** — the native ARM client is bootstrapped into
  `~deck/.local/share/Steam`, not a package, so no `steam` on PATH and game shortcuts
  (`steam steam://rungameid/...`) couldn't fire. Added `/usr/bin/steam` (desktop-mode launcher,
  no gamescope) + `steam.desktop` to `pocknix-steam` (pkgrel 3).
- **Switch to Plasma looked hung for ~30s** but wasn't: kwin+plasmashell came up fine (kwin owns
  `/dev/dri/card0`); the delay was **KSplash running its full 30s fallback** because Plasma Mobile
  never sends it the "ready" signal. Disabled via `/etc/xdg/ksplashrc` (`Theme=None`) in
  `pocknix-desktop`. Also generated `en_US.UTF-8` (build-image.sh `configure_locale`) — ALARM base
  was `C`-only, so every Qt/Plasma app warned + fell back to C.UTF-8.

**gamescope CAP_SYS_NICE (realtime priority) — + an AT_SECURE gotcha:** gamescope (built
`-Drt_cap=enabled`) logged `No CAP_SYS_NICE … Performance will be affected`. Granted it as a file
capability on `/usr/bin/gamescope` via a pacman `.install` scriptlet (`setcap cap_sys_nice+ep`;
`build-sd-image.sh` `rsync -aHAX` preserves the xattr into the image). **GOTCHA that broke game
mode:** a file capability puts the binary in glibc **secure-execution mode (AT_SECURE)**, and glibc
then **strips `LD_LIBRARY_PATH` out of the environment entirely**. `pocknix-steam` set
`LD_LIBRARY_PATH=…/steamrtarm64` on *gamescope's* env; the steam client (gamescope's child)
inherited the scrubbed env and `steamui.so` couldn't load its bundled `libvpx.so.6` →
`dlmopen … libvpx.so.6: cannot open shared object file` → client exits → supervisor loop fast-fails
to a shell. **Fix:** re-inject `LD_LIBRARY_PATH` via an INNER `env` on the client
(`gamescope … -- env LD_LIBRARY_PATH=… steam …`), set fresh for the non-secure client after
gamescope's env was scrubbed. gamescope doesn't need it (system libs). LESSON: never set
`LD_LIBRARY_PATH` on a setcap'd/AT_SECURE process's env if a child needs it — set it on the child.

**Added (this session):** Flatpak app store — `flatpak` + `discover` (desktop.list) +
`pocknix-flathub.service` (registers Flathub on first online boot). Discover is the native KDE
store; Bazaar (GTK) isn't in Arch → install it as a flatpak from Flathub.

**STILL OPEN / next:** (1) **on-screen keyboard** — `maliit-keyboard` is AUR-only; needs its own
pocknix package (Plasma's built-in virtualkeyboard is a stopgap). (2) cosmetic: `powerdevil` spams
"recently resumed from sleep" on session start (false clock-jump detection) — harmless. (3) bake it
all into a clean image (`make build` → `make sd-image`) and re-validate from a fresh flash. (4) fold
Proton/binfmt prep into the desktop `steam` launcher if x86 games misbehave when launched there.

---

## 🎉 MILESTONE: Steam LOGIN reached — native ARM Big Picture fully up on the RP6 — 2026-06-19
End-to-end: boot → tty1 autologin → `pocknix-steam` → gamescope → native ARM Steam gamepadui →
**OOBE cleared → logged in.** Final OOBE blocker after render was the Deck UI's OS-update step:
it shells out to `steamos-update`/`steamos-select-branch`/`jupiter-initial-firmware-update`, which
don't exist on our non-SteamOS base → `Updater apply error: 2`. Fixed by `packages/pocknix-steamos-shim`
(stubs reporting "no update"). KEY: Steam calls the OS-update helper by **full polkit-helper path**
`/usr/bin/steamos-polkit-helpers/steamos-update` (NOT via PATH) — shim must live there.
steamos-select-branch is PATH-resolved. Real OTA = deferred Phase 3c (see below).

### ⬜ Phase 3 polish punch-list (in-session, 2026-06-19) — Steam works, these are the rough edges
| Pri | Item | Notes / likely area |
|---|---|---|
| **HIGH** | **D-pad + X/Y** (in progress) | Fixed via `pocknix-bsp` capability_map `rp6-gamepad.yaml` (id rp6_gamepad, from armada's ayn_mcu which matches the RP6): d-pad = BTN_DPAD_* (present, evtest-confirmed), X/Y swap = BTN_NORTH↔BTN_WEST. Map loads fine. Target switched ds5→`deck` (Steam Deck pad), BUT the **`deck` target needs USB/IP `vhci-hcd`** — our kernel had `CONFIG_USBIP_CORE` off, so deck failed to create ("Failed to load vhci-hcd module") → Deck glyphs but NO input. **Enabled `CONFIG_USBIP_CORE=m`+`CONFIG_USBIP_VHCI_HCD=m` in kernel config** → deck works after a kernel rebuild. Immediate test: temporarily set target `ds5` (uhid, `CONFIG_UHID=y`) to validate the capability_map now. InputPlumber has NO uhid Deck target (deck-uhid doesn't exist), so vhci is required for the Steam-native pad. |
| **DEFERRED (kernel)** | **Back paddles + gyro** | NOT exposed to userspace (evtest event1-5 = nothing; `/sys/bus/iio/devices` empty). Paddles: RSInput driver (`CONFIG_JOYSTICK_RETROID`) emits no paddle codes — armada's map wires them to BTN_C/BTN_Z, so it's a driver/firmware-report gap (IF the RP6 even has paddles physically — confirm). Gyro: Odin2 IMU has no kernel driver bound (no IIO dev) — needs the IMU chip's driver + DTS node. Both = kernel/DTS work, not InputPlumber config. |
| **HIGH** | **No audio + volume buttons dead** ("no output devices detected") | PipeWire not exposing a sink to Steam in-session. UCM works standalone (speaker-test OK) but the session user's PipeWire/WirePlumber may not be running / wrong runtime dir; Steam reads sinks via PipeWire. Volume keys = InputPlumber/evdev → no sink to act on. |
| MED | gamescope refresh-rate limiting doesn't drive DRM (60 cap ≠ panel 60) | gamescope `GAMESCOPE_MODE_SAVE_FILE` / mode-switch path; our DRM backend may not be re-issuing the modeset. ROCKNIX uses `GAMESCOPE_MODE_SAVE_FILE=…/modes.cfg`. |
| **RESOLVED** (was "DEFERRED") | **mangoapp / perf overlay** | **The "coupling wall" was a MISDIAGNOSIS.** The overlay was blank because Steam's **Settings > In Game > Performance > "Show performance metrics in this game"** toggle was simply **OFF** — not a glfw/libdecor/version-coupling failure. With the toggle on, the simple first-attempt approach works: build/install `packages/mangohud` (provides `mangoapp`, pinned 0.8.3) + add `--mangoapp` to the gamescope launch (commit `a33dc96`). Reverted the launcher to exactly that — dropped the `MANGOHUD_CONFIGFILE` plumbing (`a86265c`) and the separate-launch/stats-FIFO model (`d7191e7`); they were both chasing a non-bug. The `libdecor "could not get required globals"` lines were noise, not the cause. LESSON: check the obvious user-facing toggle before diagnosing a deep stack-coupling issue. NB: the in-game MangoHud Vulkan layer (`MANGOHUD=1`) is arch-specific, so for x86/FEX games the gamescope `--mangoapp` overlay is the right arch-agnostic tool. |
| **DEFERRED** | **Volume rocker keys** | Slider works (Steam→PipeWire fine); the hardware Vol± keys show the OSD but don't change volume. On a real Deck the volume buttons are part of the **Deck controller HID** (Steam handles them); on the RP6 they're plain `KEY_VOLUMEUP/DOWN` on gpio-keys, so Steam shows the OSD but its volume-change (tied to Deck-controller volume) doesn't fire. NONE of armada/ROCKNIX/ChimeraOS ship a generic volume-key handler. Fix options: (a) feed the keys into the InputPlumber `deck` target as Deck volume buttons (native; needs deck/vhci kernel + InputPlumber volume capability), or (b) a small Vol±→`wpctl set-volume` user service (works on ds5 now). Deferred polish. |
| **DEFERRED (phase)** | **steamos-manager** | armada ships `armada-steamos-manager` = `com.steampowered.SteamOSManager1` D-Bus daemon (Python). Handles **TDP / GPU performance level / power / session mgmt** (NOT audio/volume/brightness — those go direct). This is the SteamOS-system-integration piece for per-game TDP, GPU clocks, fan, and likely refresh-rate behaviors. Its own phase, like FEX/OTA. armada ref: `system_files/usr/libexec/armada/steamos-manager` + the two `.service` units + dbus service files. |
| LOW | "dock update" prompt with no dock | `jupiter-initial-firmware-update` stub returns 0; make dock/firmware checks report "no update/none" so the UI stops nagging. |
| LOW | Phantom "wired network" in Steam net settings | NM exposes `usb0` (USB-gadget) or iwd's `/net/connman/iwd/0` p2p device. Mark usb0 `unmanaged` more fully or hide the p2p device. Cosmetic. |

### ⬜ PLANNED (decided 2026-06-21) — bake the Steam client at BUILD time → drop the first-boot Wi-Fi preseed
**Intention, not yet implemented.** Today `pocknix-steam` runs `pocknix-steam-install` on **first boot**
(`if [ ! -x "${CLIENT}" ]`), which downloads `steamrtarm64` from Valve's CDN → first boot needs network
→ which is *why* `build-sd-image.sh` has to pre-seed Wi-Fi creds. **Goal: no network needed on first
boot to reach Big Picture;** Wi-Fi becomes login/games-only, configured in-session (via the existing
NM+iwd path — see [[steam-network-nm-iwd]]).

**Reference — armada does exactly this (and needs no preseed):** `build_files/generate-steam-bootstrap.sh`
runs the *whole* bootstrap at build time in the aarch64 VM (which has network): downloads the ARM seed +
runtime, unzips into a staging `…/Steam`, then **runs Steam headless under Xvfb** (`steam -steamdeck
-exitsteam`) so it self-updates into a *complete* tree (`steamui.so` + a `.installed` manifest), strips
logs/tokens/caches, and ships that in the OS image. It even **fails the build if `.installed` is missing**
("the seed would re-install on first boot") — i.e. avoiding our exact situation is the point.

**Approach for pocknix (when we do it):**
1. Run `pocknix-steam-install`'s download + **Xvfb bootstrap** during the image build
   (`build-sd-image.sh`/`build-image.sh`), into a staging `HOME` in the VM — we already have both pieces.
2. **Keep the headless "run Steam once" step** — a bare seed unzip isn't a complete client; that run is
   what produces `steamui.so` + `.installed`, else it re-bootstraps (wants network) on first boot anyway.
3. **Copy the finished tree into the rootfs** at the session user's home — `/home/deck/.local/share/Steam`
   (owned `deck:deck`, per the non-root `deck` migration) + the `.steam/{root,steam,sdk*}` symlinks.
4. **Strip the seed clean** before baking (logs, `appcache/httpcache`, `config/htmlcache`, `ssfn*`,
   `registry.vdf`, `*.token`/`*.pid`) — mirror armada's cleanup block.
5. **Demote the launcher's `pocknix-steam-install` to a fallback** (only fires if the baked tree is absent).
6. Then **drop the Wi-Fi preseed requirement** from `build-sd-image.sh` (keep it optional).

**Trade-offs:** image grows by the client (~few hundred MB → bump `SD_SLACK_MIB`); baked client may be
slightly behind latest (self-updates on first online launch — harmless); VM build needs network (already
has it). **Sequencing:** do this together with the **non-root `deck` migration bake-in** (the tree must
land in `deck`'s home with correct ownership), which is still a manual on-device change today.

## 🎉 MILESTONE: Steam Big Picture RENDERS on the RP6 (native ARM, NO FEX) — 2026-06-19
`pocknix-steam` brings up **native ARM64 Steam gamepadui under gamescope on the panel.** The whole
gamepadui chain was a sequence of single missing native-ARM deps / config deltas vs armada — each
found by reading armada's real source + `ldd ... | grep 'not found'`, none needing FEX:

| Symptom | Cause | Fix |
|---|---|---|
| `CreateGlFont … failed` (missing fonts) | wrong client channel (plain `publicbeta`) | **`steamdeck_publicbeta`** channel (ships Big-Picture font payload) |
| `execl errno 2` (`steam_msg.sh`) | missing `~/.steam/root` | add **`.steam/root`** symlink |
| `Could not load module 'bin/vgui2_s.dll'` | `vgui2_s.so` DT_NEEDED `libopenal.so.1` unresolved (+ CWD) | dep **`openal`**; `cd steamrtarm64` (getcwd-relative module load) |
| steamwebhelper CEF crash (`Failed creating offscreen shared JS context`) | `steamwebhelper`/`libcef.so` DT_NEEDED `libcups.so.2` | dep **`libcups`** |
| `Failed to connect to websocket` (+ `lsof: command not found` spam) | Steam shells to `lsof` to find webhelper's CEF port | dep **`lsof`** |

Also matched armada's launch flags exactly: `-gamepadui -steamos3 -steampal -steamdeck -noverifyfiles`
(dropped ROCKNIX's `-nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders`). The
**native arm64 steamwebhelper EXISTS** (`steamrtarm64/steamwebhelper` is aarch64) and runs native —
**FEX is NOT needed for the client or the UI** (only later for x86 *game* content / Proton). Deps
now in `pocknix-steam` PKGBUILD: openal, libcups, lsof (+ gtk2, gdk-pixbuf2). Commits 474491b →
2229a5b → 948072b → 4e3dbdf → 4bb306a. `steam-native-arm-status.md` SUPERSEDED (its x86/FEX-runtime
hypothesis was wrong end to end).

**RESOLVED post-launch (2026-06-19):**
- **Setup-wizard Wi-Fi "no connections found"** → FIXED. Steam enumerates Wi-Fi via **NetworkManager
  over D-Bus**; we ran iwd-direct (NM disabled). Re-plumbed to **NM front-end + iwd backend**
  (`wifi.backend=iwd`, NM keyfile creds, iwd `EnableNetworkConfiguration=false`). Verified LIVE:
  `nmcli device status` → `wlan0 wifi connected`. Baked into `build-sd-image.sh`; static confs from
  `overlay/` (20-wifi-backend.conf + 10-unmanage-gadget.conf). See [[steam-network-nm-iwd]].
- **CJK fonts (tofu)** → `noto-fonts`/`-cjk`/`-emoji` deps.
- **Boot session** → `overlay/root/.bash_profile` execs `pocknix-steam` on tty1 autologin (real PAM
  session = XDG_RUNTIME_DIR + per-user PipeWire/audio); guarded to tty1+non-SSH; `touch /root/.no-steam`
  to boot to a shell. (Chose this over a systemd unit so Steam gets a user session for audio.)
- Benign noise (ignore): `steam-runtime-launcher-service not found` (present in tree, Steam disables
  it + continues), `steamrtarm32/*driverquery` (we only have arm64), `steamos-select-branch` /
  `lsb_release` / `steamos-polkit-helpers/*` (SteamOS-only helpers), `pipewire pw_context_connect`.

**STILL TODO:** (1) **rebuild `pocknix-steam` in the VM** so the new deps (openal/libcups/lsof/noto*/
networkmanager) are declared + pulled on a clean install/image (they were hand-`pacman -S`'d for
iteration). (2) On-device **validate the boot session** end-to-end (audio in-session, gamepad, seat
hand-off from getty). (3) First-boot **root-fs expand** service (64GB SD had 4.1G partition).

**OOBE / OS-update (2026-06-19):** the Deck UI (`-steamos3 -steamdeck`) shells out to
`steamos-update`/`steamos-select-branch`/`jupiter-biosupdate` for OS/BIOS updates; on our non-SteamOS
base those don't exist → OOBE "required update" dead-ends (`Updater apply error: 2`, `failed to query
current OS branch`). Fix = **`packages/pocknix-steamos-shim`** (stubs reporting "no update"; interface
mirrors **armada-update** — `check`→7, apply→0). registry.vdf OOBE-complete seed alone wasn't enough
on `steamdeck_publicbeta`. **Real OTA is a deferred phase** (Phase 3c): armada does it for real via
**Fedora bootc/rpm-ostree** atomic OTA (`armada-update` wired to bootc) — we'd need an atomic/A-B or
image-based update backend + a server hosting images; the shim is a drop-in placeholder (swap the
body, same Steam-facing contract). Preferred eventual OTA mechanism for the distro.

## ⬜→🔨 Phase 3b STARTED — FEX + Proton for x86 games — 2026-06-20
Native client/UI need NO FEX; **x86 games (Proton 11 ARM) DO** — Proton is NOT self-contained,
FEX is OS-level. Six pieces: FEX **with thunks** + **x86 rootfs** + **binfmt** + native-Vulkan
(Turnip) passthrough + **CachyOS Proton 11 arm64** + a per-game FEX-config shim. Full scoped plan +
ROCKNIX-vs-armada table: [`docs/fex-proton-plan.md`](docs/fex-proton-plan.md).

**Crux RESOLVED (the thunk build).** Option A (prebuilt ALARM/AUR/holo fex-with-thunks) is dead:
AUR has the ALARM no-x86-cross-toolchain blocker (FEX #1996); **holo-core-aarch64-preview ships no
fex at all** (swept 4,550 pkgs). We port **armada's no-nix recipe** (`virtudude/armada-packages/fex`):
it cross-compiles the x86 guest thunks with plain `clang -target x86_64/i686 --sysroot=<x86 dev
sysroot>` + `toolchain_x86_{32,64}.cmake`, dropping ROCKNIX's nix patch 0004. We assemble the dev
sysroot from **pinned Arch x86_64 + lib32 packages** (archive.archlinux.org) so it builds inside
`make packages`. Patches 0001/0002/0003/0005/**0006** (0006 fixes glibc≥2.41 SVE header leakage —
our Arch glibc is 2.43). FEX commit `a04b0241` (= ROCKNIX/armada).

**✅ Piece 1 BUILT (2026-06-21):** `fex-emu-2605.20260520.a04b0241-1-aarch64.pkg.tar.xz` in
`build/localrepo`. Three fixes got it compiling in the VM (all committed):
- **OOM** on `FEXCore/.../OpcodeDispatcher/Vector.cpp` — unbounded `ninja` (=nproc 8) × ~2-3 GB/TU
  blew the 7.7 GB VM (systemd-oomd reaped it). Fix: `ninja -j"${FEX_NINJA_JOBS:-2}"`.
- **System fmt v11 shadowed FEX's bundled fmt** — FEX does `find_package(fmt QUIET)` then falls back
  to `External/fmt` only if absent; Arch's v11 was found and its stricter `type_is_unformattable_for`
  rejected FEX's `join_view<std::byte*>` formats. Fix: drop fmt/xxhash/Catch2 makedepends +
  `CMAKE_DISABLE_FIND_PACKAGE_*` → FEX uses its pinned `External/*` (what armada/ROCKNIX get).
- **Re-downloaded sources every build** → persistent `SRCDEST=/build/srccache` in `build-packages.sh`.

**✅ Thunks VERIFIED (2026-06-21) — piece 1/6 DONE.** Package ships `usr/bin/FEX*` + `libFEXCore.so`,
`HostThunks{,_32}` + `GuestThunks{,_32}` **incl. `libvulkan-host`+`libvulkan-guest`** (the Turnip
passthrough path), `binfmt.d/FEX-x86{,_64}.conf`, plus `ThunksDB.json`, base `Config.json`,
`AppConfig/{client,steamwebhelper}.json`, an empty `RootFS/`, and the **`FEXRootFSFetcher`** tool.
(Minor: 32-bit GuestThunks omit vulkan/asound/drm — matches upstream; 32-bit Vulkan is niche.)

**🔨 Piece 2/6 SCAFFOLDED (2026-06-21):** `packages/fex-rootfs/` — pinned **ArchLinux x86_64 squashfs**
(`rootfs.fex-emu.gg/ArchLinux/2026-01-08/ArchLinux.sqsh`, immutable dated URL; FEX checks it with
xxh3_64 not sha256 → SKIP for now, pin sha256 after first VM download). Mirrors ROCKNIX (squashfs +
`squashfuse`, `RootFS="ArchLinux"`) + armada (bake the image in, `ThunksDB` all-on). package() ships
the `.sqsh` to `/usr/share/fex-emu/RootFS/ArchLinux.sqsh` (FEXServer FUSE-mounts it RO) and copies
ALARM's Turnip `libvulkan_freedreno.so` into `/usr/share/fex-emu/` for the Vulkan host-thunk
(ROCKNIX-style GPU passthrough).

**✅ Pieces 1+2 VALIDATED ON HARDWARE (2026-06-21):** `FEXBash -c 'uname -m'` → **`x86_64` + `NAME="Arch
Linux"`** on the RP6 — FEX translates x86 AND mounts the Arch rootfs. **Config gotcha fixed:** FEX
resolves a *bare* `RootFS` name against the per-user dir (`/root/.fex-emu/RootFS/`), which doesn't exist
→ empty RootFS path. Set `Config.json` `"RootFS"` to the **absolute** path
`/usr/share/fex-emu/RootFS/ArchLinux.sqsh` (env probe `FEX_ROOTFS=<abs> FEXBash` proved it). (Also note:
the first on-device fex-emu was stale — built before the RootFS key existed; rebuild to bake it in.)

## 🎉🎉 MILESTONE: x86 Windows GAME RUNS via Proton+FEX on the RP6 — 2026-06-22
**Gravity Circuit (x86 Win64) launched** through Proton 11 ARM + FEX + the Arch rootfs on the device.
Phase 3b proven end-to-end. The working recipe (mirrors ROCKNIX exactly — see
`vendor/rocknix-sm8550/reference/emulators/standalone/steam/scripts/`):
- **Proton + the two appids (both start with `4`):** Steam's **library** Proton 11 ARM, NOT CachyOS.
  - **`4628740`** = **Proton 11.0 (ARM64)** — the compat tool itself. Download it from the Steam library.
    It's **gated** (doesn't self-register as a selectable tool on a custom distro) → register a **custom
    `compatibilitytool.vdf`** in `compatibilitytools.d/` (display_name "Proton 11.0 (ARM64)"; symlink the
    Proton dist in, `install_path "."`).
  - **`4185400`** = **`SteamLinuxRuntime_4-arm64`** — the runtime Valve's Proton declares as
    `require_tool_appid` (the pressure-vessel container Proton would run *inside*). We installed it while
    debugging (`steamrtarm64/steam steam://install/4185400`, since a custom tool's `require_tool_appid`
    isn't auto-pulled) — **but it was a DEAD END: installing it did NOT fix the launch.** The real fix
    (below) strips `require_tool_appid` so Proton runs *without* the container, which means **`4185400` is
    not actually required** (ROCKNIX never installs it either). The launcher bake-in does **not** install
    it; a fresh reflash should run x86 games with `4185400` absent (worth confirming once on the next flash).
- **THE KEY UNLOCK:** **strip `require_tool_appid` from the Proton `toolmanifest.vdf`.** Valve's manifest
  makes Proton run *inside* the `SteamLinuxRuntime_4-arm64` **pressure-vessel container**, and Steam can't
  set that container up on pocknix → fails at `CreatingProcess` / `AppError_51` *before* Proton even runs
  (a wrapper on the runtime `_v2-entry-point` never fired = proof). ROCKNIX **replaces the toolmanifest
  with a `require_tool_appid`-free one** (`/usr/share/steam/toolmanifest.vdf`) so Proton runs **directly
  on the host, no container.** That's the whole fix.
- **binfmt:** ROCKNIX **DISABLES** the FEX binfmt during the Steam session (`echo 0 >
  /proc/sys/fs/binfmt_misc/FEX-x86{,_64}`), re-enabling on exit. The x86 Windows code goes Wine→FEX
  directly, not via Linux binfmt, so binfmt isn't needed and gets in the way of Steam's setup.
- **RootFS:** absolute path in `Config.json` (the bare-name gotcha above).

**⬜ NEXT — bake it permanent (currently all manual on-device, won't survive a Proton update/reflash):**
mirror ROCKNIX's `steam_arm64_binfmt_and_proton_prep` in `packages/pocknix-steam/pocknix-steam`:
on launch, `cp` a `require_tool_appid`-free `toolmanifest.vdf` into the Proton dir + disable `FEX-x86*`
binfmt; re-enable on exit. Ship the `compatibilitytool.vdf` + clean `toolmanifest.vdf` as package
resources, and add the runtime-install step. Then add `fex-emu`/`fex-rootfs` to the image. Also: verify
**Turnip GPU passthrough** is actually used (mangohud FPS) vs software render; check perf.
**GPU passthrough confirmed working on-device (2026-06-22).**

## ✅ Baked in (2026-06-22): non-root `deck` user, fan curve, FEX-binfmt-off service
After a reflash the image now sets these up so they survive (were all manual on-device before):
- **Non-root `deck` user (uid 1001)** in `build-sd-image.sh` — groups video/render/input/audio/seat/
  wheel; **tty1 autologin → deck**; `/home/deck/.bash_profile` boot-to-Steam; **PipeWire global-enabled**
  (`pipewire.socket`/`pipewire-pulse.socket`/`wireplumber`). **Fixes audio** — PipeWire is
  `ConditionUser=!root` so "no output devices detected" was just Steam-as-root with no PipeWire; bwrap/
  pressure-vessel (Proton) also prefer non-root. Polkit `overlay/etc/polkit-1/rules.d/50-pocknix-deck.rules`
  lets wheel (deck) do login1/NetworkManager/timedate1/systemd1/UDisks2 actions (suspend/reboot/Wi-Fi/
  timezone) without a password. Steam data now lives under `/home/deck/.local/share/Steam`.
- **RP6 fan curve** — `overlay/usr/local/bin/pocknix-fancontrol` + `pocknix-fancontrol.service`, ported
  from ROCKNIX `hardware/quirks/platforms/SM8550/{bin/fancontrol,005-thermal_path,020-fan_control}`:
  finds `hwmon*/pwm1` + cpu*/gpuss* thermal zones, drives the fan from the "moderate" temp→PWM curve
  (full at 85°C, off ≤55°C). The fan never spun because nothing took PWM control. Deployable to a live
  device without reflash (scp the script + unit + `systemctl enable --now`).
- **binfmt-needs-root, documented + solved:** `overlay/etc/systemd/system/pocknix-fex-binfmt-off.service`
  disables the FEX x86 binfmt at boot **as root**, because the `deck` session **can't write
  `/proc/sys/fs/binfmt_misc`**. The launcher's old in-session `echo 0 > …binfmt` step is removed (it
  would silently no-op as deck → Proton would break again). Leaving FEX binfmt on breaks Steam's Proton
  compat-tool setup; x86 game content goes Wine→FEX directly, not via Linux binfmt, so off is correct.

**Pieces 3–6:** (3) **binfmt** enable (systemd-binfmt → FEXInterpreter for x86/x86_64); (4) **CachyOS
Proton 11 arm64** → `compatibilitytools.d` (pin sha512); (5) per-game **FEX-config wrapper**; (6)
default compat + on-device validate (run an x86 title, confirm Turnip via the Vulkan thunk).

## Phase 3 — native ARM client journey (how we got to the milestone)
What's validated on-device (2026-06-19):
- **gamescope** (ROCKNIX-patched, `packages/gamescope`) drives the RP6 panel — `pocknix-steam`
  launches it with `--force-orientation left --use-rotation-shader`, fixed 1920x1080@120.
- **Native ARM64 Steam** downloads + runs as aarch64 (`packages/pocknix-steam`): the installer
  fetches the steamrt3c ARM64 runtime + the linuxarm64 client into `~/.local/share/Steam/steamrtarm64`.
- **steamui.so + all libs load** after fixes: built **gtk2** (`packages/gtk2`, EOL in Arch),
  `gdk-pixbuf2` from ALARM, **`steamrtarm64/` first on `LD_LIBRARY_PATH`** (bundled libvpx.so.6
  etc.), `seatd` for the seat.

**The `-gamepadui` fatals (`CreateGlFont failed` + `Could not load module 'bin/vgui2_s.dll'` +
`execl errno 2`) were NOT FEX/runtime problems.** Reading armada's ACTUAL source
(`gh api repos/virtudude/armada/contents/build_files/generate-steam-bootstrap.sh` +
`system_files/usr/libexec/armada/launch-steam`) — not the secondhand summary in
`steam-native-arm-status.md` — surfaced the real deltas (commit `474491b`):
- **Wrong client channel.** We pulled plain `publicbeta`; armada pulls **`steamdeck_publicbeta`**,
  which ships the Steam Deck Big-Picture UI payload (updater **fonts** + vgui assets). → fixes
  `CreateGlFont`. `package/beta` + manifest name now use `steamdeck_publicbeta`.
- **Wrong CWD.** Steam loads `bin/vgui2_s.dll` **relative to getcwd**. armada `cd`s into
  `steamrtarm64/`; we were `cd`-ing to `$HOME`. → fixes "Could not load module".
- **Missing `.steam/root` symlink.** Steam execs `$HOME/.steam/root/steam_msg.sh`. → fixes
  `execl errno 2`. (Also reverted a wrong-turn LDLP removal — armada keeps steamrtarm64 first.)
- Dropped the `registry.vdf`/OOBE seed I'd tried — armada deliberately *removes* registry.vdf
  from its seed, so it was an untested confound.

**NEXT: on-device test** (build in Fedora VM → scp pkg → `pacman -U` → `rm -rf ~/.local/share/Steam
~/.steam` to force re-pull from the new channel → `pocknix-steam-install` → `pocknix-steam`).
Verify `package/beta` == `steamdeck_publicbeta` and the `*.installed` manifest appears. If the
fonts/vgui fatals are gone, Steam is unblocked. `steam-native-arm-status.md` is now partly
SUPERSEDED (its "x86 runtime mis-selection" hypothesis was wrong — it was channel + CWD).
holo aarch64 repo: gamescope yes, steam no (client = Valve CDN). Packages:
gamescope, gtk2, inputplumber, pocknix-bsp, pocknix-steam.

Build-system note: `build-packages.sh` now wires a `[pocknix]` repo into the build chroot so
local packages can depend on each other; `make packages PKG="a b"` builds a subset.

## 🎉 MILESTONE: Steam-session compositor renders on the GPU (Phase 3)
`gamescope --backend drm --force-orientation left --use-rotation-shader -- vkcube` shows the
spinning cube **on the RP6 panel** (`right` rendered upside-down → use `left`). Full GPU stack
is up. Chain of fixes that got us here:

1. **GPU firmware** — `a740_sqe.fw` + `gmu_gen70200.bin` from `linux-firmware-qcom`. The kernel
   couldn't load it because the built-in `msm` driver probes **before the rootfs mounts** (no
   initramfs). Fix: build **`DRM_MSM=m`** (loads post-root via udev) — see build-kernel.sh.
   GMU firmware v4.1.9 loads; `/dev/dri/card0` + `renderD128` present.
2. **Vulkan** — `vulkaninfo` shows **`Turnip Adreno (TM) 740`** on ALARM mesa. Confirmed.
3. **gamescope** — vanilla (ALARM 3.16.24) **cannot** drive the RP6 panel: it's mounted rotated
   (DTS `rotation=<270>`) so gamescope sets a DRM **plane rotation** the `msm` DPU rejects →
   endless `Failed to prepare 1-layer flip (Invalid argument)` (upstream #1883/#819). Fix:
   **build ROCKNIX's patched gamescope** (`packages/gamescope`, commit `fe78bc6` + 4 patches);
   patch `0005` adds **`--use-rotation-shader`** (rotate in a compute shader, no plane-rotation
   property) → flip accepted. Build needed `makepkg -s` (chroot sudo), wlroots build-deps
   (xwayland, libdisplay-info, xcb-util-*), and a blanket **`-Wno-error`** (ALARM libs newer
   than the pinned wlroots' CI).

Seat: gamescope needs **seatd** running (`systemctl enable --now seatd`) — over SSH there's no
logind seat. DNS on-device fixed too (iwd → systemd-resolved).

Image wiring **DONE**: `install_local_packages` installs our epoch=1 gamescope; gamescope dropped
from steam.list; seatd enabled. Confirmed orientation: **`--force-orientation left`** (right is
upside-down). Next full `make build && make sd-image` bakes it all in.

---

## 🎉 MILESTONE: Phase 2a (controller) + 2b (audio) working
Tested on-device (verified by `make packages PKG=...` + on-device `pacman -U`).

**Phase 2a — InputPlumber: DONE.** `packages/inputplumber` (prebuilt aarch64 release v0.75.2,
same as ROCKNIX — no Rust build). `pocknix-bsp` ships `01-rsinput-rp6.yaml` (CompositeDevice
matching the RSInput gamepad `phys rsinput-gamepad/input0`, target ds5+keyboard; the RSInput
driver emits standard evdev codes so NO capability_map needed). On-device: a **virtual DualSense
appears** + inputplumber active. Enabled in the image. (Button-correctness gets a final check
once Steam runs; tweak `01-rsinput-rp6.yaml` if needed.)

**Phase 2b — Audio: working (one caveat).** The RP6 card reports as **`AYN-Odin2`** (DTS reuses
the Odin2 sound model). ALARM's alsa-ucm-conf has no matching UCM, so we ported ROCKNIX's
AYN-Odin2 UCM (`pocknix-bsp`: `AYN-Odin2.conf` + `HiFi.conf` + `conf.d/sm8550/AYN-Odin2.conf`).
**Speaker + headphone output both confirmed audible** via `alsaucm -c 0 set _verb HiFi` +
`speaker-test`. pipewire/pipewire-pulse/wireplumber enabled `--global` (WirePlumber auto-applies
the UCM). 
- **UCM-match gotcha:** `alsaucm -c AYNOdin2` fails `-2` (a bare id-string isn't opened as a
  card); `alsaucm -c 0` works — UCM matches `conf.d/sm8550/${CardLongName=AYN-Odin2}.conf`.
  PipeWire opens cards properly, so it matches.
- **KNOWN ISSUE (parked, hardware) — headphones are effectively mono.** Each amp works + carries
  the right channel individually (HPHR off → left plays; both on → right dominates), but each
  drives both ear cups. Codec routing verified correct + Class-H toggle didn't help → it's the
  **RP6 headphone analog path** (the card impersonates an AYN Odin2 but the HP wiring differs).
  Hardware/DTS follow-up, not a UCM fix. Speaker stereo is fine. Not a blocker.

**Phase 2c (deferred):** fan (ROCKNIX `0500-set-boot-fanspeed` — does the RP6 have one?),
CPU/GPU governors, thermal.

**Then finish Phase 3:** native ARM Steam client (`steamrtarm64`, provenance = open Q#4) +
`pocknix-steam` systemd session (gamescope launch from ROCKNIX `start_steam.sh`, minus ES/sway,
with `--force-orientation left --use-rotation-shader` + panel mode from DRM not swaymsg).

---

## 🎉 MILESTONE: kernel boots + runs on the RP6 (from SD), verified by diag
`pocknix-sd.img` boots on real hardware (`pocknix login`). The first-boot diag confirmed:
our 7.0.11 kernel (built root@fedora), `root=PARTLABEL=POCKNIX_ROOT` → `/dev/mmcblk0p2` ext4
(no initramfs), modules 7.0.11, gamepad `js0`, and **`mem_sleep: s2idle [deep]`** (deep
suspend available). Login root / `pocknix`.

Firmware finding (from diag): device firmware was missing → wifi (`ath12k board-2.bin`), audio
(`adsp/cdsp`), video (`vpu`) failed. ROCKNIX's synced overlay (`vendor/`) has those; we now
`install_firmware` them into the rootfs in build-sd-image.sh. GPU `a740_*` + `regulatory.db`
still missing (come from upstream `linux-firmware`/`wireless-regdb`) — follow-up; not needed
for boot. Benign noise: dummy regulators, `disp_cc` WARN, GPT alt-header (image < SD size,
`sgdisk -e` to fix). USB gadget needs a USB-C **data** cable (user lacks one) → using **Wi-Fi
pre-seed** (`SD_WIFI_SSID/PSK`) for SSH instead.

**DONE:** SSH over wifi works, and **deep suspend/resume verified on hardware** (`PM: suspend
entry (deep)` → ~3.5 s asleep → `PM: suspend exit`, SSH survived). The maintainer's TSENS
patch is confirmed active (`leaving TSENS uplow IRQ … as non-wakeup`). `pm_wakeup_irq=21`
(= `pmic_pwrkey`, power button).

**Known issue — spurious deep-sleep wake (battery, ~3.5s):** the `battery` wakeup source (in
debugfs `wakeup_sources` but NOT `/sys/class/wakeup/` → a **virtual** source via pmic_glink /
ADSP charger fw) wakes the SoC. `power/wakeup` is the WRONG knob — disabling it on all
power_supply class devices AND all device-backed `/sys/class/wakeup/` sources (except pwrkey)
did NOT stop it. The udev rule was removed (pocknix-bsp pkgrel 3). **A ROCKNIX tester
(MonsterRider) reports the fix is userspace via `standby-wake-filter`** (tsensors=kernel, done;
battery/charging/charger-detect/gpio=userspace). **Action: get the exact `standby-wake-filter`
path/command, then apply it in pocknix-bsp's sleep.d/pre hook.** Likely userspace, NOT kernel.
See `docs/sm8550-suspend-wake-report.md`. Not a distro blocker.

Wifi saga resolution (for the record): needed (1) device firmware overlay (ath12k board-2.bin
etc.), (2) regulatory **Country** set for 5 GHz (db present ≠ domain set), (3) provision **iwd
directly** (`/var/lib/iwd/<SSID>.psk`) not via NM, (4) **disable NM** so it doesn't hijack
iwd's netconfig — iwd does its own DHCP (`EnableNetworkConfiguration`). All in build-sd-image.sh.

Next: Phase 2 (pocknix-bsp: firmware/inputplumber/suspend hooks as a package), longer-soak
suspend testing (60 s+, multiple cycles, SDAM breadcrumb), then sessions. The kernel side
(Phase 1) is validated end-to-end on hardware.

## TL;DR — where we are

- **Phase 0 (build harness & skeleton): DONE + VERIFIED.** `make help`/`check`/`sync` work on
  macOS; **`sudo make build` verified end-to-end in a Fedora aarch64 VM** — ALARM bootstrap →
  keyring → full base package install (130 pkgs) completes cleanly. Linux-only targets guarded.
  - Fixes that testing flushed out (all pushed): chroot DNS on systemd-resolved hosts
    (`lib.sh chroot_resolv`), ALARM-only Phase 0 pacman.conf (holo/local deferred), and
    dropping `CheckSpace` (breaks chroot transactions with a bogus "not enough disk space").
  - Benign warnings during base build (ignore): mkinitcpio autodetect "failed to detect root
    filesystem" (chroot), microcode "aarch64 not supported" (x86-only hook), kms
    `drm_privacy_screen_register` symbol, missing vconsole.conf.
- **Phase 1 (kernel): COMPILES + pinned** — `make kernel` builds patched 7.0.11 reproducibly
  → `build/image/KERNEL` (qcom-abl) + modules. `KERNEL_SOURCE_SHA256` pinned.
- **First-boot milestone (in progress):** `make sd-image` builds a flashable SD image.
  **IMPORTANT device fact (verified):** the RP6 boots **internal ROCKNIX first and ignores the
  SD** while an internal install exists — even an official ROCKNIX SD won't boot over it. No
  SD-priority toggle exists; "Switch boot mode" only flips Android⇄ROCKNIX. To SD-boot you must
  ABL → **Uninstall ROCKNIX** first; restore later via official SD + `installtointernal`
  (SD-only, no PC/EDL). So SD testing is NOT "leave internal untouched" — but it's reversible.
  **Next: uninstall internal → boot official SD (confirm + capture layout) → flash + boot ours.**
- **Build host:** prefer an **aarch64 Linux** host (native, no qemu, native kernel compile).
  macOS can only do `sync`/`check`/editing — not the actual image build.

## The one-paragraph project recap

Self-contained Arch Linux ARM (aarch64) distro for the **Retroid Pocket 6 (SM8550)** with two
SteamOS-style switchable sessions: **Steam** (gamescope + native ARM64 Steam client, Big
Picture) and **Desktop** (Plasma Mobile on `kwin_wayland`). Kernel = the user's ROCKNIX SM8550
fork, vendored in and built here. Modeled on [thorch-os](https://github.com/thorch-os/thorch).

---

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | Build harness, repo skeleton, ALARM bootstrap, pacman wiring, `sync` | ✅ done |
| 1 | `build-kernel.sh` → qcom-abl `KERNEL` + modules; rootfs integration | ✅ compiles in VM; sha256 pinned; on-device boot pending |
| 1.5 | `build-sd-image.sh` → flashable SD boot-test image | ✅ BOOTS + WiFi/SSH + **deep suspend/resume verified on HW** |
| 2 | `pocknix-bsp` pkg (suspend sleep.d + SDAM + wakeup udev rule) ✅; firmware → rootfs build ✅; makepkg flow ✅ | ✅ core done; inputplumber/audio/thermal = polish (or Phase 3) |
| 3 | Steam session: gamescope (DRM) + native ARM steam, `pocknix-steam.service` | ⬜ |
| 4 | Desktop session: Plasma Mobile + `kwin_wayland`, `pocknix-desktop.service` | ⬜ |
| 5 | `pocknix-session-select` + boot default + in-session switch entries | ⬜ |
| 6 | Image assembly + internal-storage installer (ABL-preserving) | ⬜ |

---

## What works right now (verified on macOS)

- `make help` — target list.
- `make check` — preflight (correctly flags "image build needs Linux" on macOS).
- `make sync` — refreshes two destinations from the local `distribution/` ROCKNIX checkout:
  - **`kernel/` (COMMITTED, ~2.5 MB)** — the full RP6 kernel input set that ships in the repo:
    - `patches/` — **68 patches in ROCKNIX apply order**: `10-mainline/` (5 generic) →
      `20-sm8550/` (61 device: suspend/resume, RP6 panel, RSInput, TSENS) → `30-version/` (2).
    - `dts/qcom/qcs8550-retroidpocket-rp6.dts` (+ `.dtsi`s), `config/linux.aarch64.conf`.
    - `config/kernel-firmware.dat`, `bootloader/` packaging. See `kernel/README.md`.
  - **`vendor/` (GITIGNORED, build-time only)** — `reference/` copies of ROCKNIX steam
    launch scripts + quirks to adapt, and the 160 MB `filesystem/` firmware overlay (stock
    firmware actually comes from `linux-firmware` at build).
- Decision (resolved): kernel inputs are a **pinned snapshot of ROCKNIX `next` (nightly)** +
  jaewun's suspend branch + our small delta, **committed** in `kernel/` (self-contained +
  reproducible). We track **nightly (`next`), not stable**. The RP6 is officially supported
  by ROCKNIX, so most patches are public ROCKNIX work — our delta is just jaewun's suspend
  set + TSENS `0203` / `CONFIG_PM_SLEEP_DEBUG` / SDAM hooks. Stock Linux source = pinned
  tarball fetched in Phase 1; firmware = `linux-firmware`, not committed. Thorch auto-fetches
  nightly at build; we pin+commit instead. `make sync` advances the pin.

## Stubs left in place (grep `STUB` in scripts/)

- `scripts/build-image.sh` — kernel build, session/quirk install, image assembly.
- `scripts/build-image-fast.sh` — local pocknix package refresh.
- `scripts/install.sh` — entire internal-storage installer (Phase 6).
- `scripts/build-kernel.sh` — **does not exist yet**; `make kernel`/`make build` look for it.

---

## Phase 1 (kernel) — COMPILES in VM ✅ (pending sha256 pin + on-device boot)

Built end-to-end via `sudo make kernel`: patched 7.0.11 → `build/image/KERNEL` + modules.
Bug fixed along the way: SIGPIPE/exit-141 from `yes "" | make olddefconfig` (now plain
`olddefconfig`). To pin reproducibility: `sha256sum build/cache/linux-7.0.11.tar.xz` →
`KERNEL_SOURCE_SHA256` in `config/pocknix.conf`.

`scripts/build-kernel.sh` (run via `make kernel`) reproduces ROCKNIX's recipe and assembles
the qcom-abl boot image. `build-image.sh install_kernel()` integrates it into the rootfs.

What it does:
- Fetch stock kernel.org `linux-7.0.11` (pinned via `KERNEL_SOURCE_SHA256`), extract.
- Apply the committed stack **in order**: `kernel/patches/{10-mainline,20-sm8550,30-version}`.
- Copy `kernel/dts` into the tree and **ensure a `dtb-` Makefile entry** for each
  `qcs8550-*.dts` (no SM8550 patch registers them — may already be in stock 7.0.11).
- `.config` from `kernel/config/linux.aarch64.conf`, substituting `@DEVICENAME@`→RP6 and
  `@INITRAMFS_SOURCE@`→empty (**no embedded initramfs**), then `olddefconfig`.
- `make Image dtbs modules` (native gcc on aarch64; cross on x86).
- Boot image = `gzip(Image)` ++ all DTBs appended, **dummy ramdisk**, `mkbootimg` with
  ROCKNIX params (offsets 0, header v0, os 12.0.0) → `build/image/KERNEL`.
- `install_kernel()`: drop generic `linux-aarch64`, rsync modules → rootfs `/usr/lib/modules/`.

Key design call: **no initramfs.** UFS/SCSI/ext4 are built-in (`=y`), so the kernel mounts
the ext4 root directly. cmdline = `root=PARTLABEL=POCKNIX_ROOT rw` + ROCKNIX's SM8550 params
(replacing LibreELEC's `boot=/disk=LABEL=`). Dummy ramdisk mirrors ROCKNIX's known-good boot.

### To test in the Fedora aarch64 VM
```bash
sudo dnf install -y gcc make bc bison flex openssl-devel elfutils-libelf-devel \
                    perl python3 git xz gzip rsync diffutils
git pull
make kernel          # native compile; ~long. produces build/image/KERNEL + build/kernel/out
make check           # should now show kernel build <ver> + boot image KERNEL <size>
```

### Still open / to verify
- **On-device boot** (only testable on the RP6): does qcom-abl accept our cmdline + dummy
  ramdisk, and is `root=PARTLABEL=POCKNIX_ROOT` correct? PARTLABEL needs a GPT partition
  named `POCKNIX_ROOT` — finalized by the Phase 6 installer. Fallback if needed: real
  mkinitcpio ramdisk (assemble_bootimg accepts a ramdisk arg) or `root=/dev/sdaN`/PARTUUID.
- **Pin `KERNEL_SOURCE_SHA256`** in `config/pocknix.conf` once the 7.0.11 tarball is fetched.
- **Verify** (SM8550 README): `md5sum` built KERNEL vs deployed `/flash/KERNEL`; `uname -r`
  matches shipped modules; `cat /proc/version`.

---

## Open questions still pending (full list in plan.md)

1. **holo ↔ ALARM ABI split (highest risk):** holo `gamescope`/`steam` must link against ALARM
   `mesa`/`glibc`. Diff core package versions before first real `make build`. Fallback: build
   gamescope from source against ALARM mesa. *(Resolve early — gates Phase 3.)*
2. Kernel toolchain — mostly resolved (native on aarch64). Confirm mkbootimg/qcom-abl params.
3. DRM mode query without sway (RP6 panel res/refresh/rotation for gamescope args).
4. Native ARM Steam (`steamrtarm64`) provenance — exact holo package vs runtime download.
5. Internal partition layout — confirm RP6 ROCKNIX scheme; ext4 writable root vs squashfs.
6. Adreno 740 Vulkan on ALARM mesa (Turnip) — validate on-device.
7. Steam scope — native client only for v1; FEX/Proton deferred.

---

## Gotchas learned (don't rediscover these)

- **macOS rsync is ancient (2.6.9)** — it won't create nested destination parents. `sync.sh`
  pre-`mkdir`s them. If you add more rsync targets, do the same or it'll fail cryptically.
- **`A && B || C` traps:** a failing `B` runs `C`. Bit us once (rsync failures showed as
  "(missing)"). Prefer explicit `if` blocks in the scripts.
- The **build needs root** (chroot/mount) and **Linux**. Both are guarded in `lib.sh`
  (`need_root`, `need_linux`).
- Set **`DISTRIBUTION_DIR`** if your `distribution/` checkout isn't at `../distribution`.
- Set **`POCKNIX_ALARM_SHA256`** for reproducible builds; otherwise you get a warning and an
  unpinned "latest" ALARM tarball.

## Handy commands

```bash
make help                                   # targets
make check                                  # preflight (anywhere)
export DISTRIBUTION_DIR=$HOME/Documents/Coding/distribution
make sync                                   # refresh vendored ROCKNIX inputs
grep -rn STUB scripts/                      # what's left to implement
# on aarch64 Linux, as root:
sudo make build                             # bootstrap + base packages
```
