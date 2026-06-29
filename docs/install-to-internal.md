# Install pocknix-os to internal storage (and uninstall)

The RP6 runs much faster from the internal UFS than from an SD card. `pocknix-install-internal`
clones a **running SD install** onto internal storage; `pocknix-uninstall-internal` reverses it.

Both scripts live in the image at `/usr/local/bin/` (overlay), run **on the device**, and never touch
`abl`/`xbl`/`modem`/`persist`/`super` — only Android's `userdata` (shrunk) plus the two pocknix
partitions they add (`ROCKNIX` FAT boot + `POCKNIX_ROOT` ext4). For the exact boot-partition layout
and *why* it must be what it is, see the `rp6-internal-boot` memory.

> ⚠️ This repartitions the disk Android lives on. It shrinks `userdata` (wipes Android user data) but
> leaves Android itself bootable. **Always `--dry-run` first and read the printed plan.**

---

## Install to internal

You must be **booted from the SD** (the installer clones the *running* system to internal).

```bash
# 1. dry-run — prints the exact partition plan, makes NO changes. Review it.
pocknix-install-internal --dry-run

# 2. for real. It asks for the new Android userdata size (or pass --userdata-gib N),
#    then shrinks userdata, creates ROCKNIX (boot) + POCKNIX_ROOT (root), and rsyncs the
#    running rootfs across (the clone is the slow part — minutes off a slow SD).
pocknix-install-internal
#   non-interactive equivalent:
#   pocknix-install-internal --yes --userdata-gib 16

# 3. power off, REMOVE THE SD CARD, power on → it boots internal.
```
Flags: `--dry-run`, `--yes`/`-y`, `--userdata-gib N`, `--device /dev/sdX` (default `/dev/sda`).

**Remove the SD before booting internal.** Internal boots first, and with the SD still in there are two
`POCKNIX_ROOT` partlabels — the kernel's `root=PARTLABEL=POCKNIX_ROOT` would be ambiguous.

---

## Uninstall from internal

You **can't repartition the disk you're booted from**, so this is two stages:

```bash
# Stage 1 — run FROM the internal install: drop only the ROCKNIX boot FAT so the ABL stops
#           booting internal. POCKNIX_ROOT is left intact.
pocknix-uninstall-internal --disable-boot
#   then power off and boot — it comes up on the SD.

# Stage 2 — run FROM the SD: remove the leftover POCKNIX_ROOT and grow Android userdata back
#           to fill the disk (Android reformats userdata on its next boot).
pocknix-uninstall-internal --dry-run     # review
pocknix-uninstall-internal
```
Flags: `--disable-boot`, `--enable-boot`, `--dry-run`, `--yes`/`-y`, `--device /dev/sdX` (default
`/dev/sda`). The full (Stage 2) uninstall refuses to run if `/` is on the target device, as a guard.

(Alternative to Stage 1: the ABL menu's **"Uninstall ROCKNIX"** also removes the boot partition, since
ours is GPT-named `ROCKNIX`.)

---

## Temporarily boot the SD *without* uninstalling (e.g. to test ROCKNIX)

> **You cannot disable the internal boot by renaming the partition.** Tested on-device: renaming
> *both* the GPT name and the FAT label (`ROCKNIX` → `PNXOFF`) left the device still booting
> internal. **The RP6 ABL boots the internal boot FAT by its existence, not its name/label** — the
> only way to make it boot the SD is to *remove* the boot FAT. (`POCKNIX_ROOT` is left intact, so
> your install survives — this only drops the small boot partition, which `--enable-boot` rebuilds.)

So use the same flags as the uninstall flow:

**Disable** — from the internal pocknix (drops only the boot FAT; `POCKNIX_ROOT` stays):
```bash
pocknix-uninstall-internal --disable-boot
#   power off, LEAVE THE SD IN, power on → it boots the SD (e.g. ROCKNIX)
```

**Re-enable** — `--enable-boot` recreates the boot FAT and regenerates `/flash/KERNEL` from the
intact `POCKNIX_ROOT` (no 27 GB re-clone). It chroots the internal rootfs, so it needs a **booted
pocknix** — run it from a pocknix SD (ROCKNIX doesn't carry pocknix's scripts):
```bash
# boot a pocknix SD, then:
pocknix-uninstall-internal --enable-boot
#   power off, REMOVE the SD, power on → boots internal pocknix again
```
Both accept `--dry-run`. Neither touches Android or `POCKNIX_ROOT`. (If you already renamed the boot
partition before reading this, its name won't be `ROCKNIX` so `--disable-boot` won't find it — just
delete it directly: `parted -s /dev/sda rm <N>`, where `<N>` is the 512 MiB boot FAT from
`lsblk -o NAME,SIZE,LABEL /dev/sda`.)

---

## Put a *new* version on internal (clean reinstall)

```
Stage 1 (internal: --disable-boot) → reboot → boot a FRESH SD image (with your new build)
  → Stage 2 (from the new SD: removes POCKNIX_ROOT so the installer's idempotency check passes)
  → pocknix-install-internal   (clones the fresh SD onto internal)
```

For just iterating on packages/scripts you usually don't need to reinstall — deploy onto the running
internal system with `scp …pkg.tar.* && pacman -U …` (see `conventions.md`).
