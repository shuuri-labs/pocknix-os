# mesa patches

What this package carries and why, one entry per patch. How each patch works is in its header.

## Base

26.2.6 tarball, epoch=2

Build: VERSION is rewritten to `-pocknix<epoch>.<pkgrel>` (CEF GPU-cache bust). vulkan-freedreno
also ships `/usr/share/pocknix/vk-arm/<pkgver>/icd.json`, so pocknix-turnip-arm must never pin
mesa's series.

Last rebased: 2026-11-05 (26.2.6 bump).

## Carried

- **0002** An Adreno 830 that the kernel reports as revision 1 (0x44050001, the id the upstream
  kernel's A830 support uses) is not recognised, so GL and Vulkan get no driver. Adds that id
  to the device table; 0x44050000 already matches. Applies: Adreno 830 (sm8750). Trap:
  pocknix-mesa-android does not carry it. Source:
  https://gitlab.freedesktop.org/mesa/mesa/-/commit/2061a5ee6184e465eafb87cf465aed92c04f1a41
  Drop: at 26.3.0, which contains it.

## Not taken

- The KGSL form of the Adreno 830 revision 0 id (0x44050000): no pocknix kernel uses KGSL.

## Retired numbers

None.
