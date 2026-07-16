# devices/ — the device-abstraction boundary

Everything device-specific lives here (or in `kernel/<soc>/`). Shared code never
hardcodes a device fact: the **build** reads `devices/<name>/profile.conf` (sourced by
`scripts/lib.sh` right after `config/pocknix.conf`), and the **running OS** reads
`/usr/lib/pocknix/device.conf`, shipped by the family's BSP package.

`DEVICE` names an **image target**, and there is one FAMILY target per SoC
(`make build DEVICE=sm8550` is the default; `DEVICE=sm8250` for the RP5 family):
each family image serves every board on its SoC, ROCKNIX-style. The BSP
(`pocknix-bsp-<soc>`) ships per-board facts in `/usr/lib/pocknix/boards/<board>.conf`,
and `/usr/lib/pocknix/device.conf` is a sourced **dispatcher** that picks one at
source time by `/proc/device-tree/model`. InputPlumber configs are gated with
`matches:` on the devicetree model. Since consumers *source* `device.conf`, the
dispatcher is invisible to them; `/etc/pocknix/device.conf` still overrides.

Current families:

* **sm8550** (qcom-abl): Retroid Pocket 6 (+TOP-DPAD), AYN Odin 2 / Mini / Portal —
  one RSInput controller config for all boards.
* **sm8250** (arm-efi): Retroid Pocket 5, Retroid Pocket Flip 2 (Flip 2 hardware-unverified).

Adding a **board to an existing family**: a `boards/<board>.conf` + a dispatcher case
arm + (if its controller differs) an inputplumber yaml/map with the board's dt-model
`matches:` — plus, on arm-efi SoCs, a menuentry in the SoC grub.cfg. Bump the BSP
(and bootloader) pkgrels. No new packages, no new image.

## What a family target must provide

```
devices/<soc>/
  profile.conf                    # build-time facts (see devices/sm8550 or devices/sm8250):
                                  #   SOC (selects kernel/<soc>/ + vendor/rocknix-<soc>/),
                                  #   BOOTLOADER (qcom-abl | arm-efi),
                                  #   SD_FAT_LABEL / SD_BOOT_PARTNAME / ROOT_LABEL (bootloader contract),
                                  #   KERNEL_CMDLINE_* (ONE cmdline for the family), FW_SRC_REL,
                                  #   DEVICE_HOSTNAME, DEVICE_BSP_PKG / DEVICE_META_PKG / KERNEL_PKG
  packages.list                   # [pocknix] packages installed for this family (usually
                                  #   just the metapackage; may add ALARM names too)
  packages/
    pocknix-bsp-<soc>/            # the family BSP: device.conf dispatcher + boards/,
                                  #   input maps (dt-model gated), udev quirks, audio UCM,
                                  #   SoC suspend/cpuidle tweaks, kernel-cmdline on qcom-abl
                                  #   (must match the profile — build-packages.sh enforces).
                                  #   MUST: depends=(pocknix-bsp-common)
                                  #   provides/conflicts=(pocknix-bsp)   <- wrong-device guard
    pocknix-device-<soc>/         # metapackage: depends on the BSP + kernel (+ the
                                  #   bootloader package on arm-efi SoCs) + shared session
                                  #   packages. MUST provides/conflicts=(pocknix-device).
```

If the family brings a **new SoC**, also create `kernel/<soc>/` (`kernel.conf` with the
source pins + `config/ patches/ dts/ bootloader/` — populated by `make sync` against the
ROCKNIX device dir named in `ROCKNIX_SOC`), a thin `packages/linux-pocknix-<soc>/`
(copy an existing one; it only packages `make kernel` output — note the qcom-abl vs
arm-efi difference in its /flash hook), a `config/tuning/<soc>.conf` (ROCKNIX's
TARGET_CPU/FLAGS composed as -march/-mtune; FEX TUNE_CPU per their fex package.mk
mapping), and — on arm-efi SoCs — a `packages/pocknix-bootloader-<soc>/` (GRUB payload
+ grub.cfg, see pocknix-bootloader-sm8250). Each SoC gets its own pacman repo tree
(`build/localrepo/<soc>`, published at `POCKNIX_REPO_URL/<soc>`): the tuned packages
(mesa, gamescope, mangohud, fex-emu) share pkgnames across SoCs with different
binaries, so the repos must not mix.

## Boot styles (`BOOTLOADER` in profile.conf)

* `qcom-abl` (sm8550): the ROCKNIX ABL boots an Android boot image (`/KERNEL`,
  mkbootimg, cmdline baked in, all dtbs appended — ABL picks by board id). The BSP
  ships `kernel-cmdline`; the kernel package's hook rebuilds /flash/KERNEL on device.
* `arm-efi` (sm8250): the ABL chainloads GRUB (`EFI/BOOT/bootaa64.efi`); `/KERNEL` is
  a RAW Image; the board dtb is a separate `/boot/grub/<board>.dtb`; the cmdline lives
  in grub.cfg (`packages/pocknix-bootloader-<soc>/grub.cfg` — build-packages.sh
  enforces it matches the profile's `KERNEL_CMDLINE`). Board selection at the boot
  level is the GRUB menuentry; at the OS level it's the dispatcher + model gates.
  (The RP5's STOCK ABL SD-boots this chain; do not flash the ROCKNIX ABL there.)

## The runtime contract (`/usr/lib/pocknix/device.conf` -> `boards/<board>.conf`)

Sourced by shared session scripts (`pocknix-steam`, `pocknix-desktop-rotate`,
`pocknix-play`); `/etc/pocknix/device.conf` is the admin override (sourced after, wins). Keys:

| Key | Used by | Meaning |
|---|---|---|
| `POCKNIX_DEVICE` / `POCKNIX_SOC` | anything | identity |
| `POCKNIX_PANEL_W/H/REFRESH` | pocknix-steam | gamescope -W/-H/-r |
| `POCKNIX_PANEL_ORIENT` | pocknix-steam | gamescope --force-orientation |
| `POCKNIX_PANEL_MM` | pocknix-steam | GAMESCOPE_FAKE_OUTPUT_MM (gamepadui DPI; deliberately faked on small panels) |
| `POCKNIX_DESKTOP_ROTATE/_SCALE` | pocknix-desktop-rotate | kscreen-doctor rotation/scale |
| `POCKNIX_BIG_CORES` | pocknix-play | taskset big-core mask for emulator pinning |
| `POCKNIX_BOOT_STYLE` | pocknix-install/uninstall-internal | qcom-abl (default) or arm-efi; non-qcom-abl refuses until the arm-efi install flow lands |
| `POCKNIX_INTERNAL_DISK` | pocknix-install/uninstall-internal, installer-gui | internal disk (default /dev/sda) |
| `POCKNIX_BOOT_GPT_NAME/_FAT_LABEL`, `POCKNIX_ROOT_LABEL` | pocknix-install/uninstall-internal | internal-install boot contract |

Every consumer falls back to the RP6 values when a key (or the whole file) is absent, so
a missing/partial device.conf degrades to known-good behavior instead of breaking.
(The `POCKNIX_BOOT_STYLE` gate exists precisely because those fallbacks would be wrong
on an arm-efi board's internal storage.)

## Bring-up checklist for a new board

1. Confirm the board's dtb is in `kernel/<soc>/dts` (re-`make sync` if ROCKNIX added it)
   and note the DTS `model =` string — it keys everything at runtime.
2. `boards/<board>.conf` in the family BSP (panel geometry/orientation from the DTS,
   `POCKNIX_BIG_CORES` from the SoC topology) + a dispatcher case arm.
3. InputPlumber: extend the family yaml's `matches:` if the board shares the family
   controller, or add a new model-gated yaml + capability map if it differs.
4. UCM if the sound card name differs; udev quirks as needed. arm-efi: add the board's
   grub.cfg menuentry.
5. Bump pkgrels; `make build DEVICE=<soc>` — no shared file should need editing; if one
   does, the boundary has a hole: fix the boundary, not the device.
6. On-device checklist: docs/dev/device-smoke-checklist.md.
