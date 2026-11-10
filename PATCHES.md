# PATCHES.md: index of the patch ledgers

Each patched component keeps a `PATCHES.md` next to its patches (base, one entry per patch, what
is not taken, retired numbers); files ported from another project record theirs beside them.

## Patches

| Component | Ledger | Base |
|---|---|---|
| kernel (common) | [kernel/common/PATCHES.md](kernel/common/PATCHES.md) | Each SoC's kernel, after the SoC's own stack |
| kernel (sm8550) | [kernel/sm8550/PATCHES.md](kernel/sm8550/PATCHES.md) | Stock 7.2.10 + ROCKNIX `next` 6103571f67 (2026-10-11) |
| kernel (sm8250) | [kernel/sm8250/PATCHES.md](kernel/sm8250/PATCHES.md) | Stock 7.2.10 + ROCKNIX `next` 6103571f67 (2026-10-11) |
| gamescope | [packages/soc/gamescope/PATCHES.md](packages/soc/gamescope/PATCHES.md) | Valve `3.16.31` (f6916aa, 2026-09-27) |
| mesa | [packages/soc/mesa/PATCHES.md](packages/soc/mesa/PATCHES.md) | 26.3.0 tarball, epoch=2 |
| pocknix-turnip-arm | [packages/soc/pocknix-turnip-arm/PATCHES.md](packages/soc/pocknix-turnip-arm/PATCHES.md) | One pinned Mesa main snapshot, named in the PKGBUILD |
| mangohud | [packages/shared/mangohud/PATCHES.md](packages/shared/mangohud/PATCHES.md) | v0.8.4, one shared untuned build |
| fex-emu | [packages/shared/fex-emu/PATCHES.md](packages/shared/fex-emu/PATCHES.md) | `896a8691` (FEX-2610 + its clang 23 thunkgen fix, 2026-10-12), one shared build |
| pocknix-mesa-android | [packages/shared/pocknix-mesa-android/PATCHES.md](packages/shared/pocknix-mesa-android/PATCHES.md) | 26.3.0 tarball (mesa's pin), epoch=2 |
| steamos-manager | [packages/shared/steamos-manager/PATCHES.md](packages/shared/steamos-manager/PATCHES.md) | upstream `8e2883d` (v26.4.1-12, 2026-09-17), pinned upstream Rust 1.99.0 |
| scx-scheds | [packages/shared/scx-scheds/PATCHES.md](packages/shared/scx-scheds/PATCHES.md) | upstream `v1.1.3` (c8728c6, 2026-08-19), pinned upstream Rust 1.99.0 |
| plasma-mobile | [packages/shared/plasma-mobile/PATCHES.md](packages/shared/plasma-mobile/PATCHES.md) | 6.8.1 tarball (Arch's build) |
| powerdevil | [packages/shared/powerdevil/PATCHES.md](packages/shared/powerdevil/PATCHES.md) | 6.8.1 tarball (Arch's build, no kdoctools) |
| gtk2 | [packages/shared/gtk2/PATCHES.md](packages/shared/gtk2/PATCHES.md) | gtk+ 2.24.33 tarball |

## Ported files

| Ported | Provenance |
|---|---|
| alsa-ucm, speaker DSP profiles, InputPlumber maps (sm8250) | [devices/sm8250/packages/pocknix-bsp-sm8250/README.provenance](devices/sm8250/packages/pocknix-bsp-sm8250/README.provenance) |
| alsa-ucm, speaker DSP profile, InputPlumber maps (sm8550) | [devices/sm8550/packages/pocknix-bsp-sm8550/README.provenance](devices/sm8550/packages/pocknix-bsp-sm8550/README.provenance) |
| firmware (sm8550) | [devices/sm8550/packages/pocknix-firmware-sm8550/README.provenance](devices/sm8550/packages/pocknix-firmware-sm8550/README.provenance) |
| format-device.sh | [packages/shared/pocknix-sdcard-automount/README.provenance](packages/shared/pocknix-sdcard-automount/README.provenance) |
| GPcal calibration maths | [packages/shared/pocknix-gamepad-calibration/README.provenance](packages/shared/pocknix-gamepad-calibration/README.provenance) |
| GRUB + ABL kit (sm8250) | [packages/soc/pocknix-bootloader-sm8250/README.provenance](packages/soc/pocknix-bootloader-sm8250/README.provenance) |
| ABL kit (sm8550) | [packages/soc/pocknix-bootloader-sm8550/README.provenance](packages/soc/pocknix-bootloader-sm8550/README.provenance) |
| Cemu AppImage | [packages/shared/cemu/README.provenance](packages/shared/cemu/README.provenance) |
| Lepton | [packages/shared/pocknix-lepton/README.provenance](packages/shared/pocknix-lepton/README.provenance) |
| DXVK donor | [packages/gpu/pocknix-dxvk2-donor/README.provenance](packages/gpu/pocknix-dxvk2-donor/README.provenance) |
| Proton-GE DXVK 2 | [packages/gpu/proton-ge-dxvk2/README.provenance](packages/gpu/proton-ge-dxvk2/README.provenance) |
| sysctl tuning + zram swap | [packages/shared/pocknix-bsp-common/README.provenance](packages/shared/pocknix-bsp-common/README.provenance) |
