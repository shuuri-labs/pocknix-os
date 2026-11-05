# pocknix-mesa-android patches

What this package carries and why. It carries no patches today.

## Base

26.2.6 tarball (mesa's pin), epoch=2

One shared build at the fleet's floor `-march` (sm8250's armv8.2-a string). NDK r28c (sysroot +
compiler-rt only), libdrm 2.4.133, Fossilize `556da9ff` + its rapidjson submodule `8f4c021f`.

Build: Mesa is built for bionic (API 30, freedreno + zink + turnip) with the host clang/lld,
since the NDK ships x86_64 host compilers only. libdrm is meson's fallback (bionic has none),
its tarball handed over through meson's packagecache, so `_libdrmver` moves to the release's
`libdrm.wrap` pin on a version bump. Fossilize is built alongside because Lepton aborts without
its layer.

Last rebased: 2026-11-05 (26.2.6 bump).

## Carried

None.

## Not taken

None.

## Retired numbers

None.
