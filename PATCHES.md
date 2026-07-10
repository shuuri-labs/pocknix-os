# PATCHES.md — shared-patch ledger (pocknix-os <-> armada)

Both projects patch the same fast-moving components, differently packaged (pocknix-os:
PKGBUILD patch series; armada: its own PATCHES.md/build_files). This ledger is the sync
point: when either project bumps or rebases a component, update the row here AND in the
sibling repo's ledger so drift is visible. Rebase procedure: docs/dev/patch-rebase.md.

| Component | pocknix-os base | Patches (pocknix-os) | armada variant | Last rebased |
|---|---|---|---|---|
| gamescope | Valve `4286887` (3.16 era, "Bump wlroots to v0.19", 2026-06-12) | 0001 wl_touch, 0004 FAKE_OUTPUT_MM, 0005 rotation-shader, 0006 XTest cursor (= ROCKNIX set verbatim). Dropped: 0007 composite-rotation (fps-neutral vs 0005), 0008 mangoapp frametime revert (base carries e572411d but adds the cv_mangoapp_use_output_timing convar, default true; flip false at runtime instead of patching). Launch: -W 1080 -H 1920 --use-rotation-shader | carries the rotation approach for the same panel — check its PATCHES.md | 2026-07 (bump 4286887, 60fps-lock fix) |
| mesa | 25.1.5 tarball (ROCKNIX pin), epoch=2 | 0001 c11/c23 shim (upstream 179e744f7577 — drop when the pin contains it); VERSION rewritten `-pocknix2.1` | n/a (armada consumes prebuilt) | 2026-06 (initial) |
| mangohud | v0.8.3 | 6 patches; 0002 SM8550 GPU sysfs paths (SoC-specific), 0006 mangoapp pacing (pairs with gamescope 0008) | shared origin — compare on bump | 2026-07 (fps fix) |
| FEX | `a04b0241` (2605 era) | 0001/0002/0003/0005/0006; ROCKNIX 0004 (nix) deliberately dropped | same FEX commit as armada + ROCKNIX; see docs/dev/fex-version-bump.md + armada PATCHES.md | 2026-05 pin |
| kernel (sm8550) | stock 7.0.11 + ROCKNIX `next` snapshot (jaewun thor-suspend-merge) | kernel/sm8550/patches: 10-mainline (5), 20-sm8550 (60, incl. 0504 IPCC suspend), 30-version (2); local delta per kernel/README.md | armada uses its own kernel packaging of the same ROCKNIX base | 2026-06 sync |
