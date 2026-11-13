# mesa patches

What this package carries and why, one entry per patch. How each patch works is in its header.

## Base

26.3.0 tarball, epoch=2

Build: VERSION is rewritten to `-pocknix<epoch>.<pkgrel>` (CEF GPU-cache bust). vulkan-freedreno
also ships `/usr/share/pocknix/vk-arm/<pkgver>/icd.json`, so pocknix-turnip-arm must never pin
mesa's series.

Last rebased: 2026-11-10 (26.3.0 bump).

## Carried

- **0011** Games limited by GPU memory bandwidth can run faster: DXVK-style mutable-format
  images (and emulator output images) stay tiled and UBWC-compressed instead of going linear.
  Off unless the game sets `TU_Z_MUTABLE=2` (Pocknix Control's "Keep Images Compressed");
  1 = tiled without UBWC, 0 = upstream. Our change to the source: default 0, so an unset game
  runs plain mesa. Applies: GPUs without `ubwc_all_formats_compatible` (A650, A740). Trap: on
  A740 it needs 0012 or overlays and water render black or white. Trap: pocknix-turnip-arm carries the same
  pair; keep their behaviour the same. Drop: when upstream keeps UBWC on these images.
  Source: https://github.com/armada-os/armada/blob/b031deef99a095104ef234c5a0705850152dffe1/packages/mesa/patches/0011-tu-z-mutable-ubwc.patch
- **0012** With 0011 on, overlays and water keep their colour and storage images stop flashing
  blue tiles: copies decode a UBWC mutable image in the format it was written in, and A740-class
  GPUs drop UBWC on mutable storage images. Needs: 0011. Drop: with 0011.
  Source: https://github.com/armada-os/armada/blob/b031deef99a095104ef234c5a0705850152dffe1/packages/mesa/patches/0012-tu-z-mutable-ubwc-copy-format.patch

## Not taken

- armada 0010 (autotune GMEM multiplier 11/10 -> 10/10): only moves near-tie passes, no runtime switch, unmeasured.

## Retired numbers

0001, 0002
