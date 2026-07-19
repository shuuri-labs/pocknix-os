# PATCHES.md — shared-patch ledger (pocknix-os <-> armada)

Both projects patch the same fast-moving components, differently packaged (pocknix-os:
PKGBUILD patch series; armada: its own PATCHES.md/build_files). This ledger is the sync
point: when either project bumps or rebases a component, update the row here AND in the
sibling repo's ledger so drift is visible. Rebase procedure: pocknix-notes dev/patch-rebase.md.

| Component | pocknix-os base | Patches (pocknix-os) | armada variant | Last rebased |
|---|---|---|---|---|
| gamescope | Valve `4286887` (3.16 era, "Bump wlroots to v0.19", 2026-06-12) | 0001 wl_touch, 0004 FAKE_OUTPUT_MM, 0005 rotation-shader, 0006 XTest cursor (= ROCKNIX set verbatim). Dropped: 0007 composite-rotation (fps-neutral vs 0005); 0008 mangoapp frametime revert (see PKGBUILD header — it did NOT cause/fix the perf gap, its hunk-2 also skips wlserver_app_presented() on this base which is new since fe78bc6, and no overlay tax is occurring: ring-0 composites == present rate on-device. The cv_mangoapp_use_output_timing convar is NOT a substitute for it either). Launch: -W 1080 -H 1920 --use-rotation-shader | carries the rotation approach for the same panel — check its PATCHES.md | 2026-07 (bump 4286887, 60fps-lock fix) |
| mesa | 25.1.5 tarball (ROCKNIX pin), epoch=2 | 0001 c11/c23 shim (upstream 179e744f7577 — drop when the pin contains it); VERSION rewritten `-pocknix2.1` | n/a (armada consumes prebuilt) | 2026-06 (initial) |
| mangohud | v0.8.3 | 6 patches applied; 0002 is PER-SoC (0002-SM8550 gpuss_0_thermal / 0002-SM8250 gpu_top_thermal, selected by POCKNIX_SOC; both from ROCKNIX), 0006 mangoapp pacing (pairs with gamescope 0008) | shared origin — compare on bump | 2026-07 (sm8250 variant) |
| FEX | `1cc4b93e` (FEX-2607 tag, 2026-07-02) | 0001/0002/0005/0006; ROCKNIX 0004 (nix) deliberately dropped; 0003 dropped at 2607 (upstream target_include_directories_from_pkgconfig strips /usr/include itself) | AHEAD of armada + ROCKNIX (both still 2605/a04b0241); see pocknix-notes dev/fex-version-bump.md + armada PATCHES.md | 2026-07 (2607 bump) |
| kernel (sm8550) | stock 7.0.11 + ROCKNIX `next` snapshot (jaewun thor-suspend-merge) | kernel/sm8550/patches: 10-mainline (5), 20-sm8550 (63, incl. 0504 IPCC suspend, 1030 ACD gpu-init defer), 30-version (2); local delta per kernel/README.md | armada uses its own kernel packaging of the same ROCKNIX base | 2026-06 sync |
| kernel (sm8250) | stock 7.1.2 + ROCKNIX `next` snapshot | kernel/sm8250/patches: 10-mainline (5), 20-sm8250 (28: retroid-gamepad MCU, CH13726A panel, pm8150b, wsa881x, jack-detect), 30-version (2) | n/a (armada is RP6-only) | 2026-07 (initial sync) |
| alsa-ucm (RetroidPocket, sm8250) | ROCKNIX alsa-ucm-conf patches/SM8250/0002 | hand-ported into devices/sm8250/.../pocknix-bsp-sm8250 (UCM is NOT covered by make sync); wsa881x stereo remap INLINED into RetroidPocket.conf (upstream file-conflict avoidance) | n/a | 2026-07 (initial port) |
| GRUB (sm8250 arm-efi) | ROCKNIX-built bootaa64.efi, VENDORED binary from release 20260701 (sha pinned; packages/pocknix-bootloader-sm8250/README.provenance) | none (their 2.14-rc1 + 5 patches, used as-is); pocknix-authored static grub.cfg | n/a | 2026-07 (initial vendor) |
