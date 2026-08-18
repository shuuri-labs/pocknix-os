---
name: "Spec"
about: "A specced work item, ready to pick up: a diagnosed bug or planned task.
  If you are reporting a new problem, use the bug report form instead."
title: "area: short summary"
labels: specced
---

<!-- Also pasted over the body of a raw bug report when converting it into a spec. -->

## What and why

<!-- Bugs: the symptom, who hits it, exact repro steps, affected devices + session.
     Tasks: what we're building and the motivation.
     Either way: link the original report or Discord thread and credit the reporter. -->

## What we know

<!-- Bugs: root cause, or the leads and eliminations so far.
     Tasks: design decisions already made, prior art, known dead ends. -->

## Where it lives

<!-- Path(s) per the "Where changes go" table in CONTRIBUTING.md. Never vendor/. -->

## Constraints

<!-- Repo rules that apply. Keep the ones that do: -->

- [ ] `pkgrel` bump, so installed devices get the change via `pacman -Syu`
- [ ] Lives in a robust location (survives `make sync`, session restart, reboot)
- [ ] Covers both SoC families, or states why it is scoped to one

## Acceptance

<!-- What "done" looks like: the observable behaviour, and what on-device testing
     must cover (see "What your testing should cover" in CONTRIBUTING.md). -->

- Hardware needed to validate:

## Notes / leads
