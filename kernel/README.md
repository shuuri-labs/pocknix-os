# kernel/ — RP6 (SM8550) kernel inputs (pinned ROCKNIX nightly snapshot)

This directory holds the **complete kernel input set, committed in-repo** so pocknix-os is
self-contained *and* reproducible: a clone builds the exact same kernel with no ROCKNIX
checkout needed. Only **stock Linux source** and **stock firmware** are fetched at build
(both version+sha pinned).

## Provenance — what's whose

The RP6 is **officially supported by ROCKNIX**, so the bulk of these patches are **public
ROCKNIX work**, not ours:

- **Public ROCKNIX RP6/SM8550 support** — the RP6 panel (`0104`), touchscreen, backlight,
  audio, thermal, etc. From ROCKNIX's **`next` (nightly)** branch.
- **jaewun's suspend/resume set** — `0201`, `0204`–`0207`, `1004`, `1006`–`1009`. From
  `jaewun/ROCKNIX` `thor-suspend-fixes`; we merge/maintain it.
- **Our delta** (small) — TSENS uplow-wake broadening (`0203`), `CONFIG_PM_SLEEP_DEBUG`, and
  the SDAM breadcrumb debug hooks.

What's committed here is a **pinned snapshot of ROCKNIX `next` (nightly)** + jaewun's branch +
our delta — taken from the maintainer's `distribution/` fork (branch `thor-suspend-merge`).
We track **nightly (`next`), not a stable release**. `make sync` advances the pin when we
choose, which keeps builds reproducible (the kernel doesn't move under us between syncs).

Thorch, by contrast, auto-fetches public ROCKNIX nightly at build time (gitignored). We pin +
commit instead — same build, but reproducible and clone-standalone.

## The full kernel = stock source + this patch stack + this config

The kernel is **not** "stock Linux + a few device patches." It reproduces ROCKNIX's recipe
exactly: stock kernel.org **`linux-7.0.11`** (pinned in `config/pocknix.conf`, the version
ROCKNIX `next` currently uses for SM8550) with the full ROCKNIX patch stack applied **in
order**, then the SM8550 config, then qcom-abl packaging.

## Contents

| Path | What | Apply order |
|---|---|---|
| `patches/10-mainline/` | ROCKNIX generic backports (joypad gpiolib, input-polldev, pwm, adc-keys, BT RTL8733BU) — 5 | 1st (before device) |
| `patches/20-sm8550/` | SM8550 / RP6 device patches — 61: suspend/resume set, RP6 panel, RSInput gamepad, TSENS uplow-wake fix, audio, thermal, etc. | 2nd |
| `patches/30-version/` | Generic version-specific patches (msm resource cleanup, rust build fix) — 2 | 3rd (after device) |
| `dts/qcom/` | RP6 device tree (`qcs8550-retroidpocket-rp6.dts` + shared `.dtsi`s) | — |
| `config/linux.aarch64.conf` | Kernel config | — |
| `config/kernel-firmware.dat` | List of firmware files to pull from `linux-firmware` (blobs NOT vendored) | — |
| `bootloader/` | qcom-abl boot-image packaging reference | — |

The numeric subdir prefixes encode ROCKNIX's `PKG_PATCH_DIRS="... mainline ${DEVICE} ... 7.0"`
order; the Phase 1 build script applies them in sorted order.

## What is NOT here (fetched at build, Phase 1)

- **Stock Linux source** — kernel.org `linux-7.0.11.tar.xz`, version+sha-pinned in
  `config/pocknix.conf` (`KERNEL_SOURCE_URL` / `KERNEL_SOURCE_SHA256`). Not committed (stock,
  huge). Same base ROCKNIX pins in `packages/linux/package.mk`.
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
