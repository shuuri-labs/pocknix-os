<!--
See "What the PR must contain" in CONTRIBUTING.md. These sections are the whole body: keep each
one short and plain. How to test is required; without it the PR stalls.
-->

## What

<!-- What changes and why, in a few sentences. -->

## How

<!-- One line per choice a reviewer wouldn't guess: "**the choice.** why". No background. -->

## Tested

<!-- What ran on real hardware, with evidence. Code nobody has run waits until someone has. -->

- Device / SoC:
- Installed via: <!-- pacman -U a built package / hand-copied files / fresh image -->
- Exercised:
- Evidence: <!-- a log excerpt, a screenshot, before and after numbers -->
- **Not** tested (and why):

## How to test  <!-- required -->

<!-- Steps I can follow on my device knowing nothing about your change, with what I should see.
     "Docs only, no build needed" is fine for docs PRs. -->

```bash
# install this PR's CI build (the bot comment on the PR links the download)
gh run download <run-id> -R shuuri-labs/pocknix-os -n pr-<N>-<repo> -D pr-build
scp pr-build/<pkg>-*.pkg.tar.* root@<device>:/tmp/
ssh root@<device> 'pacman -U /tmp/<pkg>-*.pkg.tar.*'
```

1.
2.
3.

Expected:

Rollback: `sudo pocknix-rollback`, then reboot.

## Checklist

<!-- Tick what applies, delete the rest. -->

- [ ] `pkgrel` bumped for every package whose contents changed
- [ ] Committed build output regenerated (e.g. `pocknix-control/dist/`, `npx tsc --noEmit` clean)
- [ ] Survives a cold boot
- [ ] Reaches existing installs through `pacman -Syu`, not only a fresh image (or noted as image-only)
- [ ] Degrades quietly on devices without the hardware it drives
- [ ] Gamepad-navigable, if it adds UI to the Steam session
- [ ] Docs that describe what changed are updated in this PR
- [ ] CI is green (lint, the PR rules, and pr-build for a package change), commits follow `area: summary`
- [ ] AI assistance disclosed, if used
