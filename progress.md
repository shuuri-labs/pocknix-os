# pocknix-os — progress & resume notes

Working notes for picking this back up after a break. For the *why* behind decisions, see
[`plan.md`](plan.md); for *how to run it*, see [`README.md`](README.md). This file tracks
**where things stand and what to do next**.

_Last updated: 2026-06-17 — end of Phase 0._

---

## TL;DR — where we are

- **Phase 0 (build harness & skeleton): DONE.** `make help`, `make check`, `make sync` all
  work and are tested on macOS. Linux-only targets are guarded and fail fast off-Linux.
- **Next: Phase 1 (kernel).** Build `linux-pocknix` → `qcom-abl` boot image (`/flash/KERNEL`).
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
| 1 | `linux-pocknix` PKGBUILD → qcom-abl `/flash/KERNEL` + modules | ⏭️ next |
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
- Decision (resolved): kernel is **self-contained in-repo**, going beyond thorch (which
  syncs the whole kernel from public ROCKNIX, gitignored). Stock upstream Linux source =
  pinned tarball fetched in Phase 1; firmware = `linux-firmware`, not committed.

## Stubs left in place (grep `STUB` in scripts/)

- `scripts/build-image.sh` — kernel build, session/quirk install, image assembly.
- `scripts/build-image-fast.sh` — local pocknix package refresh.
- `scripts/install.sh` — entire internal-storage installer (Phase 6).
- `scripts/build-kernel.sh` — **does not exist yet**; `make kernel`/`make build` look for it.

---

## NEXT: Phase 1 checklist (kernel)

Goal: `make kernel` produces a `qcom-abl` boot image + matching modules tree.

1. **Create `packages/linux-pocknix/PKGBUILD`.** Adapt packaging logic from the vendored
   references:
   - `vendor/rocknix-sm8550/reference/linux/` (ROCKNIX `packages/linux` — build/config steps)
   - `vendor/rocknix-sm8550/bootloader/` (qcom-abl / mkbootimg wrapping)
   - thorch's `linux-thorch` PKGBUILD (overall shape) — fetch from GitHub when needed.
2. **Vendor the kernel source.** Decide: git submodule pinned to the ROCKNIX SM8550 fork
   branch vs. a tarball in `vendor/kernel/`. Patches/DTS/config already synced under
   `vendor/rocknix-sm8550/`.
3. **Reproduce the boot image** (per SM8550 README): apply patches → build `Image` + DTBs →
   gzip kernel + **concatenate DTBs** → `mkbootimg` (qcom-abl). Output:
   - boot image → staged for `/flash/KERNEL`
   - `lib/modules/<ver>/` → into the rootfs `/usr/lib/modules/`
4. **Write `scripts/build-kernel.sh`** to invoke the PKGBUILD and drop the result into the
   local repo (`build/localrepo`) + `build/image/KERNEL`. Wire it into `make kernel`/`build`.
5. **Toolchain:** on aarch64 host, native gcc — nothing extra. On x86_64, supply an aarch64
   cross-toolchain (see plan.md open question #2, now mostly resolved).
6. **Verify** (SM8550 README method): `md5sum` of built `Image` vs deployed `/flash/KERNEL`;
   `uname -r` matches the shipped `lib/modules/<ver>/`; `cat /proc/version` timestamp.

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
