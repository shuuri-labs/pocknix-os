# pocknix-ui

The touch UI host both Pocknix Tools and the Pocknix Store run on. The apps hold no logic: every
action is a CLI, and the app only starts it, shows its progress and reads its result.

## Layout

```
pocknix-ui/
  PKGBUILD
  CMakeLists.txt
  pocknix-ui          /usr/bin wrapper: drops Steam's preload env, starts the host
  pocknix-job         /usr/lib/pocknix-ui/pocknix-job: pacman runs that outlive the app
  pocknix-pacman      /usr/lib/pocknix-ui/pocknix-pacman: pacman with progress lines added
  host/               the host (main.cpp) and the C++ types Job and Host
  qml/Pocknix/Ui/     the Pocknix.Ui QML module, compiled into the host
```

## Running an app

`pocknix-ui <app>` loads `/usr/share/pocknix-<app>/qml/Main.qml`; the app's package ships that
folder and stays `arch=any`. `pocknix-ui path/to/Main.qml` loads a file directly, for work on a
device. Steam tiles run `pocknix-ui <app>`: a tile's command is its identity in Steam, so it
never changes.

- Wayland in both sessions. Under gamescope the app runs fullscreen without decorations at the
  board's `POCKNIX_DESKTOP_SCALE` (the wrapper reads device.conf) and Plasma's 10pt font, so it
  reads the same in both sessions. `QT_SCALE_FACTOR` in the environment wins.
- An app is an `AppWindow` whose `TabPage` children are its pages, listed in a left rail with
  each page's `title` and `icon` (a `-symbolic` theme name: only those draw in the rail's tint).
- The window owns the confirm sheet: a page calls `app.ask({ title, text, confirmText, hold,
  danger, yes })` or `app.notice(title, text)`. Paths and `key=value` parsing are in `Util`.
- Controls use Qt's Basic style, coloured from `Theme.qml` through the window palette. A reskin
  edits `Theme.qml` (and the components), never a CLI.

## The CLI contract

Every CLI an app calls follows these rules.

| Piece | Rule |
|---|---|
| Status | `<cli> status --json` prints one JSON object. It runs without root wherever pacman -Q or files suffice. No version field: an app and its CLIs ship in one package |
| Log | Every stdout and stderr line is shown in the app's log, as is |
| Progress | A stdout line `POCKNIX:{...}` is parsed, never shown. Keys: `phase`, `text`, `progress` (0 to 1; absent or null = unknown) |
| Exit code | 0 done, 1 error, 2 usage, 3 busy (Steam not ready, pacman db locked, a job already running), 4 no Steam account |
| Cancel | Closing stdin is the only cancel. A CLI that supports it restores its state on EOF; the app keeps stdin open only for jobs started with `input: true` |

**Root.** An app reaches root only as `pkexec /usr/bin/pocknix-<cli>`, and the host refuses any
other program. Each CLI's package ships its own `5x-pocknix-*.rules`: the sessions have no polkit
agent, so a program without a rule cannot run at all.

**pacman.** A root CLI never runs pacman as its own child. It calls
`/usr/lib/pocknix-ui/pocknix-job run <name> -- <command>...`, which starts the transient unit
`pocknix-job-<name>` under PID 1 and streams its log back. The command is usually the CLI
itself, re-entered to do the transaction, so a multi-step change finishes as a whole. Every
pacman transaction goes through `/usr/lib/pocknix-ui/pocknix-pacman`, which adds the progress
lines. The app closing (or Steam closing it) then ends only the stream; the transaction
finishes. `pocknix-job follow <name>` re-attaches without root, and `status --json` reports a
running job so a reopened app knows to.