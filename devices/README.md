# devices/ - the device-abstraction boundary

Everything device-specific lives here (or in `kernel/<soc>/`). Shared code never
hardcodes a device fact: the **build** reads `devices/<name>/profile.conf` (sourced by
`scripts/lib.sh` right after `config/pocknix.conf`), and the **running OS** reads
`/usr/lib/pocknix/device.conf`, shipped by the family's BSP package.

`DEVICE` names an **image target**, and there is one FAMILY target per SoC
(`make build DEVICE=sm8550` is the default; `DEVICE=sm8250` for the RP5 family):
each family image serves every board on its SoC, ROCKNIX-style. The BSP
(`pocknix-bsp-<soc>`) ships per-board facts in `/usr/lib/pocknix/boards/<board>.conf`,
each sourcing the family-wide `boards/family.conf` first, and
`/usr/lib/pocknix/device.conf` is a sourced **dispatcher** that picks one at source time
by `/proc/device-tree/model`. `scripts/render-bsp.sh` renders it at package time from the
BSP's `boards/models` table (`<board> <dt model>` rows). InputPlumber configs are gated with
`matches:` on the devicetree model. Since consumers *source* `device.conf`, the dispatcher
is invisible to them; `/etc/pocknix/device.conf` still overrides.

Current families:

* **sm8550** (qcom-abl): Retroid Pocket 6 (+TOP-DPAD), Retroid Pocket Nova, AYN Odin 2 /
  Mini / Portal, AYN Thor. The family RSInput controller config covers every board but the
  Thor, which has its own (its extra AYN key).
* **sm8250** (arm-efi): Retroid Pocket 5, Retroid Pocket Flip 2; each also as a Visionox-panel revision (separate `-visionox` dtb + board conf, picked by the grub `visionox` marker file).

The first board a bullet names is the family's fallback: it must be the first `boards/models`
row, which an unknown or absent model gets (`make check` pins the two together).

Adding a **board to an existing family**: a `boards/<board>.conf` (only what differs from
`boards/family.conf`) + its `boards/models` row(s) + (if its controller differs) an
inputplumber yaml/map with the board's dt-model `matches:` + a `[[device]]` entry in the
BSP's `root/usr/share/steamos-manager/devices/pocknix-family.toml`, ahead of the SoC entry -
plus, on arm-efi SoCs, a menuentry in the SoC grub.cfg.in template and the board in the BSP's board-select script
(pocknix-sm8250-board-select). Bump the BSP (and bootloader) pkgrels. No new packages, no
new image.

## Where a new file goes

* Data about one chip (profile, tuning, freqs, boards) goes in `devices/<soc>/`.
* A chip's own `arch=any` packages (its BSP, its device meta) go in `devices/<soc>/packages/`.
* A recipe built per chip goes in `packages/soc/`, gated by its `socs` file. The goal is
  one recipe for every chip: `packages/soc/linux-pocknix/` builds every chip's kernel
  package from its `kernel/<soc>/kernel.conf`; `pocknix-bootloader-<soc>` is the remaining
  one-chip recipe until it is templated.
* A recipe built per Adreno generation goes in `packages/gpu/`, gated by its `gpus` file
  against each profile's `GPU_GEN`. Neither dir takes the other's gate file.
* `packages/shared/` only if the bytes are identical for every chip.

## What a family target must provide

```
devices/<soc>/
  profile.conf                    # build-time facts that differ per family (see devices/sm8550):
                                  #   SOC (selects kernel/<soc>/ + vendor/rocknix-<soc>/),
                                  #   BOOTLOADER (qcom-abl | arm-efi),
                                  #   KERNEL_CMDLINE_ROOT / KERNEL_CMDLINE_EXTRA (ONE cmdline
                                  #   for the family), DEVICE_PRETTY,
                                  #   GPU_GEN (Adreno generation, a6xx/a7xx/a8xx: selects the
                                  #   packages/gpu packages whose ./gpus file lists it).
                                  #   Defaults a profile may override: config/pocknix.conf
                                  #   (DEVICE_HOSTNAME, SD_FAT_LABEL / SD_BOOT_PARTNAME /
                                  #   ROOT_LABEL, set before the profile: override with X=value)
                                  #   and scripts/lib.sh's profile_defaults (KERNEL_CMDLINE,
                                  #   DEVICE_BSP_PKG / DEVICE_META_PKG / KERNEL_PKG from SOC)
  freqs.txt                       # (with power-profiles.d tables) available cpufreq/devfreq
                                  #   frequencies the tables are checked against
  tuning.conf                     # userspace compiler tuning for the chip's per-SoC
                                  #   builds: POCKNIX_TUNE_CFLAGS (ROCKNIX's TARGET_CPU/FLAGS
                                  #   composed as -march/-mtune)
  packages/
    pocknix-bsp-<soc>/            # the family BSP: boards/ (family.conf, one conf per board,
                                  #   models = the table device.conf is rendered from;
                                  #   POCKNIX_BOOT_STYLE / BOOT_FAT_LABEL / ROOT_LABEL are
                                  #   rendered into family.conf from the profile) +
                                  #   root/, the install tree copied as is (git carries the
                                  #   exec bits and symlinks; make check wants 755 exactly on
                                  #   files with a shebang): input maps
                                  #   (dt-model gated), udev quirks, audio UCM, SoC
                                  #   suspend/cpuidle tweaks, steamos-manager's device match
                                  #   (usr/share/steamos-manager/devices/pocknix-family.toml:
                                  #   the boards, then a qcom,<soc> catch-all), pocknix-perfd's
                                  #   underclock tables (usr/share/pocknix/power-profiles.d/
                                  #   family.conf, checked against freqs.txt), speaker DSP
                                  #   profiles (usr/share/pocknix/speaker-dsp/<name>.conf).
                                  #   No kernel-cmdline: the build renders it from the profile.
                                  #   MUST: depends=(pocknix-bsp-common)
                                  #   provides/conflicts=(pocknix-bsp)   <- wrong-device guard
    pocknix-device-<soc>/         # metapackage: depends on the BSP + kernel + bootloader;
                                  #   optdepends names its protons (the Pocknix Store installs
                                  #   those): exactly the ./gpus packages listing its GPU_GEN
                                  #   (make check enforces, either list), the stock ones otherwise.
                                  #   Nothing every family needs: that goes on pocknix-core.
                                  #   MUST provides/conflicts=(pocknix-device).
    pocknix-firmware-<soc>/       # (optional) vendor firmware linux-firmware lacks or gets wrong,
                                  #   fetched by pinned commit + sha256 (never from vendor/),
                                  #   installed under /usr/lib/firmware/updates/; only boards
                                  #   in the BSP's boards/models. The BSP depends= on it.
```

If the family brings a **new SoC**, also create `kernel/<soc>/` (`kernel.conf` with the
source pins, `KERNEL_PKGREL` (1 for a new chip) + `config/ patches/ dts/` -
populated by `make sync` against the ROCKNIX device dir named in `ROCKNIX_SOC`); the kernel
package needs no recipe of its own (`packages/soc/linux-pocknix/` packages `make kernel` output,
plus `mkbootimg` on qcom-abl; the /flash deploy is bsp-common's and needs nothing per SoC), and a
`packages/soc/pocknix-bootloader-<soc>/` - on arm-efi SoCs the GRUB payload
+ a grub.cfg.in template (see pocknix-bootloader-sm8250), on both styles the ROCKNIX ABL install kit
copied to the SD boot FAT. Each SoC gets its own pacman repo tree
(`build/localrepo/<soc>`, published at `POCKNIX_REPO_URL/<soc>`): the tuned packages
(mesa, gamescope) share pkgnames across SoCs with different
binaries, so the repos must not mix. They build for every SoC already (`socs` = `all`), and
packages gated by GPU generation (`packages/gpu/`, e.g. the a6xx `-dxvk2` protons) follow the
profile's `GPU_GEN`: a new SoC on a known Adreno generation sets it and lists them in its meta;
a SoC-specific kernel config or a local patch delta goes in `kernel/<soc>/` (see
kernel/README.md). `make check` validates every family: required files, family and board keys,
the meta's `gpus` packages against `GPU_GEN`,
the models table against boards/ and the dts model lines (and grub.cfg + board-select on
arm-efi), the consumers' fallbacks, the rendered device.conf and family.conf, and that
the cmdline has no committed copy outside the profile. The BSP PKGBUILD installs what the
build stages into its `./staged` (device.conf, family.conf, and on qcom-abl kernel-cmdline):
copy an existing family's `package()`. A new tree is never published until its first
`make stage`/`make publish`; stage-check skips it for the other SoCs until then.

## Boot styles (`BOOTLOADER` in profile.conf)

On the device the style is `POCKNIX_BOOT_STYLE`, rendered into the BSP's family.conf from
`BOOTLOADER`; bsp-common's `pocknix-boot-deploy` runs that style's /flash deploy for every
kernel update, rollback and cmdline change. Kernel packages ship no deploy scripts or hooks.

* `qcom-abl` (sm8550): the ROCKNIX ABL boots an Android boot image (`/KERNEL`,
  mkbootimg, cmdline baked in, all dtbs appended - ABL picks by board id). The BSP
  ships `/usr/lib/pocknix/kernel-cmdline`, which build-packages.sh renders from the profile's
  `KERNEL_CMDLINE` into its `./staged`; bsp-common's kernel hook rebuilds /flash/KERNEL on device.
  The SD boot FAT also carries `rocknix_abl/` (pocknix-bootloader-<soc>): ROCKNIX's
  first-install kit for flashing that ABL from rooted stock Android - inert at boot,
  pocknix never flashes it itself.
* `arm-efi` (sm8250): the ABL chainloads GRUB (`EFI/BOOT/bootaa64.efi`); `/KERNEL` is
  a RAW Image; the board dtb is a separate `/boot/grub/<board>.dtb`; the cmdline lives
  in grub.cfg, rendered from `packages/soc/pocknix-bootloader-<soc>/grub.cfg.in` with the
  profile's `KERNEL_CMDLINE` in place of each entry's `@KERNEL_CMDLINE@` (build-packages.sh
  stages it; a profile edit rebuilds the BSP and the bootloader package). Board selection at the boot
  level is the GRUB menuentry; at the OS level it's device.conf + model gates.
  The stock ABL SD-boots this chain too; the ROCKNIX ABL kit on the SD boot FAT is
  optional here.

## The runtime contract (`/usr/lib/pocknix/device.conf` -> `boards/<board>.conf`)

Sourced at launch by shared scripts (`pocknix-steam`, the desktop session, bsp-common's
`cores.sh`, the emulation launchers, the install and rollback tools; the table names each);
`/etc/pocknix/device.conf` is the admin override (sourced after, wins). Every key a script
that sources device.conf (or `cores.sh`) reads has a row, and `make check` fails on one that
does not. Absent = `required` means every board resolves it (`make check` fails a board that
leaves it unset); otherwise it says what a board without the key gets. Keys:

| Key | Used by | Absent | Meaning |
|---|---|---|---|
| `POCKNIX_DEVICE` / `POCKNIX_SOC` | anything | required | identity |
| `POCKNIX_PANEL_W` / `POCKNIX_PANEL_H` / `POCKNIX_PANEL_REFRESH` | pocknix-steam, pocknix-roms-init (refresh also: es-retroarch) | required | gamescope -W/-H/-r |
| `POCKNIX_PANEL_ORIENT` | pocknix-steam, pocknix-roms-init | required | gamescope --force-orientation |
| `POCKNIX_PANEL_MM` | pocknix-steam | required | GAMESCOPE_FAKE_OUTPUT_MM (gamepadui DPI; deliberately faked on small panels) |
| `POCKNIX_DESKTOP_ROTATE` / `POCKNIX_DESKTOP_SCALE` | pocknix-desktop-rotate (scale also: pocknix-ui) | required | kscreen-doctor rotation/scale (seeded once per user; env re-forces); the touch apps' scale in game mode |
| `POCKNIX_BOARD_UNKNOWN` | pocknix-desktop-rotate | board known (only the fallback branch sets it) | set by the device.conf fallback branch: board not in the list, do not force guessed values |
| `POCKNIX_PANEL_OUTPUT` | pocknix-steam, pocknix-desktop, pocknix-desktop-rotate, pocknix-desktop-touchpin | single panel, first DSI | DRM connector of the main panel (`DSI-2`); gamescope `--prefer-output`, the desktop seed's output |
| `POCKNIX_PANEL_ROTATE_SHADER` | pocknix-steam | rotation autodetected | `1` = gamescope `--force-composition-rotation`: required for a panel past the DPU rotator's 1088-line cap, which otherwise scans out black |
| `POCKNIX_PANEL2_OUTPUT`, `POCKNIX_PANEL2_W` / `POCKNIX_PANEL2_H`, `POCKNIX_DESKTOP2_SCALE` | pocknix-desktop, pocknix-desktop-rotate, pocknix-desktop-touchpin | single screen (second scale: the main one's) | second panel (dual-screen boards): enabled, rotated like the main one, scaled, placed below it |
| `POCKNIX_TOUCH_NAME` / `POCKNIX_TOUCH2_NAME` | pocknix-desktop, pocknix-desktop-touchpin, pocknix-second-screen, pocknix-steam (second) | no touch mapping, no second-screen handling | evdev names of the main/second touchscreen: kwin maps each to its output (kcminputrc before launch, re-pinned over D-Bus at login); the second is libinput-ignored outside the desktop session (udev rule in the board BSP + pocknix-second-screen) |
| `POCKNIX_BIG_CORES` | via cores.sh: pocknix-steam-env (-> pocknix-game-launch), pocknix-rt-ladder, emulator launchers | required | cores games and emulators are pinned to; the cores left out are the small cores irq work goes to (on a SoC with no little cluster, leave two mids out) |
| `POCKNIX_SPEAKER_SINK` | pocknix-speaker-dsp-render | no speaker DSP | `node.name` of the UCM speaker sink the speaker DSP sits in front of; the same on every board of a family, so it lives in family.conf |
| `POCKNIX_SPEAKER_PROFILE` | pocknix-speaker-dsp-render | no speaker DSP | the board's speaker profile: `usr/share/pocknix/speaker-dsp/<name>.conf` in the family BSP (see "Speaker DSP profiles") |
| `POCKNIX_BOOT_STYLE` | pocknix-install-internal, pocknix-boot-deploy (the kernel hook, pocknix-rollback, pocknix-cmdline-sync) | required | qcom-abl or arm-efi (rendered from the profile's `BOOTLOADER`): selects the /flash kernel deploy (`pocknix-build-bootimg` or `pocknix-update-boot`) and the internal-install boot-file handling (arm-efi pins grub.cfg + fstab to internal PARTUUIDs) |
| `POCKNIX_INTERNAL_DISK` | pocknix-install/uninstall-internal, installer-gui, pocknix-tools, pocknix-rollback, pocknix-internal-boot-rename | required | internal disk |
| `POCKNIX_BOOT_GPT_NAME` / `POCKNIX_BOOT_FAT_LABEL`, `POCKNIX_ROOT_LABEL` | pocknix-install/uninstall-internal, pocknix-tools (root label), pocknix-rollback, pocknix-internal-boot-rename (root label) | required | internal-install boot contract (the two labels are rendered from `SD_FAT_LABEL` / `ROOT_LABEL`, config/pocknix.conf defaults a profile may override) |

Env overrides read by the same scripts, never set in device.conf: `POCKNIX_ROTATE` /
`POCKNIX_SCALE` / `POCKNIX_OUTPUT` (pocknix-desktop-rotate re-forces the desktop seed with them).

Picking the display values for a new board:

* `POCKNIX_PANEL_W/H` are the panel's NATIVE frame. `POCKNIX_PANEL_ORIENT` is `left`/`right`
  for a portrait panel mounted landscape (the consumers transpose) and `normal` for a
  landscape-native panel (no DT `rotation`): W/H pass through untransposed and
  `POCKNIX_DESKTOP_ROTATE=none`.
* `POCKNIX_PANEL_MM` stays `177x100` unless a tester says otherwise. It is a fake that sets
  gamepadui's dpi (`W * 25.4 / 177`), field-validated on 1920- and 1280-wide panels; deviate
  only if the UI crops (dpi too high for the width) or reads tiny.
* `POCKNIX_DESKTOP_SCALE` = the largest 0.25 step that keeps the logical short side >= 480
  (the Plasma Mobile shell needs the height): 1080-line panels -> 2.5, 960-line -> 2.0.

Every consumer also falls back to the RP6 values when a required key (or the whole file) is
absent, so a missing/partial device.conf degrades to known-good behavior instead of breaking.
(The `POCKNIX_BOOT_STYLE` gate exists precisely because those fallbacks would be wrong
on an arm-efi board's internal storage.)
`make check` holds each consumer's `${POCKNIX_<key>:-<value>}` to that rule: a required key's
fallback is the RP6 value, an optional key's is 0 or empty, and `scripts/fallbacks.allow` lists
the exceptions with a reason.

## Speaker DSP profiles

`pocknix-bsp-common` runs the speaker DSP: `pocknix-speaker-dsp.service`, a user unit started
with PipeWire, renders high-pass + EQ -> stereo widening -> post gain + lookahead limiter as a
WirePlumber smart filter on `POCKNIX_SPEAKER_SINK`, so headphones, DisplayPort and Bluetooth
bypass it. It is its own PipeWire client: `pocknix-speaker-dsp on|off` (as root) starts or
stops it without restarting PipeWire. A board without `POCKNIX_SPEAKER_PROFILE` gets no DSP.

A profile is `KEY=value` lines plus `PK`, `LSC` or `HSC` filter lines as REW and AutoEQ write them
(drop an export's `Preamp:` line and unused `None` slots):

```
HIGHPASS=<Hz>      # the speakers' floor; absent = no high-pass
WIDTH=<w>          # mid/side width; absent or 1 = no widening
POST_GAIN=<dB>     # into the limiter; absent = 0
LIMIT=<dBFS>       # limiter ceiling; absent = -0.1
RELEASE=<s>        # limiter release; absent = 0.5
Filter 1: ON PK Fc <Hz> Hz Gain <dB> dB Q <q>
```

`scripts/fit-graphiceq.py "<Hz dB; Hz dB; ...>"` turns a JamesDSP GraphicEQ string into filter
lines. Rules: the codec's digital gain stays at 0 dB (gain after the limiter clips in the
codec); a board with no measured or published curve gets no EQ and no post gain; an imported
curve gets an entry in its BSP's README.provenance and a docs/licensing.md row. `make check`
(`scripts/check-speaker-dsp.py`) fails a board naming a missing profile, a profile the renderer
rejects or no board uses, and a key list above out of step with the renderer.

## Bring-up checklist for a new board

1. Confirm the board's dtb is in `kernel/<soc>/dts` (re-`make sync` if ROCKNIX added it)
   and note the DTS `model =` string - it keys everything at runtime (`make check` fails a
   `boards/models` row that no `model = "...";` under `kernel/<soc>/dts` declares).
2. `boards/<board>.conf` in the family BSP (panel geometry/orientation from the DTS; keys
   every board shares, like `POCKNIX_BIG_CORES`, live in `boards/family.conf`); display
   values per the rule above + a `boards/models` row per DT model string.
3. InputPlumber: extend the family yaml's `matches:` if the board shares the family
   controller, or add a new model-gated yaml + capability map if it differs.
4. UCM if the sound card name differs; udev quirks as needed. arm-efi: add the board's
   grub.cfg menuentry and its arm in the BSP's board-select script.
   Dual-screen board: the `POCKNIX_PANEL2_*`/`POCKNIX_TOUCH*` keys plus a udev rule
   ignoring the second touchscreen unless `/run/pocknix/second-screen` exists (see
   the sm8550 BSP's Thor rule); gamescope blanks the second panel by itself.
   Speakers: `POCKNIX_SPEAKER_SINK` in family.conf plus `POCKNIX_SPEAKER_PROFILE` and a
   profile only with a measured or published curve; otherwise leave both unset.
5. `make check` (board keys, models table, grub menuentries); bump pkgrels; `make build DEVICE=<soc>`.
   No shared file should need editing; if one does, the boundary has a hole: fix the
   boundary, not the device.
