# pocknix-os — Arch-ARM dual-session distro for the Retroid Pocket 6 (SM8550)

## Context

Goal: a minimal, reproducible Arch Linux ARM (aarch64) distro for the Retroid Pocket 6
(Qualcomm SM8550) with two switchable sessions, modeled on the SteamOS 3 session-switch UX:

1. **Steam session** — `gamescope` (DRM backend) running the **native ARM64 Steam client**
   in SteamOS Big Picture mode (`-steamos3 -gamepadui`).
2. **Desktop session** — **Plasma Mobile** (KDE mobile shell).

The kernel is the user's ROCKNIX SM8550 fork, which builds a `qcom-abl` Android boot image
deployed as `/flash/KERNEL`. The distro must run on that kernel, not a generic one. This is
a **full, self-contained OS**: the kernel source + RP6 patches live *in this project* and
are built *by this project* (not imported from an external repo). `pocknix-os/` is currently
empty — a greenfield, scripted image builder modeled on **thorch-os** (Arch-on-ROCKNIX for
the AYN Thor, same SoC).

### Decisions locked in this session
- **Kernel:** vendored into this project and built here as a `linux-pocknix` package — full
  self-contained OS, not an imported prebuilt blob. (Modeled on thorch's `linux-thorch`.)
- **Rootfs base:** clean Arch Linux ARM tarball + Valve's `holo-core-aarch64` pacman repo
  for SteamOS-mode packages only. Keeps pure pacman per constraint.
- **Package sourcing split (important):**
  - **`mesa` → Arch Linux ARM repo** (not holo). SteamOS's mesa often lags behind upstream
    stable; ALARM tracks current. Applies to the Adreno 740 Vulkan/GL stack for *both*
    sessions.
  - **`steam`, `gamescope` (+ `mangohud`/`mangoapp`, SteamOS-mode bits) → holo
    `holo-core-aarch64`.** These are the Valve-specific, SteamOS-mode packages worth reusing
    as-is rather than rebuilding.
  - **Plasma Mobile + base userland → Arch Linux ARM repo.**
- **Install target:** **internal storage**, replacing the existing ROCKNIX install (same
  `/flash` + root partition layout the kernel already expects). No SD-image phase.
- **Steam client:** **native ARM64 client** (`steamrtarm64`), *not* Steam-under-FEX. FEX is
  needed only later for x86 *game content* via "Proton 11.0 (ARM64)" — deferred, optional.

### Key correction to the original brief
The brief asked whether to host Plasma Mobile "in Sway or a bare Wayland compositor." Neither:
**Plasma Mobile is its own compositor.** Its shell runs as
`kwin_wayland ... plasmashell -p org.kde.plasma.mobileshell`. Hosting it inside Sway is
unsupported and pointless. See "Compositor recommendation" below.

---

## Architecture overview

Two independent systemd-managed sessions, each owning DRM/KMS directly when active. No
persistent base compositor underneath (cleaner than ROCKNIX's sway-base + stop/start dance;
matches SteamOS 3, where Steam and Desktop are mutually exclusive sessions):

- `pocknix-steam.service` → gamescope (`--backend drm`) + native ARM Steam.
- `pocknix-desktop.service` → `kwin_wayland` + Plasma Mobile shell.
- `pocknix-session-select` → persists the choice, stops the active unit, starts the other.
  Modeled on ROCKNIX `steamos-session-select`
  (`packages/emulators/standalone/steam/scripts/steamos-session-select`) but generalized to
  two real sessions rather than a kill script.

Both sessions render through the SM8550 Adreno 740 via **Arch Linux ARM mesa (Turnip/freedreno)**,
on the RP6 panel defined by the kernel's `qcs8550-retroidpocket-rp6.dts`.

---

## Phased build plan

### Phase 0 — Build harness & repo skeleton
Create the scripted, reproducible builder in `pocknix-os/`. Mirror thorch-os layout:
```
config/        # pacman.conf fragments, repo definitions, image package lists
packages/      # local makepkg PKGBUILDs (pocknix-* packages)
scripts/       # build-image.sh, build-image-fast.sh, sync.sh, install.sh
vendor/        # synced ROCKNIX SM8550 artifacts (kernel, quirks, inputplumber, firmware)
build/         # output (rootfs, image)
Makefile       # targets: sync, kernel, build, fast, install, check
```
- **Adapt from thorch:** `scripts/build-image.sh`, `build-image-fast.sh`, the `Makefile`
  target structure, and `make sync` populating `vendor/rocknix-sm8550/`.
- **Build fresh:** everything is RP6-specific config; thorch is AYN-Thor-specific.
- Builder runs `pacstrap`/`mkarchroot`-style bootstrap of the ALARM aarch64 tarball (pin
  `ALARM_ROOTFS_SHA256` for hermetic builds, as thorch does), then installs packages from
  Arch ALARM repos + Valve `holo-core-aarch64-preview` + local `packages/`.

### Phase 1 — Kernel built in-project (`linux-pocknix`)
The kernel lives in and is built by pocknix-os — a full OS owns its kernel. We vendor the
source + RP6 enablement and reproduce the `qcom-abl` boot-image packaging in a PKGBUILD.

**Why this is its own toolchain (not just a pacman install):** building the kernel means
*cross-compiling C source* (kernel + DTBs) and then wrapping it Android-style — a different
process from `pacstrap`-ing finished packages. We replicate ROCKNIX's packaging steps inside
an Arch PKGBUILD instead of inside the LibreELEC buildroot.

- **Committed in-repo** under `kernel/` (done in Phase 0 via `make sync`; more self-contained
  than thorch). The kernel reproduces ROCKNIX's recipe exactly — **stock kernel.org 7.0.11**
  (pinned) + the **full ROCKNIX patch stack in order**: `10-mainline/` (5 generic backports)
  → `20-sm8550/` (61 device: suspend/resume, RP6 panel, RSInput, TSENS) → `30-version/` (2),
  then the SM8550 config (`linux.aarch64.conf`) + qcom-abl packaging. NOT just stock+device
  patches. **Stock Linux source** is fetched at build as a version+sha-pinned tarball
  (`KERNEL_SOURCE_URL/SHA256`); firmware comes from `linux-firmware` per `kernel-firmware.dat`.
  This is the same build thorch does — we commit the inputs (the RP6 patches aren't public,
  so they can't be auto-fetched the way thorch pulls public ROCKNIX).
- **`packages/linux-pocknix/PKGBUILD`** reproduces the boot-image build, porting the logic
  from ROCKNIX `packages/linux/package.mk` + `bootloader/mkimage`:
  1. apply patches, build with the cross toolchain → `Image` + DTBs,
  2. gzip the kernel and concatenate the DTBs,
  3. `mkbootimg` into the `qcom-abl` Android boot image,
  4. emit the boot image (→ `/flash/KERNEL`) and the `lib/modules/<ver>/` tree (→ rootfs
     `/usr/lib/modules/`). Model on thorch's `linux-thorch` package.
- **Modules:** ship the matching `lib/modules/<ver>/` in the rootfs; keep `uname -r` aligned.
  Honor the **kernel-overlay** mechanism (runtime overlays in
  `/storage/.cache/kernel-overlays/`, ref ROCKNIX `kernel-overlays-setup`) for dev iteration.
- **Firmware:** ship `linux-firmware` + the SM8550 firmware list
  (`devices/SM8550/config/kernel-firmware.dat`: Adreno/WiFi/BT), plus
  `0501-...fix-wifi-and-bt-mac`.
- `make kernel` builds only `linux-pocknix` (fast kernel-only iteration), mirroring the
  SM8550 README's `make docker-package PACKAGE=linux` workflow.

### Phase 2 — Hardware enablement (SM8550 quirks)
Port ROCKNIX SM8550 device integration into a `pocknix-bsp` / `pocknix-quirks` package:
- **InputPlumber** configs: `devices/SM8550/filesystem/usr/share/inputplumber/` (RSInput MCU
  capability maps, controller device YAMLs). Critical for gamepad → Steam Input.
- **Suspend/resume** hooks (the user's specialty): `sleep.d/{pre,post}` quirks incl. the
  SDAM breadcrumb debug hooks; the kernel-side fixes are already in `/flash/KERNEL`.
- Audio UCM, thermal, CPU/GPU governor hints.
- **Adapt from ROCKNIX/thorch:** quirks platform tree + `thorch-rocknix-quirks` packaging.

### Phase 3 — Session 1: Steam (gamescope + native ARM client)
- **Packages from holo `holo-core-aarch64` (no source build):** `gamescope`, native `steam`
  ARM runtime, `mangohud`/`mangoapp`. **`mesa` comes from Arch Linux ARM**, not holo (holo's
  mesa lags upstream stable) — gamescope/Steam link against the ALARM mesa.
- **Launch logic — adapt directly from ROCKNIX** `start_steam.sh` / `start_steam_arm64.sh`,
  specifically `steam_launch_bigpicture()`:
  `gamescope --backend drm -W $W -H $H -r $REFRESH --xwayland-count 2 --mangoapp
   --force-orientation <left|right> --use-rotation-shader -e -- steamrtarm64/steam
   -steamdeck -steamos3 -gamepadui ...`
  Strip ROCKNIX's EmulationStation/sway coupling (`swaymsg` geometry reads, `essway`
  start/stop, ES thunk settings); replace sway geometry probe with a direct DRM/KMS mode
  query (kernel exposes the RP6 panel mode). Keep the `force-orientation` panel-rotation
  handling — the RP6 panel is mounted rotated.
- Wrap as `pocknix-steam.service` (or a `systemd-run --scope` like ROCKNIX's
  `steam-bigpicture.scope`).
- **Defer:** FEX-Emu + "Proton 11.0 (ARM64)" for x86 game content. The native client and
  native ARM titles work without it; add as optional `pocknix-fex` later (ROCKNIX lets the
  user pick arm64 vs x86 flavor via the `steam_version` setting).

### Phase 4 — Session 2: Desktop (Plasma Mobile)
- **Packages from Arch ALARM repos:** `plasma-mobile`, `plasma-workspace`, `kwin`,
  `plasma-nano`/mobile shell, `maliit-keyboard` (on-screen kbd), `plasma-nm`,
  `powerdevil`, a minimal app set (Discover optional). No full Plasma desktop.
- Session entry: `kwin_wayland --drm ... plasmashell -p org.kde.plasma.mobileshell` wrapped
  as `pocknix-desktop.service`.
- Touch input: RP6 has a touchscreen panel (Synaptics/Hynitron drivers in the kernel
  patches) — Plasma Mobile is touch-first, good fit. Map gamepad to pointer where useful.
- **Build fresh** (thorch's KDE packaging is desktop-Plasma-leaning; we want mobile shell).
  Reference thorch only for which mobile packages it pulls and firstboot integration.

### Phase 5 — Session switching
- `pocknix-session-select <steam|desktop>`: persist choice to
  `/storage/.config/pocknix/session`, `systemctl stop` the active session unit, `start` the
  target. A oneshot `pocknix-session@.target` or a default-session service reads the
  persisted choice at boot.
- Expose the switch from inside each session: a "Switch to Desktop" entry in Steam's power
  menu (SteamOS does this via `steamos-session-select desktop`), and a launcher tile /
  power-menu action in Plasma Mobile that calls `pocknix-session-select steam`.
- **Adapt from ROCKNIX/SteamOS:** the `steamos-session-select` contract and the
  stop-compositor → start-other pattern, generalized.

### Phase 6 — Packaging & internal install
- `build-image.sh` produces the rootfs + populates `/flash/KERNEL` from Phase 1.
- **Internal install** (target chosen by user): an installer that writes the new root to the
  internal root partition and `/flash/KERNEL` to the FAT boot partition, **preserving the
  existing ROCKNIX `qcom-abl` bootloader and Android recovery** (do not touch ABL).
  - **Adapt from ROCKNIX** `devices/SM8550/bootloader/update.sh` (it already does
    `mount -o remount,rw /flash`, ABL update via `updateabl`) and thorch's
    `thorch-install-internal` for the partition-safe internal flow.
  - Keep a `/flash/KERNEL.bak` rollback (per the SM8550 README recovery procedure).
- `make check` validates the image (DTB presence, module/`uname -r` match) before install.

---

## Compositor recommendation (deliverable #4)

**Use `kwin_wayland` — the native Plasma Mobile compositor. Do not host Plasma Mobile in
Sway or a bare compositor.**

Rationale:
- Plasma Mobile's shell (`org.kde.plasma.mobileshell`) is architecturally bound to KWin +
  plasmashell. The upstream session literally is
  `kwin_wayland --xwayland "plasmashell -p org.kde.plasma.mobileshell"`. Running it under
  another compositor is unsupported and gains nothing.
- KWin gives the touch gestures, on-screen-keyboard activation, rotation, and screen
  management Plasma Mobile expects out of the box — exactly what a handheld touch UI needs.
- It keeps the two sessions cleanly symmetric: each session is one compositor owning DRM
  (`gamescope` for Steam, `kwin_wayland` for Desktop), switched by systemd. No nested or
  base compositor to complicate switching or input/seat handoff.
- ROCKNIX uses Sway only as a generic base under EmulationStation; we have no ES, so we drop
  the Sway base entirely rather than port it.

(Phosh = GNOME-mobile shell, a different stack — not applicable to a Plasma Mobile session.)

---

## thorch-os: adapt vs. build fresh (summary)

| Component | thorch / ROCKNIX source | Decision |
|---|---|---|
| Image builder (`build-image.sh`, Makefile, `sync`) | thorch `scripts/` + Makefile | **Adapt** — re-target RP6 |
| ALARM bootstrap + rootfs pin | thorch `ALARM_ROOTFS_SHA256` flow | **Adapt** |
| Kernel (`linux-pocknix` PKGBUILD, qcom-abl boot image) | ROCKNIX `packages/linux` + `bootloader/mkimage`, thorch `linux-thorch` | **Build fresh in-project** (vendor source) |
| SM8550 quirks / InputPlumber / suspend hooks | ROCKNIX `devices/SM8550/...`, `thorch-rocknix-quirks` | **Adapt** (RP6 DTS) |
| Steam launch (gamescope + native ARM) | ROCKNIX `start_steam*.sh` | **Adapt** — strip ES/sway |
| `gamescope`, native Steam, mangoapp | holo `holo-core-aarch64` repo | **Reuse binary** (no build) |
| `mesa` (Adreno 740 Vulkan/GL) | Arch Linux ARM repo | **Reuse binary** — *not* holo (lags) |
| Session-select mechanism | ROCKNIX `steamos-session-select` | **Adapt** — generalize to 2 sessions |
| Plasma **Mobile** packaging | thorch is desktop-Plasma | **Build fresh** |
| Internal installer (ABL-safe) | ROCKNIX `bootloader/update.sh`, `thorch-install-internal` | **Adapt** |
| FEX + Proton-ARM (x86 games) | ROCKNIX `packages/compat/fex-emu` | **Defer** (optional later) |

---

## Open questions to resolve before/within implementation

1. **holo vs ALARM ABI split (highest-risk):** holo ships its own `mesa`, `glibc`, maybe
   `systemd`. We deliberately take `mesa` from ALARM but `steam`/`gamescope` from holo — so
   those holo binaries must link against ALARM's `mesa`/`glibc` without an ABI break. Set
   pacman repo priority (ALARM first; pull only the named packages from holo) and verify by
   diffing core package versions before wiring `pacman.conf`. If holo gamescope hard-depends
   on holo mesa, fall back to building gamescope from source against ALARM mesa.
2. **Kernel toolchain (mostly resolved):** on an **aarch64 Linux build host this is moot** —
   `linux-pocknix` compiles natively with the host GCC (the config's
   `aarch64-rocknix-linux-gnu-gcc-15.2.0` string is informational; any recent GCC 15.x works),
   no cross-toolchain or ROCKNIX Docker container. Only on an x86_64 host do we need an
   aarch64 cross-toolchain. Remaining: confirm `mkbootimg`/qcom-abl params match what the RP6
   ABL expects (README: gzip kernel + concatenated DTBs).
3. **DRM mode query without sway:** ROCKNIX reads geometry via `swaymsg`. We need a
   sway-free way to get the RP6 panel mode/refresh/rotation for the gamescope args (e.g.
   `drm_info`, libdisplay-info, or a fixed RP6 profile from the DTS). Confirm panel
   native res/rotation from `qcs8550-retroidpocket-rp6.dts`.
4. **Native ARM Steam provenance:** confirm exactly which package/repo provides
   `steamrtarm64` (holo repo vs ROCKNIX `Install Steam.sh` runtime download) and its
   update channel, so the build is reproducible rather than a runtime curl.
5. **Internal partition layout:** confirm the RP6's existing ROCKNIX partition scheme
   (FAT `/flash`, ext4/squashfs root, `/storage`) so the installer reuses it. ROCKNIX root
   is squashfs+overlay; we want a writable Arch ext4 root — verify the bootloader/cmdline
   accepts a plain ext4 root.
6. **Adreno 740 Vulkan on ALARM mesa:** we chose ALARM `mesa` (Turnip) over holo — validate
   on-device that it gives working Vulkan for *both* gamescope and Plasma, and that holo
   `gamescope` runs against it (ties into open question #1).
7. **Steam scope confirmation:** native client only for v1 (FEX/Proton deferred) — confirmed
   in principle; revisit once the client boots, since most Steam library titles are x86.

---

## Verification (end-to-end)

1. **Build:** `make sync && make kernel && make build` produces `build/` rootfs + boot image
   with no errors; `make check` passes (DTB present, `uname -r` ↔ shipped modules match).
2. **Kernel sanity (per SM8550 README):** after install, `md5sum /flash/KERNEL` matches the
   built `Image`; `cat /proc/version` shows the expected build host/timestamp.
3. **Boot:** device boots to the default session; `journalctl -b` clean of unit failures.
4. **Steam session:** `pocknix-session-select steam` → gamescope Big Picture appears on the
   RP6 panel at native res/orientation; gamepad navigates UI (InputPlumber mapping works);
   `mangoapp` overlay renders; a native ARM title launches.
5. **Desktop session:** `pocknix-session-select desktop` → Plasma Mobile shell on
   `kwin_wayland`; touchscreen + on-screen keyboard work; WiFi via plasma-nm.
6. **Switching:** round-trip steam↔desktop ≥3× with no DRM/seat lockup; choice persists
   across reboot.
7. **Suspend/resume:** suspend in each session, resume; verify with the SDAM breadcrumb
   (`dd ... skip=80`) that kernel PM completed, and that the compositor restores display +
   input.
8. **Rollback:** confirm `cp /flash/KERNEL.bak /flash/KERNEL` recovery still works and the
   ROCKNIX ABL/Android recovery is untouched.
