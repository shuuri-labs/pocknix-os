# pocknix-os — progress & resume notes

Working notes for picking this back up after a break. For the *why* behind decisions, see
[`plan.md`](plan.md); for *how to run it*, see [`README.md`](README.md); for VM setup +
testing, see [`docs/testing-fedora-vm.md`](docs/testing-fedora-vm.md). This file tracks
**where things stand and what to do next**.

_Last updated: 2026-06-19 — Phase 3: native ARM Steam re-aligned to armada (channel + CWD fixes)._

---

## 🎉 MILESTONE: Steam Big Picture RENDERS on the RP6 (native ARM, NO FEX) — 2026-06-19
`pocknix-steam` brings up **native ARM64 Steam gamepadui under gamescope on the panel.** The whole
gamepadui chain was a sequence of single missing native-ARM deps / config deltas vs armada — each
found by reading armada's real source + `ldd ... | grep 'not found'`, none needing FEX:

| Symptom | Cause | Fix |
|---|---|---|
| `CreateGlFont … failed` (missing fonts) | wrong client channel (plain `publicbeta`) | **`steamdeck_publicbeta`** channel (ships Big-Picture font payload) |
| `execl errno 2` (`steam_msg.sh`) | missing `~/.steam/root` | add **`.steam/root`** symlink |
| `Could not load module 'bin/vgui2_s.dll'` | `vgui2_s.so` DT_NEEDED `libopenal.so.1` unresolved (+ CWD) | dep **`openal`**; `cd steamrtarm64` (getcwd-relative module load) |
| steamwebhelper CEF crash (`Failed creating offscreen shared JS context`) | `steamwebhelper`/`libcef.so` DT_NEEDED `libcups.so.2` | dep **`libcups`** |
| `Failed to connect to websocket` (+ `lsof: command not found` spam) | Steam shells to `lsof` to find webhelper's CEF port | dep **`lsof`** |

Also matched armada's launch flags exactly: `-gamepadui -steamos3 -steampal -steamdeck -noverifyfiles`
(dropped ROCKNIX's `-nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders`). The
**native arm64 steamwebhelper EXISTS** (`steamrtarm64/steamwebhelper` is aarch64) and runs native —
**FEX is NOT needed for the client or the UI** (only later for x86 *game* content / Proton). Deps
now in `pocknix-steam` PKGBUILD: openal, libcups, lsof (+ gtk2, gdk-pixbuf2). Commits 474491b →
2229a5b → 948072b → 4e3dbdf → 4bb306a. `steam-native-arm-status.md` SUPERSEDED (its x86/FEX-runtime
hypothesis was wrong end to end).

**RESOLVED post-launch (2026-06-19):**
- **Setup-wizard Wi-Fi "no connections found"** → FIXED. Steam enumerates Wi-Fi via **NetworkManager
  over D-Bus**; we ran iwd-direct (NM disabled). Re-plumbed to **NM front-end + iwd backend**
  (`wifi.backend=iwd`, NM keyfile creds, iwd `EnableNetworkConfiguration=false`). Verified LIVE:
  `nmcli device status` → `wlan0 wifi connected`. Baked into `build-sd-image.sh`; static confs from
  `overlay/` (20-wifi-backend.conf + 10-unmanage-gadget.conf). See [[steam-network-nm-iwd]].
- **CJK fonts (tofu)** → `noto-fonts`/`-cjk`/`-emoji` deps.
- **Boot session** → `overlay/root/.bash_profile` execs `pocknix-steam` on tty1 autologin (real PAM
  session = XDG_RUNTIME_DIR + per-user PipeWire/audio); guarded to tty1+non-SSH; `touch /root/.no-steam`
  to boot to a shell. (Chose this over a systemd unit so Steam gets a user session for audio.)
- Benign noise (ignore): `steam-runtime-launcher-service not found` (present in tree, Steam disables
  it + continues), `steamrtarm32/*driverquery` (we only have arm64), `steamos-select-branch` /
  `lsb_release` / `steamos-polkit-helpers/*` (SteamOS-only helpers), `pipewire pw_context_connect`.

**STILL TODO:** (1) **rebuild `pocknix-steam` in the VM** so the new deps (openal/libcups/lsof/noto*/
networkmanager) are declared + pulled on a clean install/image (they were hand-`pacman -S`'d for
iteration). (2) On-device **validate the boot session** end-to-end (audio in-session, gamepad, seat
hand-off from getty). (3) First-boot **root-fs expand** service (64GB SD had 4.1G partition).

**Phase 3b — x86 game content via FEX + Proton (deferred, scoped):** native client/UI need NO FEX;
**x86 games (Proton 11 ARM) DO** — Proton is NOT self-contained, FEX is OS-level. Need FEX **with
thunks** + an **x86 rootfs** + **binfmt** + native-Vulkan (Turnip) passthrough + the **CachyOS Proton
11 arm64** build + a per-game FEX-config shim. Full scoped plan + ROCKNIX-vs-armada reference table:
[`docs/fex-proton-plan.md`](docs/fex-proton-plan.md). Crux/risk = the thunk build (ROCKNIX needs nix;
generic distro FEX lacks thunks).

## Phase 3 — native ARM client journey (how we got to the milestone)
What's validated on-device (2026-06-19):
- **gamescope** (ROCKNIX-patched, `packages/gamescope`) drives the RP6 panel — `pocknix-steam`
  launches it with `--force-orientation left --use-rotation-shader`, fixed 1920x1080@120.
- **Native ARM64 Steam** downloads + runs as aarch64 (`packages/pocknix-steam`): the installer
  fetches the steamrt3c ARM64 runtime + the linuxarm64 client into `~/.local/share/Steam/steamrtarm64`.
- **steamui.so + all libs load** after fixes: built **gtk2** (`packages/gtk2`, EOL in Arch),
  `gdk-pixbuf2` from ALARM, **`steamrtarm64/` first on `LD_LIBRARY_PATH`** (bundled libvpx.so.6
  etc.), `seatd` for the seat.

**The `-gamepadui` fatals (`CreateGlFont failed` + `Could not load module 'bin/vgui2_s.dll'` +
`execl errno 2`) were NOT FEX/runtime problems.** Reading armada's ACTUAL source
(`gh api repos/virtudude/armada/contents/build_files/generate-steam-bootstrap.sh` +
`system_files/usr/libexec/armada/launch-steam`) — not the secondhand summary in
`steam-native-arm-status.md` — surfaced the real deltas (commit `474491b`):
- **Wrong client channel.** We pulled plain `publicbeta`; armada pulls **`steamdeck_publicbeta`**,
  which ships the Steam Deck Big-Picture UI payload (updater **fonts** + vgui assets). → fixes
  `CreateGlFont`. `package/beta` + manifest name now use `steamdeck_publicbeta`.
- **Wrong CWD.** Steam loads `bin/vgui2_s.dll` **relative to getcwd**. armada `cd`s into
  `steamrtarm64/`; we were `cd`-ing to `$HOME`. → fixes "Could not load module".
- **Missing `.steam/root` symlink.** Steam execs `$HOME/.steam/root/steam_msg.sh`. → fixes
  `execl errno 2`. (Also reverted a wrong-turn LDLP removal — armada keeps steamrtarm64 first.)
- Dropped the `registry.vdf`/OOBE seed I'd tried — armada deliberately *removes* registry.vdf
  from its seed, so it was an untested confound.

**NEXT: on-device test** (build in Fedora VM → scp pkg → `pacman -U` → `rm -rf ~/.local/share/Steam
~/.steam` to force re-pull from the new channel → `pocknix-steam-install` → `pocknix-steam`).
Verify `package/beta` == `steamdeck_publicbeta` and the `*.installed` manifest appears. If the
fonts/vgui fatals are gone, Steam is unblocked. `steam-native-arm-status.md` is now partly
SUPERSEDED (its "x86 runtime mis-selection" hypothesis was wrong — it was channel + CWD).
holo aarch64 repo: gamescope yes, steam no (client = Valve CDN). Packages:
gamescope, gtk2, inputplumber, pocknix-bsp, pocknix-steam.

Build-system note: `build-packages.sh` now wires a `[pocknix]` repo into the build chroot so
local packages can depend on each other; `make packages PKG="a b"` builds a subset.

## 🎉 MILESTONE: Steam-session compositor renders on the GPU (Phase 3)
`gamescope --backend drm --force-orientation left --use-rotation-shader -- vkcube` shows the
spinning cube **on the RP6 panel** (`right` rendered upside-down → use `left`). Full GPU stack
is up. Chain of fixes that got us here:

1. **GPU firmware** — `a740_sqe.fw` + `gmu_gen70200.bin` from `linux-firmware-qcom`. The kernel
   couldn't load it because the built-in `msm` driver probes **before the rootfs mounts** (no
   initramfs). Fix: build **`DRM_MSM=m`** (loads post-root via udev) — see build-kernel.sh.
   GMU firmware v4.1.9 loads; `/dev/dri/card0` + `renderD128` present.
2. **Vulkan** — `vulkaninfo` shows **`Turnip Adreno (TM) 740`** on ALARM mesa. Confirmed.
3. **gamescope** — vanilla (ALARM 3.16.24) **cannot** drive the RP6 panel: it's mounted rotated
   (DTS `rotation=<270>`) so gamescope sets a DRM **plane rotation** the `msm` DPU rejects →
   endless `Failed to prepare 1-layer flip (Invalid argument)` (upstream #1883/#819). Fix:
   **build ROCKNIX's patched gamescope** (`packages/gamescope`, commit `fe78bc6` + 4 patches);
   patch `0005` adds **`--use-rotation-shader`** (rotate in a compute shader, no plane-rotation
   property) → flip accepted. Build needed `makepkg -s` (chroot sudo), wlroots build-deps
   (xwayland, libdisplay-info, xcb-util-*), and a blanket **`-Wno-error`** (ALARM libs newer
   than the pinned wlroots' CI).

Seat: gamescope needs **seatd** running (`systemctl enable --now seatd`) — over SSH there's no
logind seat. DNS on-device fixed too (iwd → systemd-resolved).

Image wiring **DONE**: `install_local_packages` installs our epoch=1 gamescope; gamescope dropped
from steam.list; seatd enabled. Confirmed orientation: **`--force-orientation left`** (right is
upside-down). Next full `make build && make sd-image` bakes it all in.

---

## 🎉 MILESTONE: Phase 2a (controller) + 2b (audio) working
Tested on-device (verified by `make packages PKG=...` + on-device `pacman -U`).

**Phase 2a — InputPlumber: DONE.** `packages/inputplumber` (prebuilt aarch64 release v0.75.2,
same as ROCKNIX — no Rust build). `pocknix-bsp` ships `01-rsinput-rp6.yaml` (CompositeDevice
matching the RSInput gamepad `phys rsinput-gamepad/input0`, target ds5+keyboard; the RSInput
driver emits standard evdev codes so NO capability_map needed). On-device: a **virtual DualSense
appears** + inputplumber active. Enabled in the image. (Button-correctness gets a final check
once Steam runs; tweak `01-rsinput-rp6.yaml` if needed.)

**Phase 2b — Audio: working (one caveat).** The RP6 card reports as **`AYN-Odin2`** (DTS reuses
the Odin2 sound model). ALARM's alsa-ucm-conf has no matching UCM, so we ported ROCKNIX's
AYN-Odin2 UCM (`pocknix-bsp`: `AYN-Odin2.conf` + `HiFi.conf` + `conf.d/sm8550/AYN-Odin2.conf`).
**Speaker + headphone output both confirmed audible** via `alsaucm -c 0 set _verb HiFi` +
`speaker-test`. pipewire/pipewire-pulse/wireplumber enabled `--global` (WirePlumber auto-applies
the UCM). 
- **UCM-match gotcha:** `alsaucm -c AYNOdin2` fails `-2` (a bare id-string isn't opened as a
  card); `alsaucm -c 0` works — UCM matches `conf.d/sm8550/${CardLongName=AYN-Odin2}.conf`.
  PipeWire opens cards properly, so it matches.
- **KNOWN ISSUE (parked, hardware) — headphones are effectively mono.** Each amp works + carries
  the right channel individually (HPHR off → left plays; both on → right dominates), but each
  drives both ear cups. Codec routing verified correct + Class-H toggle didn't help → it's the
  **RP6 headphone analog path** (the card impersonates an AYN Odin2 but the HP wiring differs).
  Hardware/DTS follow-up, not a UCM fix. Speaker stereo is fine. Not a blocker.

**Phase 2c (deferred):** fan (ROCKNIX `0500-set-boot-fanspeed` — does the RP6 have one?),
CPU/GPU governors, thermal.

**Then finish Phase 3:** native ARM Steam client (`steamrtarm64`, provenance = open Q#4) +
`pocknix-steam` systemd session (gamescope launch from ROCKNIX `start_steam.sh`, minus ES/sway,
with `--force-orientation left --use-rotation-shader` + panel mode from DRM not swaymsg).

---

## 🎉 MILESTONE: kernel boots + runs on the RP6 (from SD), verified by diag
`pocknix-sd.img` boots on real hardware (`pocknix login`). The first-boot diag confirmed:
our 7.0.11 kernel (built root@fedora), `root=PARTLABEL=POCKNIX_ROOT` → `/dev/mmcblk0p2` ext4
(no initramfs), modules 7.0.11, gamepad `js0`, and **`mem_sleep: s2idle [deep]`** (deep
suspend available). Login root / `pocknix`.

Firmware finding (from diag): device firmware was missing → wifi (`ath12k board-2.bin`), audio
(`adsp/cdsp`), video (`vpu`) failed. ROCKNIX's synced overlay (`vendor/`) has those; we now
`install_firmware` them into the rootfs in build-sd-image.sh. GPU `a740_*` + `regulatory.db`
still missing (come from upstream `linux-firmware`/`wireless-regdb`) — follow-up; not needed
for boot. Benign noise: dummy regulators, `disp_cc` WARN, GPT alt-header (image < SD size,
`sgdisk -e` to fix). USB gadget needs a USB-C **data** cable (user lacks one) → using **Wi-Fi
pre-seed** (`SD_WIFI_SSID/PSK`) for SSH instead.

**DONE:** SSH over wifi works, and **deep suspend/resume verified on hardware** (`PM: suspend
entry (deep)` → ~3.5 s asleep → `PM: suspend exit`, SSH survived). The maintainer's TSENS
patch is confirmed active (`leaving TSENS uplow IRQ … as non-wakeup`). `pm_wakeup_irq=21`
(= `pmic_pwrkey`, power button).

**Known issue — spurious deep-sleep wake (battery, ~3.5s):** the `battery` wakeup source (in
debugfs `wakeup_sources` but NOT `/sys/class/wakeup/` → a **virtual** source via pmic_glink /
ADSP charger fw) wakes the SoC. `power/wakeup` is the WRONG knob — disabling it on all
power_supply class devices AND all device-backed `/sys/class/wakeup/` sources (except pwrkey)
did NOT stop it. The udev rule was removed (pocknix-bsp pkgrel 3). **A ROCKNIX tester
(MonsterRider) reports the fix is userspace via `standby-wake-filter`** (tsensors=kernel, done;
battery/charging/charger-detect/gpio=userspace). **Action: get the exact `standby-wake-filter`
path/command, then apply it in pocknix-bsp's sleep.d/pre hook.** Likely userspace, NOT kernel.
See `docs/sm8550-suspend-wake-report.md`. Not a distro blocker.

Wifi saga resolution (for the record): needed (1) device firmware overlay (ath12k board-2.bin
etc.), (2) regulatory **Country** set for 5 GHz (db present ≠ domain set), (3) provision **iwd
directly** (`/var/lib/iwd/<SSID>.psk`) not via NM, (4) **disable NM** so it doesn't hijack
iwd's netconfig — iwd does its own DHCP (`EnableNetworkConfiguration`). All in build-sd-image.sh.

Next: Phase 2 (pocknix-bsp: firmware/inputplumber/suspend hooks as a package), longer-soak
suspend testing (60 s+, multiple cycles, SDAM breadcrumb), then sessions. The kernel side
(Phase 1) is validated end-to-end on hardware.

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
- **Phase 1 (kernel): COMPILES + pinned** — `make kernel` builds patched 7.0.11 reproducibly
  → `build/image/KERNEL` (qcom-abl) + modules. `KERNEL_SOURCE_SHA256` pinned.
- **First-boot milestone (in progress):** `make sd-image` builds a flashable SD image.
  **IMPORTANT device fact (verified):** the RP6 boots **internal ROCKNIX first and ignores the
  SD** while an internal install exists — even an official ROCKNIX SD won't boot over it. No
  SD-priority toggle exists; "Switch boot mode" only flips Android⇄ROCKNIX. To SD-boot you must
  ABL → **Uninstall ROCKNIX** first; restore later via official SD + `installtointernal`
  (SD-only, no PC/EDL). So SD testing is NOT "leave internal untouched" — but it's reversible.
  **Next: uninstall internal → boot official SD (confirm + capture layout) → flash + boot ours.**
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
| 1 | `build-kernel.sh` → qcom-abl `KERNEL` + modules; rootfs integration | ✅ compiles in VM; sha256 pinned; on-device boot pending |
| 1.5 | `build-sd-image.sh` → flashable SD boot-test image | ✅ BOOTS + WiFi/SSH + **deep suspend/resume verified on HW** |
| 2 | `pocknix-bsp` pkg (suspend sleep.d + SDAM + wakeup udev rule) ✅; firmware → rootfs build ✅; makepkg flow ✅ | ✅ core done; inputplumber/audio/thermal = polish (or Phase 3) |
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
