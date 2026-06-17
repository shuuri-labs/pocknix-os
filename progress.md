# pocknix-os — progress & resume notes

Working notes for picking this back up after a break. For the *why* behind decisions, see
[`plan.md`](plan.md); for *how to run it*, see [`README.md`](README.md); for VM setup +
testing, see [`docs/testing-fedora-vm.md`](docs/testing-fedora-vm.md). This file tracks
**where things stand and what to do next**.

_Last updated: 2026-06-17 — end of Phase 0._

---

## TL;DR — where we are

- **Phase 0 (build harness & skeleton): DONE + VERIFIED.** `make help`/`check`/`sync` work on
  macOS; **`sudo make build` verified end-to-end in a Fedora aarch64 VM** — ALARM bootstrap →
  keyring → full base package install (130 pkgs) completes cleanly. Linux-only targets guarded.
  - Fixes that testing flushed out (all pushed): chroot DNS on systemd-resolved hosts
    (`lib.sh chroot_resolv`), ALARM-only Phase 0 pacman.conf (holo/local deferred), and
    dropping `CheckSpace` (breaks chroot transactions with a bogus "not enough disk space").
  - Benign warnings during base build (ignore): mkinitcpio autodetect "failed to detect root
    filesystem" (chroot), microcode "aarch64 not supported" (x86-only hook), kms
    `drm_privacy_screen_register` symbol, missing vconsole.conf.
- **Phase 1 (kernel): COMPILES** — `make kernel` builds patched 7.0.11 end-to-end in the
  Fedora VM and produces `build/image/KERNEL` (qcom-abl) + modules. **Paused here for review.**
  Remaining before Phase 1 is fully "done": (1) pin `KERNEL_SOURCE_SHA256`, (2) on-device boot
  test — which can't happen until there's a rootfs to mount (a first-boot milestone). **Next
  when resuming: a minimal "prove it boots" image, or Phase 2 features.**
- **Build host:** prefer an **aarch64 Linux** host (native, no qemu, native kernel compile).
  macOS can only do `sync`/`check`/editing — not the actual image build.

## The one-paragraph project recap

Self-contained Arch Linux ARM (aarch64) distro for the **Retroid Pocket 6 (SM8550)** with two
SteamOS-style switchable sessions: **Steam** (gamescope + native ARM64 Steam client, Big
Picture) and **Desktop** (Plasma Mobile on `kwin_wayland`). Kernel = the user's ROCKNIX SM8550
fork, vendored in and built here. Modeled on [thorch-os](https://github.com/thorch-os/thorch).

---

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | Build harness, repo skeleton, ALARM bootstrap, pacman wiring, `sync` | ✅ done |
| 1 | `build-kernel.sh` → qcom-abl `KERNEL` + modules; rootfs integration | ✅ compiles in VM; pending sha256 pin + on-device boot |
| 2 | `pocknix-bsp`/quirks: inputplumber, suspend hooks, audio/thermal | ⬜ |
| 3 | Steam session: gamescope (DRM) + native ARM steam, `pocknix-steam.service` | ⬜ |
| 4 | Desktop session: Plasma Mobile + `kwin_wayland`, `pocknix-desktop.service` | ⬜ |
| 5 | `pocknix-session-select` + boot default + in-session switch entries | ⬜ |
| 6 | Image assembly + internal-storage installer (ABL-preserving) | ⬜ |

---

## What works right now (verified on macOS)

- `make help` — target list.
- `make check` — preflight (correctly flags "image build needs Linux" on macOS).
- `make sync` — refreshes two destinations from the local `distribution/` ROCKNIX checkout:
  - **`kernel/` (COMMITTED, ~2.5 MB)** — the full RP6 kernel input set that ships in the repo:
    - `patches/` — **68 patches in ROCKNIX apply order**: `10-mainline/` (5 generic) →
      `20-sm8550/` (61 device: suspend/resume, RP6 panel, RSInput, TSENS) → `30-version/` (2).
    - `dts/qcom/qcs8550-retroidpocket-rp6.dts` (+ `.dtsi`s), `config/linux.aarch64.conf`.
    - `config/kernel-firmware.dat`, `bootloader/` packaging. See `kernel/README.md`.
  - **`vendor/` (GITIGNORED, build-time only)** — `reference/` copies of ROCKNIX steam
    launch scripts + quirks to adapt, and the 160 MB `filesystem/` firmware overlay (stock
    firmware actually comes from `linux-firmware` at build).
- Decision (resolved): kernel inputs are a **pinned snapshot of ROCKNIX `next` (nightly)** +
  jaewun's suspend branch + our small delta, **committed** in `kernel/` (self-contained +
  reproducible). We track **nightly (`next`), not stable**. The RP6 is officially supported
  by ROCKNIX, so most patches are public ROCKNIX work — our delta is just jaewun's suspend
  set + TSENS `0203` / `CONFIG_PM_SLEEP_DEBUG` / SDAM hooks. Stock Linux source = pinned
  tarball fetched in Phase 1; firmware = `linux-firmware`, not committed. Thorch auto-fetches
  nightly at build; we pin+commit instead. `make sync` advances the pin.

## Stubs left in place (grep `STUB` in scripts/)

- `scripts/build-image.sh` — kernel build, session/quirk install, image assembly.
- `scripts/build-image-fast.sh` — local pocknix package refresh.
- `scripts/install.sh` — entire internal-storage installer (Phase 6).
- `scripts/build-kernel.sh` — **does not exist yet**; `make kernel`/`make build` look for it.

---

## Phase 1 (kernel) — COMPILES in VM ✅ (pending sha256 pin + on-device boot)

Built end-to-end via `sudo make kernel`: patched 7.0.11 → `build/image/KERNEL` + modules.
Bug fixed along the way: SIGPIPE/exit-141 from `yes "" | make olddefconfig` (now plain
`olddefconfig`). To pin reproducibility: `sha256sum build/cache/linux-7.0.11.tar.xz` →
`KERNEL_SOURCE_SHA256` in `config/pocknix.conf`.

`scripts/build-kernel.sh` (run via `make kernel`) reproduces ROCKNIX's recipe and assembles
the qcom-abl boot image. `build-image.sh install_kernel()` integrates it into the rootfs.

What it does:
- Fetch stock kernel.org `linux-7.0.11` (pinned via `KERNEL_SOURCE_SHA256`), extract.
- Apply the committed stack **in order**: `kernel/patches/{10-mainline,20-sm8550,30-version}`.
- Copy `kernel/dts` into the tree and **ensure a `dtb-` Makefile entry** for each
  `qcs8550-*.dts` (no SM8550 patch registers them — may already be in stock 7.0.11).
- `.config` from `kernel/config/linux.aarch64.conf`, substituting `@DEVICENAME@`→RP6 and
  `@INITRAMFS_SOURCE@`→empty (**no embedded initramfs**), then `olddefconfig`.
- `make Image dtbs modules` (native gcc on aarch64; cross on x86).
- Boot image = `gzip(Image)` ++ all DTBs appended, **dummy ramdisk**, `mkbootimg` with
  ROCKNIX params (offsets 0, header v0, os 12.0.0) → `build/image/KERNEL`.
- `install_kernel()`: drop generic `linux-aarch64`, rsync modules → rootfs `/usr/lib/modules/`.

Key design call: **no initramfs.** UFS/SCSI/ext4 are built-in (`=y`), so the kernel mounts
the ext4 root directly. cmdline = `root=PARTLABEL=POCKNIX_ROOT rw` + ROCKNIX's SM8550 params
(replacing LibreELEC's `boot=/disk=LABEL=`). Dummy ramdisk mirrors ROCKNIX's known-good boot.

### To test in the Fedora aarch64 VM
```bash
sudo dnf install -y gcc make bc bison flex openssl-devel elfutils-libelf-devel \
                    perl python3 git xz gzip rsync diffutils
git pull
make kernel          # native compile; ~long. produces build/image/KERNEL + build/kernel/out
make check           # should now show kernel build <ver> + boot image KERNEL <size>
```

### Still open / to verify
- **On-device boot** (only testable on the RP6): does qcom-abl accept our cmdline + dummy
  ramdisk, and is `root=PARTLABEL=POCKNIX_ROOT` correct? PARTLABEL needs a GPT partition
  named `POCKNIX_ROOT` — finalized by the Phase 6 installer. Fallback if needed: real
  mkinitcpio ramdisk (assemble_bootimg accepts a ramdisk arg) or `root=/dev/sdaN`/PARTUUID.
- **Pin `KERNEL_SOURCE_SHA256`** in `config/pocknix.conf` once the 7.0.11 tarball is fetched.
- **Verify** (SM8550 README): `md5sum` built KERNEL vs deployed `/flash/KERNEL`; `uname -r`
  matches shipped modules; `cat /proc/version`.

---

## Open questions still pending (full list in plan.md)

1. **holo ↔ ALARM ABI split (highest risk):** holo `gamescope`/`steam` must link against ALARM
   `mesa`/`glibc`. Diff core package versions before first real `make build`. Fallback: build
   gamescope from source against ALARM mesa. *(Resolve early — gates Phase 3.)*
2. Kernel toolchain — mostly resolved (native on aarch64). Confirm mkbootimg/qcom-abl params.
3. DRM mode query without sway (RP6 panel res/refresh/rotation for gamescope args).
4. Native ARM Steam (`steamrtarm64`) provenance — exact holo package vs runtime download.
5. Internal partition layout — confirm RP6 ROCKNIX scheme; ext4 writable root vs squashfs.
6. Adreno 740 Vulkan on ALARM mesa (Turnip) — validate on-device.
7. Steam scope — native client only for v1; FEX/Proton deferred.

---

## Gotchas learned (don't rediscover these)

- **macOS rsync is ancient (2.6.9)** — it won't create nested destination parents. `sync.sh`
  pre-`mkdir`s them. If you add more rsync targets, do the same or it'll fail cryptically.
- **`A && B || C` traps:** a failing `B` runs `C`. Bit us once (rsync failures showed as
  "(missing)"). Prefer explicit `if` blocks in the scripts.
- The **build needs root** (chroot/mount) and **Linux**. Both are guarded in `lib.sh`
  (`need_root`, `need_linux`).
- Set **`DISTRIBUTION_DIR`** if your `distribution/` checkout isn't at `../distribution`.
- Set **`POCKNIX_ALARM_SHA256`** for reproducible builds; otherwise you get a warning and an
  unpinned "latest" ALARM tarball.

## Handy commands

```bash
make help                                   # targets
make check                                  # preflight (anywhere)
export DISTRIBUTION_DIR=$HOME/Documents/Coding/distribution
make sync                                   # refresh vendored ROCKNIX inputs
grep -rn STUB scripts/                      # what's left to implement
# on aarch64 Linux, as root:
sudo make build                             # bootstrap + base packages
```
