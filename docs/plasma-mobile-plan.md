# Plan: Plasma Mobile desktop session + session switching (pocknix-os)

Status: **Phase 1 scaffolded + Phase 2 skeleton in place (2026-06-22); UNTESTED on hardware.**
Game mode is done. The desktop half + the Game ↔ Desktop switch now exist as code (see "Progress"
below); the next step is a VM build + on-device test of the rotation crux.

## Progress (2026-06-22) — what's built

`packages/pocknix-desktop/` created (mirrors `pocknix-steam`, pulls the Plasma Mobile stack as deps):
- **`pocknix-desktop`** — launcher; execs `startplasmamobile` (the confirmed Plasma 6 entrypoint:
  sets phone/handset env + runs `plasma-mobile-envmanager`, then execs `startplasma-wayland` →
  kwin_wayland on the DRM backend + the mobile shell; self-handles the D-Bus session).
- **`pocknix-desktop-rotate`** + `…-rotate.desktop` (xdg-autostart) — applies the panel
  rotation+scale via `kscreen-doctor` **after** the session is up (kscreen needs the running
  daemon). Autodetects the connected DSI output; overridable via `POCKNIX_ROTATE/SCALE/OUTPUT`.
  **This is the rotated-DSI crux (risk #1) and is the thing to validate first on hardware.**
- **`steamos-session-select`** — the REAL switch (was never implemented): writes the choice file +
  `systemctl --no-block restart getty@tty1` (deck is wheel → polkit `systemd1.*` = no password).
- **`return-to-gamemode.desktop`** — Plasma app-grid tile → `steamos-session-select gamescope`.

Wiring:
- `overlay/home/deck/.bash_profile` now reads `$XDG_STATE_HOME/pocknix-session` (`gamescope`|`plasma`,
  **default gamescope** — game mode unchanged) and execs the matching launcher.
- `scripts/build-image.sh install_local_packages` installs `pocknix-desktop` (+ build guard).
- `config/packages/desktop.list` updated to the confirmed set (kept as docs; the package pulls it).

**To test (VM build → device):**
```
make packages PKG=pocknix-desktop      # then sudo make build && sudo make sd-image, OR hot-deploy:
scp build/localrepo/pocknix-desktop-*.pkg.tar.* root@<rp6>:/tmp/ && pacman -U /tmp/pocknix-desktop-*
# pull the Plasma stack too if not in the image: pacman -S plasma-mobile plasma-workspace kwin \
#   plasma-nano plasma-nm powerdevil plasma-settings maliit-keyboard kscreen
steamos-session-select desktop         # (as deck) → restarts getty → boots Plasma Mobile
# check orientation; if upside-down/sideways: POCKNIX_ROTATE=right (or DSI output name) and re-test
steamos-session-select gamescope       # switch back
```

---

### Original plan below (kept for reference)

> Scope: **pocknix-os only**. A parallel armada fork also targets Plasma Mobile (see that repo's
> `PLAN.md`), but its switch plumbing is SDDM-based and does **not** port here — read the
> "Architecture" section before reusing anything from it.

---

## Architecture you're building on (orient here first)

pocknix-os boots straight into Steam game mode via a **tty autologin**, not a display manager:

- `overlay/etc/systemd/system/getty@tty1.service.d/autologin.conf` → `agetty --autologin deck`
- `overlay/home/deck/.bash_profile` → on tty1, non-SSH → `exec pocknix-steam`
- `packages/pocknix-steam/pocknix-steam` → launches `gamescope … -e -- steam -gamepadui …`
- The session runs as the **non-root `deck` user** (uid 1001) — required for PipeWire audio, Steam
  Input/uinput, etc. (every "worked as root, broke as deck" gap is now fixed; see `progress.md`).
- `packages/pocknix-steamos-shim/` stubs `steamos-*` commands (update/branch/BIOS, and likely
  `steamos-session-select`) so the gamepadui OOBE doesn't dead-end. **This is the switch hook.**

**Implication:** there is no SDDM / `os-session-select` / `session-control` to reuse. The switch is
built around the autologin + `.bash_profile` model: a *session-choice file* the `.bash_profile`
reads, and a `steamos-session-select` that rewrites it and restarts the session.

**Display rotation difference (critical):** the RP6 panel is portrait (1080×1920) mounted rotated.
gamescope handles this with `--use-rotation-shader --force-orientation left` (a shader, no DRM
transform). **kwin_wayland drives DRM directly**, so Plasma Mobile needs a *real* output transform
(kscreen rotation) — this is the single biggest unknown.

Plasma Mobile runs on **kwin_wayland**, not Sway (locked decision — see the `plasma-mobile-compositor`
memory).

### Build/deploy workflow (same as game mode)
- Build in the Fedora aarch64 VM. `make packages PKG=<x>` builds one package into `build/localrepo`;
  `make build` bootstraps the rootfs + builds/installs **all** packages; `make sd-image` images the
  existing `build/rootfs` + runs `firstboot_config`.
- **Remember the trap:** `make sd-image` only images what `make build` last installed. New packages
  must be added to `install_local_packages` in `scripts/build-image.sh` (guarded there) and pulled in
  by a `make build` — or hot-deployed to a live device with `scp` + `pacman -U`.
- Device deploy for iteration: `scp build/localrepo/<pkg>… root@<ip>:/tmp/` + `pacman -U`.

---

## Phase 0 — Recon (cheap, do first)
- Confirm `plasma-mobile`, `plasma-nano`, `plasma-workspace`, `plasma-settings`, `maliit-keyboard`,
  `kwin` exist in **ALARM aarch64** (Arch ARM mirrors Arch repos, so probably yes). Anything missing
  becomes a pocknix package (same pattern as gamescope/mangohud).
- Decide package delivery: a `pocknix-plasma` meta-package vs additions to `config/packages/base.list`.
- Confirm boot default stays **game mode** (gamescope); desktop is opt-in via the switch.

## Phase 1 — Plasma Mobile session standalone (get it rendering)
1. **Package set** — pull the mobile stack (meta-package or base.list). Runs on kwin_wayland.
2. **Launcher** — new `pocknix-desktop` script (mirror `packages/pocknix-steam/pocknix-steam`):
   exports `XDG_*`, execs the Plasma Mobile wayland session (`startplasma-mobilewayland` / the
   `org.kde.plasma.mobile` session — confirm the exact Plasma 6 entrypoint) as `deck`.
3. **Display config — the crux.** kwin needs a real output transform, unlike gamescope's shader:
   - `kscreen-doctor output.DSI-1.rotation.left` (rotate the portrait DSI panel to landscape)
   - scale ~2.0 for the 6″ 1080×1920
   - do this in a first-run bootstrap (mirror the idea of armada's `desktop-bootstrap`).
   - **Fallback if kscreen can't transform DSI cleanly:** a kwin output-config file.
4. **Input** — touch (`ft5x06`) is native wayland; Maliit on-screen keyboard; gamepad via
   InputPlumber as pointer/keyboard for nav; volume keys already handled by `pocknix-volumed`.
5. **Test gate** — temporarily point `overlay/home/deck/.bash_profile` at `pocknix-desktop`
   → boots into Plasma Mobile, correct orientation + scale, touch + OSK work. (Revert after.)

## Phase 2 — Session switching
1. **Choice file** — e.g. `~deck/.local/state/pocknix-session` holding `gamescope` | `plasma`
   (default `gamescope`). `.bash_profile` reads it → execs `pocknix-steam` or `pocknix-desktop`.
2. **`steamos-session-select`** — replace the `pocknix-steamos-shim` stub with a real implementation:
   write the choice + terminate the current session so getty respawns `deck` and `.bash_profile`
   picks the new one. This is exactly what Steam's **"Switch to Desktop"** invokes.
3. **"Return to Game Mode"** — a Plasma app-grid `.desktop` tile running
   `steamos-session-select gamescope`.
4. **Robustness** — bare `exec` + getty-respawn switching can be fragile; consider a small supervisor
   loop (or a systemd user service) wrapping the session so the switch is clean and the tty doesn't
   hit a start-limit (we already hit getty start-limit-hit once during the deck migration).

## Phase 3 — Polish + integration
- Suspend/resume in desktop (reuse `pocknix-sleep` / pocknix-bsp sleep hooks).
- Audio already works (deck/PipeWire); polkit already covers `deck`/wheel for power/network/timedate.
- Plasma Mobile first-run: scale, lockscreen/screen-blanking prefs, default apps.
- Verify the gamepadui "Switch to Desktop" button appears once `steamos-session-select` is real.

---

## Top risks to validate early
1. **kwin rotation on the rotated DSI panel** (Phase 1.3) — highest risk; gamescope sidestepped it
   with a shader, kwin must do a real DRM transform. Validate before building anything else.
2. **plasma-mobile availability on ALARM aarch64** vs having to build the stack.
3. **Switch timing** on the tty-autologin model (no SDDM) — may need the supervisor wrapper, not a
   bare `exec`.

## Key files / touchpoints
- `overlay/home/deck/.bash_profile` — session entry; reads the choice file, execs the right launcher.
- `overlay/etc/systemd/system/getty@tty1.service.d/autologin.conf` — deck autologin (unchanged).
- `packages/pocknix-steam/pocknix-steam` — reference for the new `pocknix-desktop` launcher.
- `packages/pocknix-steamos-shim/` — where `steamos-session-select` becomes real.
- new `packages/pocknix-plasma/` (or `pocknix-desktop`) — the mobile stack + launcher + bootstrap.
- `config/packages/base.list` — package list.
- `scripts/build-image.sh` (`install_local_packages`) — add new packages here (+ the guard).
- `scripts/build-sd-image.sh` (`firstboot_config`) — deck user, overlay rsync, service enablement.

## References
- armada `PLAN.md` (Part A) — Plasma Mobile session *design* reference (NOT the SDDM switch).
- Memories: `plasma-mobile-compositor` (kwin not Sway), `pocknix-os-project`, `pocknix-steam-session`,
  `rp6-input-audio`, `gamescope-rp6-gpu`.
- `progress.md` — game-mode state + the deck-user migration (the model this switch extends).
