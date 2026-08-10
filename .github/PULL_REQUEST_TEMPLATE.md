<!--
Thanks for contributing! Please read CONTRIBUTING.md first - especially
"What your testing should cover" and "What the PR must contain".
The "How to test" section below is required: I re-verify changes on my own
hardware before merging, and without steps the PR stalls.
-->

## What

<!-- What changes, and why. A couple of sentences. -->

## How

<!-- The approach. Call out anything non-obvious or anything that looks wrong at a glance
     but is deliberate. -->

## Tested

<!-- Device(s), SoC family (sm8550 / sm8250), and how you installed it (pacman -U a built
     package / hand-copied files / fresh image). Then what you actually exercised. -->

- Device / SoC:
- Installed via:
- Exercised:
- **Not** tested (and why):

## How to test  <!-- required -->

<!-- Steps I can follow on my device to reproduce your result. Assume I have the repo and a
     build host, and know nothing about your change. Include the expected result at each
     step, any setup your test needs (specific game/ROM/emulator/SD state/hardware), and how
     to roll back. "Docs only, no build needed" is a fine answer for docs PRs. -->

```bash
# build
sudo make packages PKG=""

# install
scp build/localrepo/<pkg>-*.pkg.tar.* root@<device>:/tmp/
ssh root@<device> 'pacman -U /tmp/<pkg>-*.pkg.tar.*'
```

1.
2.
3.

Expected:

Rollback: `pacman -U /var/cache/pacman/pkg/<previous>.pkg.tar.xz`

## Checklist

- [ ] `pkgrel` bumped for every package whose contents changed (or: no package contents changed)
- [ ] Committed build output regenerated and committed (e.g. `pocknix-control/dist/` via `npm ci && npm run build`, `npx tsc --noEmit` clean)
- [ ] Survives a reboot / cold boot, where relevant
- [ ] Reaches existing installs through `pacman -U` / `-Syu`, not only a fresh image (or noted as image-only)
- [ ] Degrades quietly on devices without the hardware it drives
- [ ] Gamepad-navigable, if it adds UI to the Steam session
- [ ] CI lint is green, commits follow `area: summary` with no em-dashes
- [ ] AI assistance disclosed, if used
