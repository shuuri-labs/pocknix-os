# kernel/ — RP6 (SM8550) kernel enablement

This directory holds the **RP6-specific kernel work, committed in-repo** so pocknix-os is
self-contained: a clone has everything custom needed to build the kernel. Only **stock
upstream Linux source** and **stock firmware** are fetched at build time (both pinned).

This goes further than thorch, which syncs the whole kernel (incl. patches) from public
ROCKNIX at build time into a gitignored tree. Since we maintain the SM8550 fork, our patches
belong in the repo, not behind a build-time fetch.

## The full kernel = stock source + this patch stack + this config

The kernel is **not** "stock Linux + our device patches." It reproduces ROCKNIX's recipe
exactly: stock kernel.org **`linux-7.0.11`** (pinned in `config/pocknix.conf`) with the full
ROCKNIX patch stack applied **in order**, then the SM8550 config, then qcom-abl packaging.
This is the same build thorch performs — we just commit the inputs instead of fetching them
from public ROCKNIX (necessary, since the RP6 patches aren't public).

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
