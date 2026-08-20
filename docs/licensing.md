# Licensing

Original pocknix-os work is licensed **GPL-2.0-or-later**. See [LICENSE.md](../LICENSE.md)
for the full license text.

Copyright (C) 2026 shuuri-labs and the pocknix-os contributors.

"Original work" covers everything authored for this project: the build harness (`build/`,
`scripts/`, `Makefile`), device profiles (`devices/`), the rootfs overlay (`overlay/`),
all `pocknix-*` packages, PKGBUILDs, and patches written for pocknix-os.

## Why GPL-2.0-or-later

Much of this repo is derived from GPL-2.0 material and cannot be licensed more permissively:

- The kernel patch series in `kernel/` are derivative works of the Linux kernel
  (GPL-2.0-only), so they are GPL-2.0 regardless of what the top of this repo says.
- Large parts of the patch sets and BSP material are carried from
  [ROCKNIX](https://github.com/ROCKNIX/distribution), whose original software and scripts
  are GPL-2.0.

GPL-2.0-or-later for the rest keeps the whole repo under one coherent, compatible license
instead of a per-directory patchwork.

## Third-party material

Vendored and packaged third-party components keep their upstream licenses. This repo does
not and cannot relicense them. The main ones:

| Component | Where | Upstream license |
|---|---|---|
| Linux kernel + patch series | `kernel/`, `packages/soc/linux-pocknix-*` | GPL-2.0-only |
| ROCKNIX patches, scripts, BSP material | `kernel/*/patches`, various packages | GPL-2.0 |
| ROCKNIX-built GRUB binary | `vendor/`, `packages/soc/pocknix-bootloader-sm8250` | GPL-3.0-or-later (GRUB) |
| gamescope + patch set | `packages/soc/gamescope` | BSD-2-Clause (patches: GPL-2.0, from ROCKNIX) |
| Mesa | `packages/soc/mesa` | MIT |
| MangoHud | `packages/soc/mangohud` | MIT |
| FEX-Emu | `packages/soc/fex-emu` | MIT |
| alsa-ucm-conf material | `devices/sm8250` BSP | BSD-3-Clause |
| Packaged emulators, tools, and libraries | `packages/*` | each project's own license |

PKGBUILDs in `packages/` fetch pinned upstream sources; the resulting binary packages and
OS images contain those projects under their own licenses. Provenance for vendored
binaries is recorded next to them (for example
`packages/soc/pocknix-bootloader-sm8250/README.provenance`) and in [PATCHES.md](../PATCHES.md).

ROCKNIX additionally licenses its distribution branding and artwork under CC BY-NC-SA.
pocknix-os does not ship ROCKNIX branding; only their GPL-licensed software, scripts, and
patches are used.

## Source availability

Published pocknix-os images and the pacman repo contain GPL-licensed binaries. The
corresponding source is this repository plus the pinned upstream sources referenced by
each PKGBUILD (exact tags and hashes are in the PKGBUILDs and PATCHES.md), which
satisfies the GPL source-offer requirement as long as this repo stays public.
