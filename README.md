# pocknix-os

A minimal, reproducible **Arch Linux ARM (aarch64)** distro for the **Retroid Pocket 6**
(Qualcomm SM8550) with two SteamOS-3-style switchable sessions:

1. **Steam** — `gamescope` (DRM) + the **native ARM64 Steam client** in Big Picture mode.
2. **Desktop** — **Plasma Mobile** (on its own `kwin_wayland` compositor).

It is a **full, self-contained OS**: the kernel (the user's ROCKNIX SM8550 fork, producing a
`qcom-abl` boot image) is vendored into and built *by* this project. Modeled on
[thorch-os](https://github.com/thorch-os/thorch). See [`plan.md`](plan.md) for the full
phased build plan and rationale.

## Status

**Phase 0 — build harness & repo skeleton.** Bootstrap (ALARM rootfs download/verify/extract),
pacman repo wiring (ALARM + Valve holo + local), and base-package install are in place. Kernel
build (Phase 1), sessions (Phase 3/4), switching (Phase 5) and image assembly (Phase 6) are
stubbed with clear markers.

## Layout

```
kernel/        COMMITTED RP6 kernel enablement: patches, DTS, config, fw list, bootloader
config/        pacman.conf template, repo settings (pocknix.conf), package lists
packages/      local makepkg PKGBUILDs (linux-pocknix, pocknix-bsp, session units…)
scripts/       sync / bootstrap / build-image / fast / install / check
vendor/        GITIGNORED build-time material (reference scripts, firmware overlay); `make sync`
build/         build output (rootfs, image, localrepo, cache)
plan.md        full phased plan
```

### Self-contained kernel (vs thorch)

The full kernel input set lives **in the repo** under `kernel/` (patches, DTS, config, fw
list) as a **pinned snapshot of ROCKNIX `next` (nightly)** — the RP6 is officially supported
upstream, so most patches are public ROCKNIX work; the maintainer's delta is small (jaewun's
suspend branch + a few debug patches). Only **stock Linux source** (version+sha-pinned tarball)
and **stock firmware** (`linux-firmware`) are fetched at build.

This is more self-contained *and* reproducible than thorch, which auto-fetches ROCKNIX nightly
at build into a gitignored tree. We track **nightly (`next`), not stable**; `make sync`
advances the pin from your `distribution/` checkout (review the diff, commit). See
[`kernel/README.md`](kernel/README.md) for provenance.

## Requirements

The image build runs on a **Linux host, as root** (it uses `chroot`). Tools needed:
`bash, curl, tar (bsdtar preferred), rsync, sed`.

> The maintainer works from macOS; run the build targets on a Linux build box, VM, or
> container. `make check`, `make sync`, and editing all work fine on macOS.

### Build host architecture (matters — aarch64 is simpler)

The **target is always aarch64**; the host's architecture only changes whether the host-side
steps run natively or under emulation. The harness auto-detects this — no flags to set.

| Step | aarch64 Linux host | x86_64 Linux host |
|---|---|---|
| Rootfs package install (chroot + pacman) | **native**, no qemu | needs `qemu-aarch64-static` + binfmt (emulated, slow) |
| Kernel compile (Phase 1) | **native** gcc, no cross-toolchain | cross-compile with an aarch64 toolchain |
| `mkbootimg` / qcom-abl packaging | arch-independent | arch-independent |

An **aarch64 Linux host is preferred**: native pacman install (no emulation) and a native
kernel build. `maybe_install_qemu()` in `scripts/lib.sh` skips qemu entirely on aarch64.

> **Note on the kernel:** the SM8550 README says "build on x86_64; the ROCKNIX Docker image
> is amd64-only." That applies to *ROCKNIX's own buildroot container*, **not** to pocknix-os.
> Phase 1 builds the kernel via the in-project `linux-pocknix` PKGBUILD, so on an aarch64 host
> it compiles natively with the host gcc — no cross-toolchain and no Docker. The config's
> `aarch64-rocknix-linux-gnu-gcc-15.2.0` string is informational; any recent GCC 15.x works.

Good aarch64 host options: an aarch64 Linux **VM on Apple Silicon** (UTM/Parallels), an **ARM
cloud instance** (AWS Graviton, Oracle Ampere, Hetzner ARM), or any ARM board with enough disk.

## Quick start

```bash
make help                         # list targets
make check                        # preflight (works anywhere)

export DISTRIBUTION_DIR=$HOME/Documents/Coding/distribution   # ROCKNIX source
make sync                         # vendor SM8550 kernel + device files

# on a Linux host, as root:
export POCKNIX_ALARM_SHA256=...    # pin for reproducible builds (optional)
sudo make build                   # bootstrap + base packages (later phases stubbed)
```

## Configuration

All knobs live in [`config/pocknix.conf`](config/pocknix.conf) and can be overridden via the
environment. Key ones: `DISTRIBUTION_DIR`, `POCKNIX_ALARM_SHA256`, `HOLO_REPO_URL`/`HOLO_RELEASE`.

Package sourcing is deliberate (see plan.md): **mesa from Arch Linux ARM** (holo's lags),
**steam/gamescope/mangoapp from Valve holo**, Plasma Mobile + base from ALARM.
