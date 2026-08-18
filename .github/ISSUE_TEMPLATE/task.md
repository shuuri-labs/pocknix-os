---
name: "Task"
about: "Planned work that is not a bug: features, packaging, infra, docs."
title: "area: short description"
labels: specced
---

## Motivation

<!-- Why this is worth doing. Link any context: Discord thread, roadmap issue, README note. -->

## What to do

<!-- The shape of the work, concrete enough to start without asking. -->

## Where it lives

<!-- Path(s) per the "Where changes go" table in CONTRIBUTING.md. Never vendor/. -->

## Constraints

<!-- Repo rules that apply to this task. Keep the ones that do: -->

- [ ] `pkgrel` bump, so installed devices get the change via `pacman -Syu`
- [ ] Lives in a robust location (survives `make sync`, session restart, reboot)
- [ ] Covers both SoC families, or states why it is scoped to one

## Acceptance

<!-- What "done" looks like: the observable behaviour, and what on-device
     testing must cover (see "What your testing should cover" in CONTRIBUTING.md). -->

- Hardware needed to validate:

## Notes / leads
