# Contributing to pocknix-os

Contributions are very welcome. pocknix-os is maintained by one person with a small pile of
hardware, so the most useful thing a PR brings is **proof it works on a real device** and
**steps that let me check it on mine**.

Questions or "is this worth doing?": the [pocknix Discord](https://discord.gg/jEpwudj4Fx) or an
issue. For anything large (a new device family, a new session, a kernel bump, a new packaging
approach), open an issue first so we agree the shape before you spend the time.

Especially welcome: emulator configs you've dialled in, testing on hardware I don't own (AYN
Odin 2 family, Thor, Nova), Pocknix Control features and fixes, and docs fixes.

## Ground rules

1. **One topic per PR.** A fix, a feature, or a config set. Not three.
2. **Test your own code on real hardware, and show it.** A log, a screenshot, before and after
   numbers. No build host? CI builds the PR's packages. No device? Find a tester in Discord.
   Docs need no test.
3. **Tell me how to test it.** Every PR has steps I can follow on my device, see
   [What the PR must contain](#what-the-pr-must-contain).
4. **Bump `pkgrel`** when you change what a package ships, or existing installs never get it.
5. **Fix it where it sticks.** A change that only lasts until the next `make sync`, session
   restart or reboot is not a fix.
6. **Keep the PR body short.** The template's sections, filled in plainly. No essays.
7. **CI is green.** It runs `make check`, the PR rules (`scripts/check-pr.sh`) and, for a
   package change, a build of that package.

## Where changes go

| Path | What lives there |
|---|---|
| `packages/shared/<pkg>/` | SoC-neutral packages, built once for every device. Most contributions land here. |
| `packages/soc/<pkg>/` | Packages built per SoC family (GPU stack, emulators, kernels); a `socs` file names the families or says `all`. |
| `packages/gpu/<pkg>/` | Packages built per Adreno generation; a `gpus` file names the generations, matched against each profile's `GPU_GEN`. |
| `devices/<soc>/` | Per-SoC-family and per-board facts: `profile.conf`, compiler tuning, the device metapackage, BSP package, InputPlumber configs. `devices/README.md` says where a new file goes. |
| `kernel/<soc>/` | Committed kernel inputs: pinned version, patch series, config, dts. See `kernel/README.md`. |
| `kernel/common/patches/` | Our SoC-neutral kernel patches, applied to every SoC. |
| `scripts/` | The build harness (`build-*.sh`, `lib.sh`, `stage-repo.sh`, ...). |
| `overlay/` | Files baked into the image rootfs at build time. |
| `config/` | Global build config: `pocknix.conf`, base package lists (`config/packages/`). |
| `docs/` | User-facing guides. |
| `.github/` | Issue and PR templates, the CI workflow. |
| `.githooks/` | Git hooks; `pre-commit` runs the doc check. |
| `build/` | Build output (gitignored): rootfs, images, `localrepo/<soc>` and `localrepo/shared`. |
| `vendor/` | **Do not edit.** Regenerated wholesale by `make sync` from ROCKNIX. |

Four rules that catch most first-time contributors:

- **Kernel config changes go in a delta**, never `kernel/<soc>/config` (a synced snapshot that
  `make sync` overwrites): the delta block in `scripts/build-kernel.sh` for every SoC, or
  `kernel/<soc>/config-delta` (plus `config-assert` to survive `olddefconfig`) for one.
- **`overlay/` and the image scripts only reach people who reflash.** A fix existing installs
  need goes in a package with a bumped `pkgrel`.
- **Runtime state a session or service can clobber is re-asserted where it sticks** (a systemd
  unit, the session launch path), not set once at install time.
- **A new Arch Linux ARM package can't be installed on existing devices until the base hosts
  it.** Add the name to `config/packages/base-extras.list` and say so in the PR; I host it.

## Building

You don't need a full image to contribute. Build the smallest thing your change needs.

```bash
# anywhere (macOS, x86 Linux, no root)
make check                            # preflight: the harness, the docs, the comments
git config core.hooksPath .githooks   # once per clone: the doc check runs before each commit

# Pocknix Control frontend (any host with Node); dist/ is committed
cd packages/shared/pocknix-decky/pocknix-control && npm ci && npm run build && npx tsc --noEmit

# aarch64 Linux with root (an Arch or Fedora VM on Apple Silicon, or an ARM cloud box)
sudo make packages PKG="pocknix-decky"                      # one package -> build/localrepo/
sudo make kernel && sudo make build && sudo make sd-image   # full image; the kernel takes 1-2 hours
```

No aarch64 host? Open the PR anyway: CI builds every package it changes (see
[Testing on a device](#testing-on-a-device)). `make help` lists every target. Targets build the default SoC family; pass `DEVICE=<soc>` for
another (the families are the dirs under `devices/`). Packages are `.pkg.tar.xz`, so glob
`*.pkg.tar.*`. Never sign or publish anything: releases go through my staged publish flow.

## Testing on a device

Build the package, copy it over, `pacman -U`, exercise it. A package change needs no reflash.
SSH is off by default: turn it on in Pocknix Tools, or build the image with `SD_SSH=on`.

```bash
# build host (per-SoC packages land in build/localrepo/<soc>/)
scp build/localrepo/shared/pocknix-decky-*.pkg.tar.* root@<device-ip>:/tmp/

# device (default password for root and deck is 'pocknix')
pacman -U /tmp/pocknix-decky-*.pkg.tar.*
systemctl restart <unit>; journalctl -b -u <unit>
```

**No build host? Use the PR's CI build.** Every PR that changes a package gets an unsigned
build of each one as a workflow artifact named `pr-<N>-<repo>` (`shared` or a SoC family), kept
for 14 days; the run's summary prints the exact commands. Its pkgrel sits below the next
release, so the release upgrades over it. Kernel packages build only once I add the
`build-kernel` label. Install builds only of PRs you trust.

```bash
gh run download <run-id> -R shuuri-labs/pocknix-os -n pr-<N>-<repo> -D pr-build
scp pr-build/*.pkg.tar.* root@<device-ip>:/tmp/
ssh root@<device-ip> 'pacman -U /tmp/*.pkg.tar.*'
```

Every `pacman -U` takes a snapshot first, so the way back is `sudo pocknix-rollback` and a
reboot ([docs/snapshots.md](docs/snapshots.md)).

- **The Steam session runs as `deck` (uid 1001).** Over SSH, poke session state with
  `XDG_RUNTIME_DIR=/run/user/1001`.
- **Never `scp` over a running script.** Bash reads it by offset and resumes mid-file. Copy to
  `/tmp`, then `mv` it into place.
- **`scp`ing a script doesn't install its dependencies.** Declare new ones in the `PKGBUILD`.
- **Pocknix Control iterates without a package:** copy your plugin over
  `/home/deck/homebrew/plugins/PocknixControl` (`chown -R deck:deck` it) and reload the plugin,
  never the Decky loader. A reboot restores the shipped copy, so test the final version from
  an installed package.

## What your testing should cover

Cover what applies, and say what you skipped.

1. **Happy path, on named hardware:** device, SoC family, and how you installed it.
2. **Cold boot:** reboot; the behaviour survives and the unit starts clean in `journalctl -b`.
3. **Update path:** it arrives via `pacman -U` on an existing install, or you say it's image-only.
4. **The other SoC families**, if you touched shared code. They differ in GPU, bootloader and
   audio: test the ones you have and declare the rest untested.
5. **Missing hardware:** on a board without the LEDs, fan or sensor it degrades quietly and never
   errors the session.
6. **Failure paths:** no network, missing config, service disabled, permission denied. Anything
   behind Decky or the network can arrive late or never.
7. **Neighbours:** the rest of the tab, service or script you touched still works.
8. **Game mode:** fully gamepad-navigable, readable at handheld distance, never steals focus.
9. **Perf claims:** before and after numbers, same scene and settings (MangoHud or an fps
   counter). `ps` `%CPU` is a lifetime average, and a paused scene hides jitter.
10. **Kernel:** boots, no new `dmesg` errors, suspend/resume works, the series applies to a
    clean tree.
11. **Emulator configs:** emulator version, the exact title, before and after, and any `taskset`
    pinning it needed.

## What the PR must contain

The template's sections are the whole body: **What**, **How**, **Tested**, **How to test** and
the checklist. `.github/PULL_REQUEST_TEMPLATE.md` lays them out.

**Short and casual.** Write it like a comment to a person, not a report: plain words, short
sentences, nothing I can already read in the diff. Rough sizes:

- **What:** 2-3 sentences, what changes and why.
- **How:** up to 5 one-line bullets, only for choices a reviewer wouldn't guess, written as
  "**the choice.** why".
- **Tested:** device and SoC, install method, what you exercised, the evidence, and what you
  didn't test.
- **How to test:** as long as it needs (below).
- **Checklist:** tick what applies, delete the rest.

Outside code blocks, aim for about 200 words.

**How to test is required.** Steps I can follow on my own device, assuming I have the repo and
a build host but know nothing about your change: the build or CI download command (or "docs
only, no build"),
install and restart, what to do in order, **what I should see** and what it looked like
before, any setup (a game, ROM, SD card state, hardware), and how to roll back. For example:

```markdown
## How to test

    sudo make packages PKG="pocknix-decky"
    scp build/localrepo/shared/pocknix-decky-*.pkg.tar.* root@device:/tmp/
    ssh root@device 'pacman -U /tmp/pocknix-decky-*.pkg.tar.* && reboot'

1. Boot to game mode, open the QAM, Pocknix Control -> Controller -> Stick Lights.
2. Move the Brightness slider to ~10%. Expected: the rings dim smoothly and stay the
   chosen hue. Before this change the bottom third of the slider was nearly dead and
   0% lost the colour permanently.
3. Reboot. Expected: the rings come back at the same colour and brightness.

Rollback: `sudo pocknix-rollback`, then reboot.
```

Without these steps the PR waits until I work out how to check it. That's the biggest reason
PRs stall.

## Package rules

- **Bump `pkgrel`** whenever what a package ships changes; bump `pkgver` only for an upstream
  version, and reset `pkgrel=1` when you do. Never rebuild an existing filename with different
  contents.
- **Committed build output is reproducible.** I rebuild
  `packages/shared/pocknix-decky/pocknix-control/dist/` from your sources, so commit `dist/`
  together with the `src/` change.
- **A new package name needs a `depends=` edge** from the layer metapackage that owns it
  (`pocknix-core`, `pocknix-{steam,desktop,emulation}-full`) or from `pocknix-device-<soc>`, in
  the same PR: `pacman -Syu` never installs a name nothing depends on. A rename needs
  `replaces=` + `conflicts=` for the old name.
- **New dependencies** come from the Arch Linux ARM repos or `[pocknix]`. Flag anything large;
  image size matters on a handheld.
- **License:** a package you author declares `license=('GPL-2.0-or-later')`. A repackage keeps
  the upstream license and names it in a comment on the same line.
- **Shared code doesn't name a chip.** Read device.conf or the build's `SOC` instead.
- **Don't touch `vendor/`.** `make sync` regenerates it.
- **`make check` enforces the rest** and says what's wrong. A deliberate exception is a row with
  its reason in the matching `scripts/*.allow` file; each file's header gives the format.

### Patch series

Numbered files in the package dir, in `source=()` with checksums, applying cleanly to the
pinned base (`kernel/README.md` covers kernel patches). Each patched component keeps a
`PATCHES.md` next to its patches, indexed in the root `PATCHES.md`:

- **Carried:** one entry per patch: the symptom it fixes in plain words, then `Applies:`,
  `Needs:`, `Trap:`, `Source:` and `Drop:` where they say something. How it works goes in the
  patch's own header.
- **Not taken:** anything deliberately skipped, with a one-clause reason.
- **Retired numbers:** a dropped patch's number (plus a Not taken line if a sync would bring it
  back). The commit says why; git keeps the history.
- **Never another project's state** (what it pins or carries): it goes stale the day it moves.

A file ported without a patch (a UCM profile, an InputPlumber map) records its source and our
changes in a `README.provenance` in its package dir, listed in the root `PATCHES.md`.
`make check` fails when a ledger and its patches drift.

## Requesting a package

The locked base is a curated snapshot, not a mirror of Arch. Hosting a package means keeping
it resolvable at every base cut and answering bug reports about it, so requests are judged on
what the package does for the device as a handheld, not on size or on whether Arch carries it.
Open one with the **Package request** issue form; it asks for exactly this.

| The package is... | Answer | Examples |
|---|---|---|
| in Arch Linux ARM, its dependencies already in the base, and it serves the handheld | hosted as an opt-in extra at the next base cut; `pacman -S <name>` then works on a locked device | `tailscale`, `samba` |
| not in Arch Linux ARM, or needs patches | only if it is part of what pocknix does: games, emulation, the two sessions, the device itself | `mesa`, `fex-emu` |
| anything else | install it yourself, unsupported: Flatpak via Discover, `pacman -U` straight from the Arch Linux ARM mirror, `makepkg` from the AUR (`base-devel` and `git` are in the base), or `sudo pocknix-base rolling` for live Arch Linux ARM | editors, toolchains, AUR helpers |

AUR helpers (`yay`, `paru`) aren't hosted: AUR recipes mostly target x86_64, self-built packages
break silently when the base rotates, and an update-everything tool works against the locked
base.

## Commits and PR hygiene

- **Subject:** `area: concise summary`, lowercase after the colon, under about 65 characters.
  The area is a subsystem (`kernel`, `steam`, `desktop`, `emulation`, `audio`, `devices`,
  `docs`, ...) or a package name.
- **Milestone commits.** Squash the "try X", "revert X", "fix typo" churn before you submit.
- **Rebase on `main`** instead of merging it in, and re-test after.
- **Code comments: one line, WHY only.** Two when a trap needs its cause; longer only in a file's
  leading header. If a competent reader wouldn't get anything wrong without it, leave it out.
  `make check` (`scripts/check-comments.py`) enforces the length and what a comment may name.
- **Docs move with the code.** A doc that describes what you changed is updated in the same PR.
- **CI checks the PR too.** `scripts/check-pr.sh` (run it locally with `PR_BODY_FILE=<body>`)
  fails on a cut-short or headerless `.patch` (`scripts/patch-lint.py`), a `pkgrel` or
  `KERNEL_PKGREL` not above `main`'s, a subject not shaped `area: summary`, or a description
  missing What, How, Tested or How to test. A `kernel/` change also runs
  `scripts/check-kernel-apply.sh`, which applies each affected series to the pinned source.
- **No unrelated reformatting.** It hides the real change.

## AI assistance

Fine, and I use it too. Three conditions:

- **Say so in the PR.** It helps me aim the review.
- **You understand what you submit:** the code, what it changes on the device, and what else it
  might touch. If you can't answer "why this way?", it isn't ready.
- **It's tested on hardware**, like any other code PR.

Coding agents pick up [AGENTS.md](AGENTS.md) on their own: the same rules, as a checklist.

## Review and merge

I review every PR. Whether I also run it myself depends on what it can break:

| The PR touches | It merges after |
|---|---|
| docs | review |
| emulator configs, Pocknix Control, desktop apps | review + your evidence |
| the kernel, `devices/`, boot, session startup, `pocknix-core`, packaging (new names, `replaces=`) | review + your evidence + my own run on hardware |

On a device I don't own, your test (or a second tester's) is the hardware pass. A code PR
nobody has run on hardware waits until someone has. If a requested change is outside your
comfort zone (systemd, packaging, the kernel), say so and I'll do that part. Merged changes ship
as a package update in the next release, or in the next image if they're image-only.

pocknix-os is [GPL-2.0-or-later](LICENSE.md). By contributing you agree your work ships under
the same licence.
