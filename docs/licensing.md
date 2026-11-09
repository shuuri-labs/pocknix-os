# Licensing

Original pocknix-os work is licensed **GPL-2.0-or-later**. See [LICENSE.md](../LICENSE.md)
for the full license text.

Copyright (C) 2026 shuuri-labs and the pocknix-os contributors.

"Original work" covers everything authored for this project: the build harness (`scripts/`,
`Makefile`, `config/`), device profiles (`devices/`), the rootfs overlay (`overlay/`),
all `pocknix-*` packages, PKGBUILDs, and patches written for pocknix-os. Each package we
author declares `GPL-2.0-or-later` in its PKGBUILD; packages that repackage third-party
content (firmware, the kernel, bootloaders, upstream builds) declare the upstream license.

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
| Linux kernel + patch series | `kernel/`, `packages/soc/linux-pocknix/` | GPL-2.0-only |
| ROCKNIX patches, scripts, BSP material | `kernel/*/patches`, various packages | GPL-2.0 |
| ROCKNIX-built GRUB binary | `packages/soc/pocknix-bootloader-sm8250` | GPL-3.0-or-later (GRUB) |
| ROCKNIX ABL (fetched, pinned) | `packages/soc/pocknix-bootloader-*` | BSD-3-Clause (Qualcomm edk2 LinuxLoader) |
| gamescope + patch set | `packages/soc/gamescope` | BSD-2-Clause (the patch set: GPL-2.0; origins in its PATCHES.md) |
| Mesa | `packages/soc/mesa` | MIT |
| Mesa for Android + Fossilize layer | `packages/shared/pocknix-mesa-android` | MIT (Mesa, Fossilize), Apache-2.0 WITH LLVM-exception (static libc++, NDK compiler-rt) |
| MangoHud | `packages/shared/mangohud` | MIT |
| FEX-Emu | `packages/shared/fex-emu` | MIT |
| GPcal calibration maths | `packages/shared/pocknix-gamepad-calibration` | MIT |
| alsa-ucm-conf material | `devices/*` BSPs | BSD-3-Clause |
| Speaker EQ curves | `devices/*` BSPs, `usr/share/pocknix/speaker-dsp/` | each curve author's terms, named in the profile header (RP5, Flip 2: kokoko3k's jdsp4rp5, GPL-2.0; RP6: Ryan Retro, used with his permission) |
| Valve DXVK build (fetched, pinned) | `packages/gpu/pocknix-dxvk2-donor` | zlib |
| Proton-GE, Proton-CachyOS | `packages/gpu/proton-*-dxvk2` | BSD-3-Clause (Proton) plus each bundled component's own |
| Packaged emulators, tools, and libraries | `packages/*` | each project's own license |

PKGBUILDs in `packages/` fetch pinned upstream sources; the resulting binary packages and
OS images contain those projects under their own licenses. Provenance for vendored
binaries is recorded next to them (for example
`packages/soc/pocknix-bootloader-sm8250/README.provenance`), indexed in [PATCHES.md](../PATCHES.md).

ROCKNIX additionally licenses its distribution branding and artwork under CC BY-NC-SA.
pocknix-os does not ship ROCKNIX branding; only their GPL-licensed software, scripts, and
patches are used.

## Source availability

Published pocknix-os images and the pacman repo contain GPL-licensed binaries. The
corresponding source is this repository plus the pinned upstream sources referenced by
each PKGBUILD (exact tags and hashes are in the PKGBUILDs and each component's PATCHES.md), which
satisfies the GPL source-offer requirement as long as this repo stays public.
