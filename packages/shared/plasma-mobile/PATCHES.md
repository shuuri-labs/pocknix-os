# plasma-mobile patches

What this package carries and why, one entry per patch. How each patch works is in its header.

## Base

6.8.1 tarball (Arch's build)

It shadows the base by repo order.

Last rebased: 2026-11-10 (6.8.1, two-screen gesture and brightness slider).

## Carried

- **0001** With two screens the task switcher gesture works: only the screen the swipe started on
  acts on it, so an empty screen no longer closes the switcher on release and the other screen's
  apps are no longer minimized. Source: ours; upstream: not filed. Drop: the condition is in the
  patch header.

- **0002** The quick-settings brightness slider stays hidden for the whole session when PowerDevil
  starts after plasmashell: the util watches an interface name nothing owns, so the late service
  is never seen. It now watches `org.kde.Solid.PowerManagement`; `isValid()` follows the owner and
  the existing availability signal reaches QML. Source: ours; upstream: not filed. Drop: when
  plasma-mobile watches the service name.

- **0003** The handle jumped on press and the floor was guessed from `from: 1`. It now binds with
  `RestoreNone`, so nothing restores the pre-press value, and reads
  `brightnessMin`/`brightnessMinChanged` (added to the bundled XML). Source: ours; upstream: not
  filed. Drop: when the util reads `brightnessMin` and the binding restores none.

## Not taken

None.

## Retired numbers

None.
