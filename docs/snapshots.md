# Snapshots, rollback and the update safety net

Every update takes a snapshot of the system first, so if one breaks something you can undo it
with one button (or one command) and a reboot. **A rollback never touches your games, saves or
settings**: only the system itself goes back. If the update included a new kernel, the previous
kernel comes back too.

Pocknix keeps the snapshots from the last two updates. Snapshots are skipped when storage is
nearly full. The update still installs; you just cannot undo that one.

## Using it

Three front-ends, one mechanism - pick whichever still works when things go wrong:

- **Game mode (QAM):** Pocknix Control → Updater tab → **Roll Back Last Update**. The
  confirmation lists what gets restored; confirm, then **Reboot Now**. It only ever offers the
  last update.
- **Pocknix Tools** (game or desktop mode): **System** → *Roll back an update* lists every
  snapshot, newest first; press and hold *Roll back* on one, and it offers the restart. Use this
  when the plugin is what broke. Booted from the SD with Pocknix also on internal storage, an
  *Internal install* list does the same for the internal copy.
- **CLI (terminal/ssh):**

```bash
pocknix-snapshots list          # what you can roll back to
pocknix-snapshots status        # running root / boots-next / free space
sudo pocknix-rollback           # newest snapshot, interactive confirm
sudo pocknix-rollback --to 0003 # jump straight to a specific snapshot
sudo pocknix-rollback --yes     # skip the confirm (scripts)
sudo pocknix-rollback --internal --to 0003  # roll back the internal install from the SD
pocknix-rollback --list         # same as pocknix-snapshots list (--status likewise)
sudo pocknix-snapshots prune    # apply the retention now (updates do this themselves)
```

Snapshots are full photographs of the system, not incremental steps, so `--to` is always a
**single jump** - no rolling back one update at a time. It is also directionless: from a
restored older state, `--to` a newer snapshot moves you forward again. The QAM only ever
offers the *last* update (the common case); anything deeper is for Pocknix Tools or the CLI. Times are
stored in UTC but always displayed in local time.

Every rollback creates a fresh root from an immutable read-only snapshot. The system you
rolled back from is deleted at the next update, so to undo a rollback, update again.
After a rollback the QAM shows a *"System was rolled back"* notice and hides the rollback
button (you are already on that snapshot's state); the next update clears the notice,
takes a fresh snapshot, and brings the button back.

## Manual recovery (device won't boot after a kernel update)

Every kernel update keeps the previous boot image as `/flash/KERNEL.bak`. If the device
no longer boots and you can't get a shell:

1. Power off. Put the SD in a card reader (internal installs: boot a pocknix SD instead and
   mount the internal FAT).
2. On the boot FAT partition:
   ```bash
   mv KERNEL KERNEL.bad
   mv KERNEL.bak KERNEL
   md5sum KERNEL > KERNEL.md5    # MANDATORY - the ABL refuses a KERNEL whose md5 mismatches
   ```
3. Boot. The old kernel now runs with the newer modules - degraded (Wi-Fi/audio may be
   missing) but alive. Run `sudo pocknix-rollback` on the device to make kernel and rootfs
   coherent again.
