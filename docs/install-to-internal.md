# Install pocknix-os to internal storage (and uninstall)

> **Install OpenABL first** if you have not already: see the [install guide](install.md).
> pocknix needs it to boot, and it is what makes switching between the internal install and the
> SD card a menu choice.

## The OpenABL menu

Everything below is driven from the bootloader menu, so it is worth knowing first. **Hold Volume −**
while powering on to open it. **Volume keys move through the entries** and the **power key
selects**. The settings this guide uses:

- **Boot mode** - what boots by default: **Linux** or **Android**.
- **Boot source** - which disk Linux boots from: **Auto** (internal storage first, then the SD
  card), **Internal**, **SD card** or **USB**.
- **Device model** - which device the Linux kernel is told it runs on. Set it once to your device.
- **Volume up at boot** - what holding **Volume +** at power-on boots instead, without changing
  the default (usually **Android**).

**Uninstall CFW** removes an internal install (see below).

On a device still running the ROCKNIX ABL or its factory bootloader, install OpenABL from the
running system: **Pocknix Tools → Advanced → Bootloader → Install**, or `pocknix-update-abl` in a
terminal.

---

## Install to internal

> ⚠️ Installing to internal shrinks Android's userdata partition, so Android reformats it on its
> next boot. Android still boots, but its apps and data are gone - effectively a factory reset. Back
> up anything you care about first.

You must be **booted from a Pocknix SD** (the installer clones the *running* system to internal).

**Everything on the SD's Pocknix partition has to fit on internal storage**, Steam games and ROMs
included, in the space Android does not keep. The installer checks this before touching anything
and tells you how much to free if it does not fit: uninstall games or move ROMs off the card first,
and reinstall them onto internal storage afterwards.

**Pocknix Tools → Advanced → Internal storage** (game or desktop mode): pick how much internal
storage Android keeps, press and hold **Install**, and let it run. Or from a terminal:

```bash
# 1. dry-run - prints the exact partition plan, makes NO changes. Review it.
pocknix-install-internal --dry-run

# 2. for real. It asks for the new Android userdata size (or pass --userdata-gib N),
#    then shrinks userdata, creates the boot + POCKNIX_ROOT partitions, and rsyncs the
#    running rootfs across (the clone is the slow part - minutes off a slow SD).
pocknix-install-internal
#   non-interactive equivalent:
#   pocknix-install-internal --yes --userdata-gib 16
```
Flags: `--dry-run`, `--yes`/`-y`, `--userdata-gib N`, `--device /dev/sdX` (default `/dev/sda`).
The dry run prints how much the SD holds and the largest Android size that still fits it.

If an install fails part-way (the log ends in an error after "Repartitioning"), do **not** boot
internal storage: run `pocknix-uninstall-internal` (or **Remove, restore Android** in Pocknix
Tools) to clear the half-written install, fix the cause, and install again.

### Then point the bootloader at it

With **Boot source** on **Auto** the internal install boots next time, even with the SD card in.
On **SD card**, power off, hold **Volume −** to open the menu and set **Boot source** to
**Internal** (or **Auto**).

Set it to **SD card** whenever you want to boot the SD again; nothing on either disk changes.

### Then use the microSD slot for games

Booting from internal frees the slot for a games card. Format it in Steam, the same as on a Steam
Deck: **Settings → Storage**, highlight the card, then **Options (Y) → Format**.

> **Formatting erases everything on the card.** Steam asks you to confirm before it starts.

The card is formatted the way a Steam Deck does it (ext4 with casefolding), mounts automatically,
and Steam makes it the default install location right away. Cards formatted this way also work in
a real Steam Deck, and vice versa. The card pocknix boots from never shows up there to format.

---

## Uninstall from internal

> ⚠️ Uninstalling from internal regrows Android's userdata partition back to its original size, so
> Android reformats it on its next boot. Android still boots, but its apps and data are gone -
> effectively a factory reset. Back up anything you care about first.

### From the OpenABL menu (recommended)

Hold **Volume −** at power-on and select **Uninstall CFW**. It deletes the internal Linux install
and grows Android's partition back to its full size in one step - no SD card, no second boot.

### From a running pocknix SD

You **can't repartition the disk you're booted from**, so this has to run from the SD. Set **Boot
source** to **SD card** in the menu, boot it, then use **Pocknix Tools → Advanced →
Internal storage → Remove**, or a terminal:

```bash
pocknix-uninstall-internal --dry-run     # review the plan
pocknix-uninstall-internal
```
It removes the internal boot and `POCKNIX_ROOT` partitions and grows Android `userdata` back to fill
the disk. Flags: `--dry-run`, `--yes`/`-y`, `--device /dev/sdX` (default `/dev/sda`). It refuses to
run if `/` is on the target device, as a guard.

---

## Put a *new* version on internal (clean reinstall)

```
boot menu -> Boot source: SD card, and boot the SD carrying your new build
  -> pocknix-uninstall-internal      (clears the old install so the installer sees a fresh disk)
  -> pocknix-install-internal        (clones the fresh SD onto internal)
  -> boot menu -> Boot source: Auto (or Internal)
```

**Pocknix Tools → Advanced → Internal storage** does the two middle steps: **Remove**, then
**Install**.

---

## Restoring the stock bootloader

Removing pocknix does not put the original Android bootloader back - OpenABL stays until you flash
your backup over it. Keeping OpenABL is mostly harmless, but if you're after a *full* return to
stock then this is the final step. It needs the `abl_a.img` / `abl_b.img` backup you were told to
make (and copy off the device) when you first replaced the bootloader.

Where your backup is, depending on how you flashed:

- **Android's `backup_abl.sh`** (the [install guide](install.md#2-install-the-openabl-bootloader) steps): it wrote
  `abl_a.img` + `abl_b.img` into `openabl/` (`rocknix_abl/` on older pocknix cards) on Android
  internal storage - gone if you have since installed to internal, so use the copy you were told
  to keep off the device.
- **`pocknix-update-abl` / Pocknix Tools**: it saved the bootloader it replaced to
  `/flash/openabl/` (older backups in `/flash/rocknix_abl/` are moved there) and, when an SD card
  was mounted, copied it to `pocknix-abl-backup/` on that card. Note this is only *stock* if that
  run was the first time the device's bootloader was ever replaced.

Then, from Android:

1. **Boot Android.** If pocknix is on internal storage, remove it first (**Uninstall CFW** above) -
   otherwise Android has no room to come back. Then set the menu's **Boot mode** to **Android**,
   or hold **Volume +** at power-on.
2. Put an `openabl` folder at the root of Android's internal storage if it isn't there any more
   (copy it off a pocknix SD card, same as during install), and **copy your `abl_a.img` and
   `abl_b.img` backups into it**. The names and the location matter - the script reads exactly
   `openabl/abl_a.img` and `openabl/abl_b.img`.
3. Open **Settings → Handheld Settings → Advanced → Run Script as Root**, navigate to that folder,
   and run **`restore_backup_abl.sh`**.
4. Reboot. The device is back on its factory bootloader and boots Android the way it shipped.
   If your backup is the ROCKNIX ABL (an older pocknix card's bootloader) rather than stock, it
   stops at "device not set" on the first boot: OpenABL took the model it had stored. Pick your
   device in its menu once.

> ⚠️ Keep the device plugged in while doing ABL writes: an interrupted or wrong bootloader write
> leaves a device that needs a PC to recover.

After this, the device can no longer boot pocknix: pocknix needs OpenABL. Flash it again
([install guide](install.md#2-install-the-openabl-bootloader)) to bring it back.
