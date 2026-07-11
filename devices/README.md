# devices/ — the device-abstraction boundary

Everything device-specific lives here (or in `kernel/<soc>/`). Shared code never
hardcodes a device fact: the **build** reads `devices/<name>/profile.conf` (sourced by
`scripts/lib.sh` right after `config/pocknix.conf`), and the **running OS** reads
`/usr/lib/pocknix/device.conf`, shipped by the device's BSP package. Select an image
target with `make build DEVICE=<name>` (default: `rp6`).

## Two target shapes

`DEVICE` names an **image target**, and there are two generations of them:

* **Per-device targets** (`rp6`, `odin2`, `odin2mini`, `odin2portal` — all sm8550):
  one image per board, the BSP's `device.conf` is a static facts file. The original
  layout; will eventually collapse into a family target.
* **Per-SoC family targets** (`sm8250`, first of its kind): ONE image serves every
  board on the SoC, ROCKNIX-style. The BSP (`pocknix-bsp-sm8250`) ships per-board
  facts in `/usr/lib/pocknix/boards/<board>.conf`, and `/usr/lib/pocknix/device.conf`
  is a sourced **dispatcher** that picks one at source time by
  `/proc/device-tree/model`. InputPlumber configs are gated per-board with
  `matches:` on the devicetree model. Adding a board to an existing family = a new
  `boards/` file + its inputplumber yaml(s) + a dispatcher case arm (+ a grub.cfg
  menuentry on arm-efi SoCs) — no new packages, no new image.

New SoCs get a family target from day one. Since consumers *source* `device.conf`,
the dispatcher is invisible to them; `/etc/pocknix/device.conf` still overrides.

## What an image target must provide

```
devices/<name>/
  profile.conf                    # build-time facts (see devices/rp6 or devices/sm8250):
                                  #   SOC (selects kernel/<soc>/ + vendor/rocknix-<soc>/),
                                  #   BOOTLOADER (qcom-abl | arm-efi),
                                  #   SD_FAT_LABEL / SD_BOOT_PARTNAME / ROOT_LABEL (bootloader contract),
                                  #   KERNEL_CMDLINE_*, FW_SRC_REL, DEVICE_HOSTNAME,
                                  #   DEVICE_BSP_PKG / DEVICE_META_PKG / KERNEL_PKG
  packages.list                   # [pocknix] packages installed for this target (usually
                                  #   just the metapackage; may add ALARM names too)
  packages/
    pocknix-bsp-<name>/           # the BSP: input maps, udev quirks, audio UCM,
                                  #   SoC suspend/cpuidle tweaks, device.conf (runtime
                                  #   contract; dispatcher + boards/ on family targets),
                                  #   kernel-cmdline on qcom-abl targets (must match the
                                  #   profile — build-packages.sh enforces it). MUST:
                                  #   depends=(pocknix-bsp-common)
                                  #   provides/conflicts=(pocknix-bsp)   <- wrong-device guard
    pocknix-device-<name>/        # metapackage: depends on the BSP + kernel (+ the
                                  #   bootloader package on arm-efi SoCs) + shared session
                                  #   packages. MUST provides/conflicts=(pocknix-device).
```

If the target brings a **new SoC**, also create `kernel/<soc>/` (`kernel.conf` with the
source pins + `config/ patches/ dts/ bootloader/` — populated by `make sync` against the
ROCKNIX device dir named in `ROCKNIX_SOC`), a thin `packages/linux-pocknix-<soc>/`
(copy an existing one; it only packages `make kernel` output — note the qcom-abl vs
arm-efi difference in its /flash hook), a `config/tuning/<soc>.conf` (ROCKNIX's
TARGET_CPU/FLAGS for the SoC, composed as -march/-mtune; FEX TUNE_CPU per their fex
package.mk mapping), and — on arm-efi SoCs — a `packages/pocknix-bootloader-<soc>/`
(GRUB payload + grub.cfg, see pocknix-bootloader-sm8250). Each SoC also gets its own
pacman repo tree (`build/localrepo/<soc>`, published at `POCKNIX_REPO_URL/<soc>`):
the tuned packages (mesa, gamescope, mangohud, fex-emu) share pkgnames across SoCs
with different binaries, so the repos must not mix. Targets on an existing SoC share
the kernel tree, kernel package, firmware, and repo.

## Boot styles (`BOOTLOADER` in profile.conf)

* `qcom-abl` (sm8550): the ROCKNIX ABL boots an Android boot image (`/KERNEL`,
  mkbootimg, cmdline baked in, all dtbs appended — ABL picks by board id). The BSP
  ships `kernel-cmdline`; the kernel package's hook rebuilds /flash/KERNEL on device.
* `arm-efi` (sm8250): the ROCKNIX ABL chainloads GRUB (`EFI/BOOT/bootaa64.efi`);
  `/KERNEL` is a RAW Image; the board dtb is a separate
  `/boot/grub/<board>.dtb`; the cmdline lives in grub.cfg
  (`packages/pocknix-bootloader-<soc>/grub.cfg` — build-packages.sh enforces it
  matches the profile's `KERNEL_CMDLINE`). Runtime board selection at the boot level
  is the GRUB menuentry (one per board dtb); at the OS level it's the device.conf
  dispatcher + InputPlumber model gates.

## The runtime contract (`/usr/lib/pocknix/device.conf`)

Sourced by shared session scripts (`pocknix-steam`, `pocknix-desktop-rotate`,
`pocknix-play`); `/etc/pocknix/device.conf` is the admin override (sourced after, wins). Keys:

| Key | Used by | Meaning |
|---|---|---|
| `POCKNIX_DEVICE` / `POCKNIX_SOC` | anything | identity |
| `POCKNIX_PANEL_W/H/REFRESH` | pocknix-steam | gamescope -W/-H/-r |
| `POCKNIX_PANEL_ORIENT` | pocknix-steam | gamescope --force-orientation |
| `POCKNIX_PANEL_MM` | pocknix-steam | GAMESCOPE_FAKE_OUTPUT_MM (gamepadui DPI) |
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

On an **existing SoC family** (e.g. a second sm8250 board): add
`boards/<board>.conf` + a dispatcher case arm + inputplumber yaml(s) with the board's
dt-model `matches:` to the family BSP; add the board's menuentry to the SoC grub.cfg
(arm-efi); bump the BSP/bootloader pkgrels. No new image target.

On a **per-device target SoC** (sm8550, until its family collapse):

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
