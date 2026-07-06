# pocknix-os docs index

Living references (current, kept up to date):

- [testing-fedora-vm.md](testing-fedora-vm.md) — the build host: Fedora aarch64 VM setup on the M1, deploy loop
- [install-to-internal.md](install-to-internal.md) — installing pocknix to the RP6's internal UFS (and back out)
- [emulation-setup.md](emulation-setup.md) — on-device emulation layout: ROM folders, BIOS names, per-system status
- [waydroid.md](waydroid.md) — Waydroid (Android) setup and gotchas
- [fex-version-bump.md](fex-version-bump.md) — how to bump the pinned FEX commit
- [fex-proton-plan.md](fex-proton-plan.md) — the FEX + Proton-ARM plan and rationale
- [plasma-mobile-plan.md](plasma-mobile-plan.md) — desktop-session (Plasma Mobile) plan
- [pacman-repo.md](pacman-repo.md) — the [pocknix] update repo: signing, hosting, `pacman -Syu` instead of reflashing
- [../devices/README.md](../devices/README.md) — the device-abstraction boundary + new-device bring-up checklist

Root-level: [../README.md](../README.md) (project intro + build flow), [../plan.md](../plan.md)
(original phased build plan), [../progress.md](../progress.md) (the running journal).

## archive/

Closed investigations, kept as records — the fixes live in code now. Each file carries an
`ARCHIVED` header saying what resolved it.

- [archive/gamescope-fps-investigation.md](archive/gamescope-fps-investigation.md) — the FPS-gap hunt (SOLVED); with its capture scripts (`fps-capture.sh`, `offcpu-capture.sh`) and raw `captures/`
- [archive/sm8550-suspend-wake-report.md](archive/sm8550-suspend-wake-report.md) — spurious-wake report (RESOLVED by kernel patch 0504)
- [archive/steam-native-arm-status.md](archive/steam-native-arm-status.md) — native ARM Steam blocker writeup (SUPERSEDED)
