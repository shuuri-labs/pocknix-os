---
name: "Bug spec"
about: "A diagnosed bug, ready to pick up. If you are reporting a new problem, use
  the bug report form instead. For planned non-bug work, use the Task template."
title: "area: short problem statement"
labels: specced
---

<!-- This skeleton is also pasted over the body of a raw bug report when
     converting it into a spec. -->

## Problem

<!-- What is wrong or missing, from the user's point of view. If converted from a
     report or Discord thread, link it and credit the reporter. -->

## Reproduction

<!-- Exact steps. "Could not reproduce locally, reported on <device>" is fine - say so. -->

- Devices affected:
- Session (gaming / desktop / both):

## Root cause (if known)

<!-- What is actually going on, or the leads and eliminations so far. -->

## Where the fix lives

<!-- Path(s) per the "Where changes go" table in CONTRIBUTING.md,
     e.g. packages/pocknix-steam/. Never vendor/. -->

## Constraints

<!-- Repo rules that apply to this task. Keep the ones that do: -->

- [ ] `pkgrel` bump, so installed devices get the change via `pacman -Syu`
- [ ] Fix lives in a robust location (survives `make sync`, session restart, reboot)
- [ ] Covers both SoC families, or states why it is scoped to one

## Acceptance

<!-- What "done" looks like: the observable behaviour, and what your on-device
     testing must cover (see "What your testing should cover" in CONTRIBUTING.md). -->

- Hardware needed to validate:

## Notes / leads
