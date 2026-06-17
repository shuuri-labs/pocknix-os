# Testing pocknix-os in a Fedora VM (Apple Silicon)

How to build and smoke-test pocknix-os in a **Fedora aarch64** VM on an Apple Silicon Mac
(M1/M2/M3). aarch64 is the right choice: it runs **natively** (no qemu emulation) and matches
the build target, so package install and the kernel compile run at full speed.

> What's testable in the VM: the **build pipeline** (bootstrap → base packages → kernel →
> boot image). What is **not** testable here: actually booting on the RP6 (needs the device).

## 1. Create the VM (UTM)

[UTM](https://mac.getutm.app/) is the free standard on Apple Silicon (uses Apple's
Virtualization framework for native ARM).

1. `brew install --cask utm` (or download from the site).
2. Get **Fedora aarch64** (Server or Workstation, "ARM aarch64") from getfedora.org.
3. New VM → **Virtualize** → Linux → the Fedora ISO. Resources: **4+ CPUs, 8 GB RAM, 60 GB
   disk** (rootfs build ≈ a few GB; kernel source + build tree adds ~2–3 GB more).
4. Install Fedora, reboot, log in.

> Parallels / VMware Fusion work too — just ensure the guest is **aarch64**, not x86.

## 2. Install dependencies

```bash
# image build (chroot/bootstrap/packages)
sudo dnf install -y git make curl rsync bsdtar

# kernel build (make kernel)
sudo dnf install -y gcc bc bison flex openssl-devel elfutils-libelf-devel \
                    perl python3 xz gzip diffutils

# SD boot-test image (make sd-image)
sudo dnf install -y parted dosfstools e2fsprogs util-linux
```
`bsdtar` (libarchive) preserves the ALARM tarball best; gnu `tar` is the fallback. No
`qemu-user-static` is needed on aarch64.

## 3. Get the code

```bash
git clone https://github.com/shuuri-labs/pocknix-os.git
cd pocknix-os
```
The RP6 kernel inputs are committed under `kernel/`, so a clone has everything custom; only
stock upstream Linux + stock firmware are fetched at build.

## 4. Preflight (no root)

```bash
make check
```
Expect `host os → Linux ok` and `kernel: enablement → 68 patches`.

## 5. Build the base rootfs

```bash
sudo -E make build      # -E passes exported vars (e.g. POCKNIX_ALARM_SHA256) through sudo
```
This bootstraps the ALARM aarch64 rootfs, inits the keyring, and installs the base packages
(ALARM repos only in Phase 0). Success ends with:
```
ok  build-image: base rootfs built at .../build/rootfs (later phases stubbed)
```
Verify:
```bash
sudo chroot build/rootfs uname -m                       # aarch64
sudo chroot build/rootfs pacman -Q | wc -l              # ~130+
sudo chroot build/rootfs pacman -Q mesa networkmanager pipewire vulkan-freedreno
```
For a reproducible build, pin the rootfs:
```bash
export POCKNIX_ALARM_SHA256=$(sha256sum build/cache/ArchLinuxARM-aarch64-latest.tar.gz | cut -d' ' -f1)
sudo -E make build
```

## 6. Build the kernel + qcom-abl boot image

```bash
sudo make kernel   # native compile — long; produces build/image/KERNEL + build/kernel/out
make check         # should now show: kernel build <ver> + boot image KERNEL <size>
```
> Use `sudo` here because `build/` is root-owned after `sudo make build` (so a non-root
> `make kernel` can't write the download cache). The compile itself doesn't require root.
This fetches stock `linux-7.0.11`, applies the patch stack in order, builds Image+dtbs+modules,
and assembles the qcom-abl boot image (gzip Image + appended DTBs + dummy ramdisk). See
[`../kernel/README.md`](../kernel/README.md) for the recipe. Pin the source afterward:
```bash
sha256sum build/cache/linux-7.0.11.tar.xz    # put this in config/pocknix.conf KERNEL_SOURCE_SHA256
```

## 6b. Build + flash the SD boot-test image

Boot-test the kernel on the RP6 **without touching internal ROCKNIX**. The image mirrors
ROCKNIX's qcom-abl SD layout (GPT: fat32 `system`/`ROCKNIX` with `KERNEL`, ext4 `POCKNIX_ROOT`
with the rootfs) so the device's existing ABL boots it.

```bash
sudo make build      # ensure the rootfs exists AND has the pocknix kernel modules
sudo make kernel     # ensure build/image/KERNEL exists
sudo make sd-image   # -> build/image/pocknix-sd.img
```
> `make sd-image` also re-syncs the pocknix modules into the rootfs and drops the generic
> `linux-aarch64`, so it's fine if you ran `make build` before the kernel existed.

Flash to the microSD (in the VM, pass the USB SD reader through to the guest; or copy the
`.img` to the Mac host and flash there with Balena Etcher / `dd`):
```bash
lsblk                              # find the SD device — e.g. /dev/sdb. DO NOT pick your disk.
sudo dd if=build/image/pocknix-sd.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

Insert into the RP6 and power on (if it boots internal ROCKNIX instead, use the boot menu —
hold **Vol‑** at power-on). **Boot signals to look for**, in order:
1. Kernel log scroll on the screen (console=tty0) — proves the ABL loaded our KERNEL.
2. A `login:` prompt — proves systemd came up and root mounted (`root=PARTLABEL=POCKNIX_ROOT`).
   Log in as `root` / `pocknix`.
3. `uname -a` shows our kernel; `cat /proc/cmdline` shows our cmdline; `lsblk` shows the SD.
4. SSH: if Wi-Fi/USB networking is up, `ssh root@<ip>`.

### Interacting with it (the RP6 has no keyboard)

The image bakes in three no-keyboard paths (`overlay/`, enabled by `build-sd-image.sh`):

- **SSH over USB-C (recommended).** `pocknix-usbgadget` brings up a CDC-NCM network gadget at
  **`10.66.0.1`**. **Connect the USB-C cable to your computer *before* powering on** (so the
  USB controller is in device mode at boot). The RP6 then appears as a USB ethernet interface:
  - macOS: System Settings → Network → the new USB interface → Configure IPv4 **Manually**,
    IP `10.66.0.2`, mask `255.255.255.0`. Then `ssh root@10.66.0.1` (pw `pocknix`).
- **Diagnostic dump (zero interaction).** `pocknix-diag` writes **`pocknix-diag.txt` to the FAT
  boot partition** ~8 s after boot. Power off, put the SD in your Mac/VM, and read that file —
  it has `uname`, `/proc/cmdline`, root mount, `lsblk`, suspend support, input devices, and the
  `dmesg` errors/warnings. This works even if the gadget doesn't.
- **Console autologin.** tty1 auto-logs-in as root (useful only if you later attach a USB
  keyboard in host mode).

> The "initramfs unpacking failed" line during boot is **expected and harmless** — we ship no
> initramfs (UFS/ext4 are built in); the kernel mounts root directly via `root=PARTLABEL=`.

To go back to ROCKNIX: power off, remove the SD. Internal is untouched.

### If it doesn't boot
The biggest unknown is whether the ABL accepts our SD KERNEL. If you get nothing:
- Confirm your unit boots an **official ROCKNIX SD image** at all (sanity check the SD path).
- Compare partition names/labels against a real ROCKNIX SD (`sudo gdisk -l`, `lsblk -f`) — the
  ABL may key off a specific name/label/GUID we need to match. Paste findings and we adjust.
- A bad boot can't hurt internal ROCKNIX (we never wrote to it).

## 7. Cleanup

```bash
make clean       # removes rootfs/image/localrepo/kernel build, keeps the download cache
make distclean   # also removes the cache
```

## Gotchas (already handled — here so they're not a surprise)

| Symptom | Cause / fix |
|---|---|
| `Could not resolve host` for every repo during `make build` | systemd-resolved stub `127.0.0.53` in the chroot. Handled by `lib.sh chroot_resolv` (uses real upstream resolvers, public DNS fallback). |
| `could not determine cachedir mount point / not enough free disk space` (with ample space) | pacman `CheckSpace` can't resolve mounts in a chroot. We omit `CheckSpace` in `pacman.conf.in`. |
| `holo`/`pocknix` repo DB download fails | Intentional in Phase 0 — base install is ALARM-only; those repos are added in Phase 3+. |
| `POCKNIX_ALARM_SHA256 is unset` warning under sudo | `sudo` drops env; use `sudo -E make build` to pass it through. |
| mkinitcpio warnings (autodetect/microcode/kms) during base build | Benign chroot/arch artifacts from the generic `linux-aarch64`; Phase 1 removes that kernel. |
| `tar: Ignoring unknown extended header keyword 'LIBARCHIVE.xattr...'` | Harmless; install `bsdtar` to silence. |

## Host requirements recap

Linux host, **root for `bootstrap`/`build`/`fast`/`kernel`** (chroot/compile);
`help`/`check`/`sync` run as your normal user. aarch64 host strongly preferred (native).
