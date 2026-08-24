# Contributing to pocknix-os

Contributions are very welcome. pocknix-os is maintained by one person with a small pile of
hardware, so the most valuable thing a PR can bring is **evidence it works on a real device**
and **instructions that let me reproduce that on mine**.

Questions, ideas, or "is this worth doing?" chats: the
[pocknix Discord](https://discord.gg/mSSNKQg9m) or a GitHub issue. For anything large
(a new device family, a new session, a kernel bump, a new packaging approach), open an issue
first so we can agree the shape before you spend the time.

Especially welcome:

- **Emulator configs** that you have dialled in on a device (see the "Not all pre-baked
  emulator configs have been validated yet" note in the README).
- **Device support and testing** for hardware I do not own (AYN Odin 2 family, Thor, Nova).
- **Pocknix Control features and fixes.**
- **Docs corrections** - these need no hardware and no build.

## Contents

- [Ground rules](#ground-rules)
- [Where changes go](#where-changes-go)
- [Building](#building)
- [Testing on a device](#testing-on-a-device)
- [What your testing should cover](#what-your-testing-should-cover)
- [What the PR must contain](#what-the-pr-must-contain)
- [Package rules](#package-rules)
- [Commits and PR hygiene](#commits-and-pr-hygiene)
- [AI assistance](#ai-assistance)
- [Review and merge](#review-and-merge)

## Ground rules

1. **One topic per PR.** A fix, a feature, or a config set. Not three.
2. **Test on hardware, or say plainly that you could not.** Untested is acceptable when
   declared and justified ("no Odin 2 to hand"). Silently untested is not.
3. **Tell me how to test it.** Every PR includes reproduction steps I can follow on my
   device. This is a hard requirement, see
   [What the PR must contain](#what-the-pr-must-contain).
4. **Bump `pkgrel`** when you change what a package ships, otherwise existing users never
   get your change through `pacman -Syu`.
5. **Fixes go in robust locations.** A change that only survives until the next `make sync`,
   the next session restart, or the next reboot is not a fix. See
   [Where changes go](#where-changes-go).

## Where changes go

| Path | What lives there |
|---|---|
| `packages/<pkg>/` | Package sources, `PKGBUILD`s, patch series. Most contributions land here. |
| `devices/<soc>/` | Per-SoC-family and per-board facts: `profile.conf`, `packages.list`, BSP package, InputPlumber configs. See `devices/README.md`. |
| `kernel/<soc>/` | Committed kernel inputs: pinned version, patch series, config, dts. See `kernel/README.md`. |
| `scripts/` | The build harness (`build-*.sh`, `lib.sh`, `stage-repo.sh`, ...). |
| `overlay/` | Files baked into the image rootfs at build time. |
| `config/` | Global build config. |
| `docs/` | User-facing guides. |
| `vendor/` | **Do not edit.** Regenerated wholesale by `make sync` from ROCKNIX. |

Three rules that catch most first-time contributors:

- **Kernel config changes go in the delta block in `scripts/build-kernel.sh`**, not in
  `kernel/<soc>/config` - that file is a synced ROCKNIX snapshot and `make sync` overwrites it.
  The deltas are applied on top of it, with hard asserts for options that must survive
  `olddefconfig`.
- **Anything in `overlay/` or the image scripts only reaches people who reflash.** It does not
  ship through `pacman -Syu`. If a fix needs to reach existing installs, it belongs in a
  package with a bumped `pkgrel`. If it genuinely cannot, say so in the PR.
- **Runtime state that a session or service can clobber must be re-asserted** where it will
  stick (a systemd unit, the session launch path), not set once at install time.

## Building

You do **not** need to build a full image to contribute. Match the smallest thing that
covers your change:

**Anywhere (macOS, x86 Linux, no root):**

```bash
make check      # preflight: validates the harness and any built artifacts
make help       # every target
```

**Pocknix Control frontend** (any host with Node, no aarch64 needed):

```bash
cd packages/pocknix-decky/pocknix-control
npm ci
npm run build         # regenerates dist/index.js - this IS committed, see Package rules
npx tsc --noEmit      # must be clean
```

**A single package** (needs an **aarch64 Linux host with root** - an Arch/Fedora VM on Apple
Silicon or an ARM cloud box both work):

```bash
sudo make packages PKG="pocknix-decky"    # -> build/localrepo/<pkg>-*.pkg.tar.xz
```

**A full image** (same aarch64 Linux host with root; the kernel build is 1-2 hours):

```bash
sudo make kernel
sudo make build
sudo make sd-image      # -> build/image/<soc>/
```

Packages compress as `.pkg.tar.xz`, so glob `*.pkg.tar.*`. Never sign or publish anything -
releases go through the maintainer's staged publish flow.

## Testing on a device

The normal loop is **build the package, copy it over, `pacman -U`, exercise it**. You do not
need to reflash an image for a package change.

```bash
# on the build host
scp build/localrepo/pocknix-decky-*.pkg.tar.* root@<device-ip>:/tmp/

# on the device (default password for root and deck is 'pocknix')
pacman -U /tmp/pocknix-decky-*.pkg.tar.*
systemctl restart <the-unit-you-touched>      # if applicable
journalctl -b -u <the-unit-you-touched>       # check it came up clean
```

**Keep a rollback.** The previous package is still in `/var/cache/pacman/pkg/`; reinstall it
with `pacman -U /var/cache/pacman/pkg/<old-file>` if the new one misbehaves. A reboot back
into a known-good state beats debugging a wedged session.

Notes that will save you an hour:

- **The Steam session runs as the `deck` user (uid 1001)**, not root. If you are poking at
  session state over SSH you need `XDG_RUNTIME_DIR=/run/user/1001`.
- **Never `scp` over a script that is currently executing.** Bash re-reads the file by offset
  and resumes in the middle of the new contents. Copy to `/tmp` and `mv` into place.
- **`scp`ing a script does not install its dependencies.** Install those separately, and make
  sure any new dependency is declared in the `PKGBUILD` before you submit.
- **Pocknix Control can be iterated without building a package**: copy your plugin directory
  over `/home/deck/homebrew/plugins/PocknixControl` (`chown -R deck:deck` it) and reload the
  plugin. Do not restart the Decky loader mid-session. Note that
  `pocknix-decky-sync.service` re-copies the OS-shipped plugin from `/usr/share/decky-plugins`
  on every boot, so a hand-copied plugin is replaced at reboot - fine for iteration, but the
  final verification must be from an installed package.
- **No device or no Linux host?** Still submit. Docs and configs need neither. For code, say
  what you could not test and I will run it.

## What your testing should cover

Not everything applies to every PR. Cover what is relevant, and say which items you skipped.

1. **The happy path, on named hardware.** Which device, which SoC family, and how you
   installed it (`pacman -U` a built package, hand-copied files, or a fresh image).
2. **Cold boot.** Reboot and confirm the behaviour survives, state restores, and the unit
   starts clean in `journalctl -b`. A feature that only works until you power off is not done.
3. **The update path, not just a fresh image.** Confirm the change actually arrives via
   `pacman -U` on an existing install with the bumped `pkgrel`. If the change is image-only,
   say so explicitly.
4. **The other SoC family**, if you touched shared code. sm8550 (RP6, Odin 2 family) and
   sm8250 (RP5, Flip 2) differ in GPU generation, bootloader, and audio. If you only have
   one, test it and declare the other untested.
5. **Devices that lack the hardware you are driving.** Not every board has the LEDs, the fan,
   or the sensor. Probe for the thing and degrade quietly when it is missing; never error the
   session. If you cannot test the absent-hardware path on hardware, at least show the code
   path that handles it.
6. **Failure paths.** No network, missing config file, service disabled, permission denied.
   Especially: anything gated behind Decky or the network can be late or never arrive, so a
   feature that depends on it should not be the only thing restoring important state.
7. **Neighbouring features.** Exercise the rest of the tab, service, or script you touched to
   show you did not regress it.
8. **Game mode reality**, for anything in the Steam session. It must be **fully
   gamepad-navigable** (no touch-only or mouse-only controls), readable at handheld distance,
   and it must not steal focus from the game.
9. **Perf claims need numbers.** Before and after, same scene, same settings, from MangoHud or
   an fps counter. Two traps: `ps` `%CPU` is a **lifetime average**, not current load, and a
   paused or menu scene hides jitter.
10. **Kernel changes**: boots on real hardware, no new errors in `dmesg`, suspend/resume still
    works, and the patch series still applies from a clean tree.
11. **Emulator configs**: emulator version, the exact ROM or title you tested, before/after
    behaviour, and any CPU core pinning (`taskset`) the emulator needed to perform well.

## What the PR must contain

A PR description with four sections. `.github/PULL_REQUEST_TEMPLATE.md` fills these in for
you.

**What** - what changes, in a couple of sentences, and why.

**How** - the approach, and anything non-obvious a reviewer would otherwise have to
reverse-engineer. Call out deliberate choices that look wrong at a glance.

**Tested** - device, SoC family, install method, and what you actually exercised, mapped to
the list above. Include what you could **not** test and why.

**How to test** - **required.** Step-by-step instructions I can follow on my own device to
reproduce your result. Assume I have the repo and a build host but know nothing about your
change. Include:

- the exact build command for the affected package (or "docs only, no build");
- the install and restart commands;
- what to click, run, or launch, in order;
- **what I should see** if it works, and what the old behaviour looked like;
- any setup your test needs (a specific game, ROM, emulator, SD card state, a device with
  particular hardware, a network condition);
- how to get back to a known-good state if it goes wrong.

Concretely:

```markdown
## How to test

    sudo make packages PKG="pocknix-decky"
    scp build/localrepo/pocknix-decky-*.pkg.tar.* root@device:/tmp/
    ssh root@device 'pacman -U /tmp/pocknix-decky-*.pkg.tar.* && reboot'

1. Boot to game mode, open the QAM, Pocknix Control -> Lighting.
2. Move the Brightness slider to ~10%. Expected: the rings dim smoothly and stay the
   chosen hue. Before this change the bottom third of the slider was nearly dead and
   0% lost the colour permanently.
3. Reboot. Expected: the rings come back at the same colour and brightness.

Rollback: `pacman -U /var/cache/pacman/pkg/pocknix-decky-<old>.pkg.tar.xz`
```

"It works on my device" without these steps means the PR sits until I can work out how to
check it, which is the single biggest reason a PR stalls.

## Package rules

- **Bump `pkgrel`** whenever a package's shipped contents change. Without it, `pacman -Syu`
  is a no-op for existing users and only fresh images get your work. Bump `pkgver` only for
  an upstream version change, and reset `pkgrel=1` when you do.
- **Never republish an existing package filename with different contents.** In practice this
  means: always bump, never quietly rebuild.
- **Committed build output must be reproducible.** `packages/pocknix-decky/pocknix-control/dist/`
  is committed and I rebuild it from your sources during review; it should come out
  byte-identical with the pinned toolchain (`npm ci && npm run build`), and `npx tsc --noEmit`
  should be clean. Commit `dist/index.js` and `dist/index.js.map` alongside the `src/` change.
- **Patch series**: numbered files in the package directory, added to `source=()` with
  matching checksums, applying cleanly against the pinned base. If you touch a component
  listed in `PATCHES.md` (gamescope, mesa, mangohud, FEX, the kernels, GRUB), update its row.
- **New dependencies** should come from the Arch Linux ARM repos or `[pocknix]`. Flag anything
  large - image size matters on a handheld.
- **Do not touch `vendor/`.** `make sync` regenerates it.

## Commits and PR hygiene

- **Subject**: `area: concise summary`, lowercase after the colon, under about 65 characters.
  Areas in use: `build`, `kernel`, `image`, `sd-image`, `steam`, `desktop`, `emulation`,
  `input`, `audio`, `wifi`, `suspend`, `perf`, `gamescope`, `mesa`, `fex-emu`, `bsp`,
  `devices`, `repo`, `ci`, `docs`, `cleanup`, or a package name.
- **No em-dashes or en-dashes** in commit messages. Plain hyphens, commas, parentheses.
- **Milestone granularity.** Squash the "try X", "revert X", "fix typo" churn before you
  submit. A commit should be a complete, verified change.
- **Rebase on `main`** rather than merging it in, and re-test after the rebase.
- **Code comments: 2 to 4 lines, and only the WHY.** Status, plan, and validation narrative do
  not belong in comments or commit bodies.
- **CI must be green.** The `lint` job runs `bash -n` over every script and `PKGBUILD`,
  resolves each device profile chain, and checks that every `kernel-cmdline` file still
  matches its `profile.conf`. It is fast; there is no excuse for a red PR.
- **No unrelated reformatting.** It makes the real change unreviewable.

## AI assistance

Using an AI assistant is fine, and the project README is up front about the maintainer doing
the same. Three conditions:

- **Say so in the PR.** It genuinely helps me target the review, and it has done so before.
- **You understand and can explain every line you submit.** If you cannot answer "why this
  way?", it is not ready.
- **It is tested on hardware.** Plausible-looking code that has never run is worse than no PR.

## Review and merge

I read every PR. Device-testable changes merge **after I have run them on my own hardware**,
so expect a few days, and expect specific review comments - `pkgrel` bumps, per-device
coverage, whether a fix lives somewhere durable. If a requested change is outside your comfort
zone (systemd wiring, packaging, the kernel), say so and I will do that part; a PR does not
have to be perfect to be worth merging.

Once merged, the change ships to users as a package update in the next release, or in the next
image if it is image-only.

pocknix-os is [GPL-2.0-or-later](LICENSE.md). By contributing you agree your work ships under
the same licence.
