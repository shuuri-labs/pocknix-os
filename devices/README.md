# devices/ — the device-abstraction boundary

Everything device-specific lives here (or in `kernel/<soc>/`). Shared code never
hardcodes a device fact: the **build** reads `devices/<name>/profile.conf` (sourced by
`scripts/lib.sh` right after `config/pocknix.conf`), and the **running OS** reads
`/usr/lib/pocknix/device.conf`, shipped by the device's BSP package. Select a device
with `make build DEVICE=<name>` (default: `rp6`).

## What a device must provide

```
devices/<name>/
  profile.conf                    # build-time facts (see devices/rp6/profile.conf):
                                  #   SOC (selects kernel/<soc>/ + vendor/rocknix-<soc>/),
                                  #   SD_FAT_LABEL / SD_BOOT_PARTNAME / ROOT_LABEL (bootloader contract),
                                  #   KERNEL_CMDLINE_*, FW_SRC_REL, DEVICE_HOSTNAME,
                                  #   DEVICE_BSP_PKG / DEVICE_META_PKG / KERNEL_PKG
  packages.list                   # [pocknix] packages installed for this device (usually
                                  #   just the metapackage; may add ALARM names too)
  packages/
    pocknix-bsp-<name>/           # the device BSP: input maps, udev quirks, audio UCM,
                                  #   SoC suspend/cpuidle tweaks, device.conf (runtime
                                  #   contract), kernel-cmdline (must match profile —
                                  #   build-packages.sh enforces it). MUST:
                                  #   depends=(pocknix-bsp-common)
                                  #   provides/conflicts=(pocknix-bsp)   <- wrong-device guard
    pocknix-device-<name>/        # metapackage: depends on the BSP + kernel + shared
                                  #   session packages. MUST provides/conflicts=(pocknix-device).
```

If the device brings a **new SoC**, also create `kernel/<soc>/` (`kernel.conf` with the
source pins + `config/ patches/ dts/ bootloader/` — populated by `make sync` against the
ROCKNIX device dir named in `ROCKNIX_SOC`) and a thin `packages/linux-pocknix-<soc>/`
(copy the sm8550 one; it only packages `make kernel` output). Devices on an existing SoC
(e.g. RP6 + Odin 2, both sm8550) share the kernel tree, the kernel package, and the
firmware — the kernel/boot image carries every board's dtb and the bootloader picks by
board id.

## The runtime contract (`/usr/lib/pocknix/device.conf`)

Sourced by shared session scripts (`pocknix-steam`, `pocknix-desktop-rotate`);
`/etc/pocknix/device.conf` is the admin override (sourced after, wins). Keys:

| Key | Used by | Meaning |
|---|---|---|
| `POCKNIX_DEVICE` / `POCKNIX_SOC` | anything | identity |
| `POCKNIX_PANEL_W/H/REFRESH` | pocknix-steam | gamescope -W/-H/-r |
| `POCKNIX_PANEL_ORIENT` | pocknix-steam | gamescope --force-orientation |
| `POCKNIX_PANEL_MM` | pocknix-steam | GAMESCOPE_FAKE_OUTPUT_MM (gamepadui DPI) |
| `POCKNIX_DESKTOP_ROTATE/_SCALE` | pocknix-desktop-rotate | kscreen-doctor rotation/scale |

Every consumer falls back to the RP6 values when a key (or the whole file) is absent, so
a missing/partial device.conf degrades to known-good behavior instead of breaking.

## Bring-up checklist for a new device (same SoC)

1. `devices/<name>/profile.conf` — start from rp6's; fix labels/cmdline if the bootloader
   contract differs; set the package names.
2. `devices/<name>/packages/pocknix-bsp-<name>/` — new input maps (InputPlumber
   device + capability_map), UCM if the card differs, copies of the SoC quirk confs,
   `device.conf` with the real panel geometry/orientation, `kernel-cmdline` matching the
   profile.
3. `devices/<name>/packages/pocknix-device-<name>/PKGBUILD` + `packages.list`.
4. `make build DEVICE=<name>` — no shared file should need editing; if one does, the
   boundary has a hole: fix the boundary, not the device.
5. On-device checklist: docs/dev/device-smoke-checklist.md.
