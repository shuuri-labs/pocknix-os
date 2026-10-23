# pocknix-store

The Pocknix Store: one-tap install and removal of the optional pieces, so the base stays slim.
The app is QML on [pocknix-ui](../pocknix-ui/README.md); every change goes through the root CLI
`pocknix-store`.

## Layout

```
pocknix-store/
  PKGBUILD
  pocknix-store           /usr/bin: the CLI (status as the user, changes as root)
  57-pocknix-store.rules  promptless pkexec of the CLI for wheel
  pocknix-store.desktop   app menu entry
  qml/                    the app: /usr/share/pocknix-store/qml/Main.qml
  catalogue.d/            one <id>.conf per entry
  icons/                  entry icons, credited in icons/CREDITS
```

## Catalogue entries

`catalogue.d/<id>.conf`, `key=value` lines. The file name is the entry id the CLI takes.

| Key | Meaning |
|---|---|
| `name` | shown on the tile |
| `section` | `emulation`, `compatibility`, `network` or `streaming` |
| `description` | one line under the name |
| `icon` | a file in `icons/`, else a theme icon name |
| `packages` | what install adds and remove takes away, space-separated |
| `tile` | the pocknix-tiles manifest name; absent = no Steam tile toggle |

- **Hidden until hosted.** An entry shows only when every package is in the sync db or installed.
  The store reads the local copy of the sync db, so a newly hosted package appears after the next
  update (every install runs a full `-Syu`).
- **Emulators need no entry.** Any `pocknix-emu-*` package in the sync db shows under Emulation;
  an entry only gives it a name, an icon and the description. Without one it uses the package
  description and the theme icon `applications-games`.
- An icon added to `icons/` gets a line in `icons/CREDITS`: project, upstream path and commit,
  licence and any credit the licence asks for.

## The CLI

| Command | Runs as | Does |
|---|---|---|
| `status --json` | user | entries with installed state, emulation mode, store job state |
| `follow` | user | re-attaches to a running store job |
| `install <id>...` | root | `pacman -Syu --needed` the entries' packages |
| `remove <id>...` | root | `pacman -Rs` the entries' packages |
| `install-all` | root | the emulation meta `pocknix-emulation-full` (All mode) |
| `remove-all` | root | the meta, its emulators and their now-unneeded dependencies |

- **Ids, never package names.** The rule lets wheel run the CLI with any arguments, so the
  catalogue plus the `pocknix-emu-*` set is the whole allowlist. The meta and the
  `pocknix-emulation` alias are only reached through `install-all`, `remove-all` and the switch
  below.
- **All and Pick.** All = the meta is installed. Removing one emulator in All mode marks the other
  installed members explicit, then removes the meta and the alias with it: the device is in Pick
  mode and keeps the rest.
- **pacman runs in the `pocknix-job` unit `store`.** The root command validates the ids and
  starts the unit, which runs `pocknix-store job <command> <id>...` and validates them again. Exit
  3 when a store job or another pacman transaction is running.
- Tiles and default settings are not root's: the app runs `pocknix-tiles` and
  `pocknix-roms-init --reset` as the user.
