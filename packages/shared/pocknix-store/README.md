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
  90-pocknix-store-adopt.hook  runs adopt after a store install or a device meta change
  pocknix-store.desktop   app menu entry
  qml/                    the app: /usr/share/pocknix-store/qml/Main.qml
  catalogue.d/            one <id>.conf per entry
  icons/                  entry icons, credited in icons/CREDITS
  tiles/                  Steam tile manifests: the store's own (auto=1, added once per account),
                          and those of entries whose package ships none (Moonlight)
```

## Catalogue entries

`catalogue.d/<id>.conf`, `key=value` lines. The file name is the entry id the CLI takes.

| Key | Meaning |
|---|---|
| `name` | shown on the tile |
| `section` | `emulation`, `compatibility`, `network`, `streaming` or `desktop` (shown as Desktop mode): each section is one page in the app's rail |
| `description` | one line under the name |
| `icon` | a file in `icons/`, else a theme icon name |
| `packages` | what install adds and remove takes away, space-separated |
| `variants` | per-GPU builds of one package: the store takes the one the installed `pocknix-device-<soc>` lists in `optdepends`; none listed hides the entry |
| `tile` | the pocknix-tiles manifest name; absent = no Steam tile toggle |
| `services` | systemd services or sockets enabled `--now` after install and disabled before removal |
| `note` | one line the app shows once the install finishes (where to turn it on) |
| `setup` | one named step built into the CLI (`tailscale-operator`), never a command |

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
| `adopt` | root | marks installed entries outside Emulation that nothing requires as explicit |
| `setup <id>` | root | runs an installed entry's `setup` step again (Pocknix Tools restores the Tailscale operator that `tailscale logout` clears) |

- **Ids, never package names.** The rule lets wheel run the CLI with any arguments, so the
  catalogue plus the `pocknix-emu-*` set is the whole allowlist. The meta and the
  `pocknix-emulation` alias are only reached through `install-all`, `remove-all` and the switch
  below.
- **Shared packages stay.** A removal never takes a package another installed entry lists
  (gnome-keyring belongs to GNOME, COSMIC and Hyprland alike).
- **All and Pick.** All = the meta is installed. Removing one emulator in All mode marks the other
  installed members explicit, then removes the meta and the alias with it: the device is in Pick
  mode and keeps the rest.
- **pacman runs in the `pocknix-job` unit `store`.** The root command validates the ids and
  starts the unit, which runs `pocknix-store job <command> <id>...` and validates them again. Exit
  3 when a store job or another pacman transaction is running.
- **adopt** keeps a package a meta stops requiring (Proton, now `optdepends` of the device metas)
  from turning into an orphan that a cleanup would remove. The hook runs `adopt --later`, which
  starts it as the unit `pocknix-store-adopt`: pacman holds its lock while hooks run.
- Tiles and default settings are not root's: the app runs `pocknix-tiles` and
  `pocknix-roms-init --reset` as the user.
