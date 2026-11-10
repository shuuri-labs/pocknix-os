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
  is never seen. It now watches `org.kde.Solid.PowerManagement`, so the late owner is noticed at
  all. Source: ours; upstream: not filed. Drop: when plasma-mobile watches the service name.

- **0003** The quick-settings slider's handle fights the finger mid-drag, and its floor is a
  hardcoded 1 instead of PowerDevil's real minimum. It now binds the value only while the handle
  is not pressed and reads `brightnessMin`/`brightnessMinChanged` (added to the bundled XML), never
  below 1. Source: ours; upstream: not filed. Drop: when plasma-mobile reads `brightnessMin` and
  stops re-binding during a drag.

- **0004** With 0002 alone the slider still stays hidden when PowerDevil answers late: the
  availability signal is emitted while `isValid()` still reports the missing owner, so QML reads
  false once and is never notified again. Availability now follows the `brightness()` reply — a
  reply sets it, an error or a lost owner clears it. Source: ours; upstream: not filed. Drop: when
  plasma-mobile derives availability from a reply.

## Not taken

None.

## Retired numbers

None.
