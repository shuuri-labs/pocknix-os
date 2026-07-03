# Waydroid on pocknix-os

Android apps via Waydroid. Target UX: each Android app opens as its own
fullscreen, caption-less Plasma window on the deck (Plasma Mobile) session.
Image is **VANILLA** (no Play Store — Aurora Store works; GApps needs re-init +
device registration).

Kernel prerequisites (binder) live in `scripts/build-kernel.sh`
(`ANDROID_BINDER_IPC` + `BINDERFS`). The `waydroid` package is in
`config/packages/desktop.list`. First run still needs `waydroid init`.

## How windowing actually works (non-obvious)

`persist.waydroid.multi_windows` does **not** control the number of windows — it
toggles Android *freeform* (draws a caption bar: min/max/close + back) vs
*fullscreen* (no caption) windowing. Waydroid maps every `waydroid app launch
<pkg>` to its own Plasma toplevel (`app_id waydroid.<pkg>`) either way. So:

- `multi_windows=false` → clean per-app windows, **no caption**, **back-only**
  nav bar. Home/Recents belong to the `show-full-ui` shell composite; here Plasma
  is the shell (task switcher = recents, close = home). Intents spawn new app
  windows. **This is the desired behaviour.**
- The caption bar is Android freeform decoration — only removable via
  `multi_windows=false` (or patching the Android system image; not worth it).

**Do not add a KWin fullscreen force rule.** It traps the bottom-edge swipe (so
you can't reach the Plasma task switcher) and breaks the nav bar. The mobile
default (`Placement=Maximizing` + `BorderlessMaximizedWindows`) already fills the
screen once the panel strut is gone (below).

## Baked into the image (overlay/)

- `overlay/usr/local/bin/pocknix-waydroid-tuning` + its `.service`
  (`WantedBy=waydroid-container.service`, enabled in `build-sd-image.sh`). Runs
  on every container start, waits for `sys.boot_completed`, then idempotently
  re-asserts the four/five Android `/data` settings below. These live in Android
  `/data`, so **`waydroid init` wipes them** — the hook restores them at launch.
- `overlay/usr/local/bin/pocknix-waydroid-apk-install` + the deck
  `waydroid-apk-install.desktop` — "Open With → Install with Waydroid" handler
  for `.apk` files (auto-starts a session if needed). Set it as the default apk
  handler on first run: `xdg-mime default waydroid-apk-install.desktop
  application/vnd.android.package-archive`.

### The Android `/data` settings the hook pins
1. `navigation_mode=0` + `threebutton` overlay (gesture nav conflicts with the
   host Plasma edge gestures).
2. `wm density 360` — **display size**. Waydroid auto-density drifts (seen
   213/248/450); at 1080 a low value pushes smallestWidth ≥600dp → tablet UI
   (taskbar nav, edge-swipe eaten as back). 360 → swdp ~432 → phone UI, user's
   preferred size. Stored as `forcedDensity` in `display_settings.xml` (only
   persists when the value ≠ physical).
3. `font_scale=1.0` — **font size**.
4. `policy_control=immersive.status=*` — hides Android status bar, keeps nav bar.
5. `persist.waydroid.multi_windows=false` — read at container boot, so it takes
   effect the **next** start (persists after).

## Host-side (Plasma) — NOT yet auto-baked

Applied on-device; survives `waydroid init` but not a fresh image. TODO: fold
into the deck config skeleton safely (partial-file merge risk on the mobile
shell config).

- `~/.config/plasmamobilerc [General] autoHidePanelsEnabled=true` — the "Auto
  Hide Panels" mobile-shell quicksetting. Removes the **top status-bar panel's
  strut** so Waydroid sizes its wayland surface to the full work area (1080)
  instead of 1025 — this is what closed the ~55px bottom gap. (Plain KWin
  `panelVisibility` is ignored by the mobile panel.)
  Apply: `kwriteconfig6 --file plasmamobilerc --group General --key
  autoHidePanelsEnabled true` then restart plasmashell.

## Storage layout

- `/var/lib/waydroid/` — images, `waydroid.cfg`, overlays.
- Android `/data` — `~/.local/share/waydroid/data/` (LXC rbind-mounts it). Owned
  by host uid 1000 (`alarm`) because Android's `system` uid maps straight through
  (no userns remap).
- `/sdcard` = `.../data/media/0/` (Download there is app-uid:media_rw 1023, mode
  770 → deck can't read it). FUSE emulated storage is active.
- Routing Android downloads → host `~/Downloads`: bind-mount before session start
  (rbind is a snapshot) + uid friction. **Open / not implemented.**

## App shortcuts are automatic

Waydroid's `UserMonitor` (`tools/services/user_manager.py`) writes
`~/.local/share/applications/waydroid.<pkg>.desktop` (`Exec=waydroid app launch
<pkg>`) on **any** app install — Play Store, Aurora, sideload, `waydroid app
install`. System apps get `NoDisplay=true` (hidden); user-installed apps show. So
store-installed apps auto-get own-window shortcuts and the built-ins stay hidden
— no configuration needed.
