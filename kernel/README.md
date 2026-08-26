# kernel/ — per-SoC kernel inputs (pinned ROCKNIX nightly snapshots)

Each `kernel/<soc>/` directory holds one SoC's **complete kernel input set, committed
in-repo** so pocknix-os is self-contained *and* reproducible: a clone builds the exact
same kernel with no ROCKNIX checkout needed. Only **stock Linux source** and **stock
firmware** are fetched at build (both version+sha pinned, per-SoC in
`kernel/<soc>/kernel.conf`). The device profile (`devices/<name>/profile.conf`) selects
the SoC; devices on the same SoC (RP6 + AYN Odin 2, both `sm8550/`) share the tree —
every board's dtb ships and the bootloader picks it (qcom-abl: by board id from the
boot image's appended dtbs; arm-efi: by the grub.cfg menuentry's `devicetree` line).

Currently: `sm8550/` (synced for the Retroid Pocket 6; the notes below describe it)
and `sm8250/` (synced for the Retroid Pocket 5 — same recipe, 28 SoC patches from
ROCKNIX `devices/SM8250/patches/linux`, arm-efi boot so its `bootloader/` holds
ROCKNIX's update.sh reference rather than qcom-abl packaging).

## Provenance — what's whose

The RP6 is **officially supported by ROCKNIX**, so the bulk of these patches are **public
ROCKNIX work**, not ours:

- **Public ROCKNIX RP6/SM8550 support** — the RP6 panel (`0104`), touchscreen, backlight,
  audio, thermal, etc. From ROCKNIX's **`next` (nightly)** branch.
- **jaewun's suspend/resume set** — `0203`, `0207`, `1004`, `1006`–`1010`, `1015` (UFS
  hibern8/clk-gating, geni irq masking, rsinput MCU suspend) plus the thorch s2idle stack
  `1045`–`1051` (PCIe suspend OPP floor, rpmh suspend-state votes, lowest GPU OPP). From
  `jaewun/ROCKNIX` `thor-suspend-fixes` / thorch; we merge/maintain it. Retired at 7.2:
  `0201` (its premise, a threaded IRQF_ONESHOT UFS handler, is gone upstream) and
  `1040`–`1044` (the "PCI: qcom: Add D3cold support" v5 series landed in 7.2).
- **Our delta** (small) — SD UHS-I SDR104 (`0210`–`0212` + the RP6/Odin 2 sdhc_2 nodes),
  `1020`/`1021` (DPU UBWC param, RP6 120Hz-only mode), and DTS edits that `make sync`
  does not carry (see PATCHES.md): the RP6 touchscreen at 400kHz I2C without
  `no-regmap-bulk-read` (armada-packages PR #32: the AYN workaround the RP6 inherited
  forced 63 single-byte reads per frame, capping touch at ~28Hz instead of 120Hz).

What's committed here is a **pinned snapshot of ROCKNIX `next` (nightly)** + jaewun's branch +
our delta — taken from the maintainer's `distribution/` fork (branch `thor-suspend-merge`).
We track **nightly (`next`), not a stable release**. `make sync` advances the pin when we
choose, which keeps builds reproducible (the kernel doesn't move under us between syncs).

Thorch, by contrast, auto-fetches public ROCKNIX nightly at build time (gitignored). We pin +
commit instead — same build, but reproducible and clone-standalone.

## The full kernel = stock source + this patch stack + this config

The kernel is **not** "stock Linux + a few device patches." It reproduces ROCKNIX's recipe:
stock kernel.org source (pinned per SoC in `kernel/<soc>/kernel.conf` — sm8550 **`7.2`**,
sm8250 **`7.2`**) with the full ROCKNIX patch stack applied **in order**, then the SoC
config, then qcom-abl packaging. The pin can lead or lag ROCKNIX; `make sync` moves the
patch stack, never the pin.

## Contents

| Path | What | Apply order |
|---|---|---|
| `patches/10-mainline/` | ROCKNIX generic backports (input-polldev, pwm, adc-keys, BT RTL8733BU) — 4 | 1st (before device) |
| `patches/20-sm8550/` | SM8550 / RP6 device patches — 73: suspend/resume set, RP6 panel, RSInput gamepad, TSENS uplow-wake fix, audio, thermal, SD UHS, etc. | 2nd |
| `patches/30-version/` | Generic version-specific patches (msm resource cleanup, initramfs warn, rust build fix) — 3 | 3rd (after device) |
| `dts/qcom/` | RP6 device tree (`qcs8550-retroidpocket-rp6.dts` + shared `.dtsi`s) | — |
| `config/linux.aarch64.conf` | Kernel config | — |
| `config/kernel-firmware.dat` | List of firmware files to pull from `linux-firmware` (blobs NOT vendored) | — |
| `bootloader/` | qcom-abl boot-image packaging reference | — |

The numeric subdir prefixes encode ROCKNIX's `mainline -> ${DEVICE} -> <version>` patch-dir
order (version dir named in kernel.conf); the build script applies them in sorted order.

## What is NOT here (fetched at build, Phase 1)

- **Stock Linux source** — kernel.org `linux-<ver>.tar.xz`, version+sha-pinned per SoC in
  `kernel/<soc>/kernel.conf` (`KERNEL_VERSION` / `KERNEL_SOURCE_URL` / `KERNEL_SOURCE_SHA256`).
  Not committed (stock, huge).
- **Firmware blobs** — sourced from the `linux-firmware` package per `kernel-firmware.dat`.

## Provenance / refreshing

These files are mirrored from the maintainer's ROCKNIX `distribution/` checkout
(`projects/ROCKNIX/devices/SM8550/`). To pull the latest:

```bash
export DISTRIBUTION_DIR=$HOME/Documents/Coding/distribution
make sync     # refreshes kernel/ — review `git diff`, then commit
```

`make sync` overwrites this directory from your distribution checkout, so treat changes here
as "synced snapshots": refresh via sync, review the diff, commit. (See `scripts/sync.sh`.)
