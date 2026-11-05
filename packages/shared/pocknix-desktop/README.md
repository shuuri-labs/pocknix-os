# pocknix-desktop

The DE-neutral half of desktop mode: the session launcher and the picker. The desktop itself
comes from a `pocknix-desktop-flavour` provider (`pocknix-desktop-plasma-mobile`,
`pocknix-desktop-plasma`).

## Layout

```
pocknix-desktop/
  PKGBUILD
  pocknix-desktop             /usr/bin: started by pocknix-session for desktop mode
  pocknix-desktop-select      /usr/bin: the picker (list, current, reset, <name> [--now])
  return-to-gamemode.desktop  app entry, shown in every desktop
  *.list                      /usr/share/pocknix/desktop-apps: app lists with no flavour package to ship them
  pocknix-flathub-*           Flathub remote seeding, started by the NM dispatcher once online
  pocknix-fontcache-prune     + zz-pocknix-fontcache.hook: drops font cache entries of removed fonts
  pocknix-desktop.install
```

## Per-desktop app lists

`/usr/share/pocknix/desktop-apps/<name>.list` names the app entries (desktop file ids, one per
line, `#` comments) a desktop brings along. At every start the launcher hides every list but
the session's own, so one desktop's apps never show in another desktop's app list.

- **Own list:** `<name>` equals the session (the `wayland-sessions` file name) or one of its
  `DesktopNames`, lowercased. A list no session owns (`devtools`) is hidden everywhere.
- **Mechanism:** per installed id, a copy of the entry with `NoDisplay=true` in
  `$XDG_RUNTIME_DIR/pocknix-desktop/share`, put first in `XDG_DATA_DIRS`: off every app list,
  still launchable by id. Never a `Hidden=true` stub. Rebuilt at each start; no pacman-owned or
  home file is touched.
- **Who ships a list:** the package that brings the apps. A flavour ships its own
  (`plasma.list`, `plasma-mobile.list`); desktops with no Pocknix package (GNOME, COSMIC,
  Hyprland) and the dev-tool list live here.
- **A desktop's own apps only:** what it pulls in as dependencies, its default terminal, and
  tools that only work in it; never a general app a user picks for any desktop (Firefox). A
  user's own copy in `~/.local/share/applications` always wins over the hidden one.
