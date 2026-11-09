# plasma-mobile patches

What this package carries and why, one entry per patch. How each patch works is in its header.

## Base

6.8.1 tarball (Arch's build)

It shadows the base by repo order.

Last rebased: 2026-10-29 (6.8.1, two-screen gesture).

## Carried

- **0001** With two screens the task switcher gesture works: only the screen the swipe started on
  acts on it, so an empty screen no longer closes the switcher on release and the other screen's
  apps are no longer minimized. Source: ours; upstream: not filed. Drop: the condition is in the
  patch header.

## Not taken

None.

## Retired numbers

None.
