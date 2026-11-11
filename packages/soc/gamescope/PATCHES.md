# gamescope patches

What this package carries and why, one entry per patch. How each patch works is in its header.

## Base

Valve `3.16.31` (f6916aa, 2026-09-27)

Launch: logical landscape -W/-H, rotation autodetected from the primary plane (scanout on
sm8550 via kernel 0066, composite on sm8250); POCKNIX_PANEL_ROTATE_SHADER=1 forces
--force-composition-rotation for panels past the 1088-line rotator cap.

Last rebased: 2026-11-11 (0017-0019 panel profiles).

## Carried

### Input

- **0001** Touch works when gamescope runs nested: the Wayland backend wires up wl_touch.
  Source: ROCKNIX set.
- **0006** The gamepad cursor sprite no longer freezes when the cursor is driven through XTest.
  Source: ROCKNIX set.
- **0015** Android under Lepton gets real taps and swipes: a touch that goes down on an xdg-shell
  window passes through as wl_touch instead of Steam's pointer emulation, and keeps that mode
  until it lifts. X11 windows keep Steam's mode. Source: armada 0025, code verbatim, hunks
  re-anchored.

### Display and planes

- **0004** GAMESCOPE_FAKE_OUTPUT_MM sets a custom display physical size. Source: ROCKNIX set.
- **0012** A plane layout msm has no free hardware pipe for (test commit -ENODEV) counts as no fit
  instead of aborting. Source: sunshineinabox.
- **0013** The Steam overlay and MangoHud stay above the game: libliftoff sets a plane's mutable
  zpos from its layer, so msm's several primary planes (all zpos 0, else stacked by plane id)
  follow layer order. Source: ROCKNIX 0020 + 0022, verbatim.
- **0017** An EDID-less internal panel (every DSI board) gets a synthetic EDID built from its
  preferred mode (sRGB chromaticity, no HDR), so known-display profiles are looked up at all
  and Steam sees a display. Never committed to KMS. Trap: every internal panel's kernel modes
  at native size now become Steam's refresh list (was empty; 0018 does it for profiled panels
  too), so a panel with several modes (the Nova's 60 + 120) gets Steam refresh switching.
  Source: armada 0002, without its tests.
- **0018** Steam's default vibrance no longer oversaturates the OLED panels: known-display
  `matches()` also gets `connector`, `device_id` (`GAMESCOPE_INTERNAL_DEVICE_ID`, internal
  connectors only), `internal` and `has_edid`, so the BSPs' panel profiles (board id passed
  by pocknix-steam) give a panel its Display P3 colorimetry. Also fixes the CTA descriptor
  offset when an HDR block is inserted into the EDID. Needs: 0017. Source: armada 0003,
  without its tests.

### Frame pacing and colour

- **0009** FSR resolves to SGSR on SDR RGB, since the Steam Deck client offers no SGSR entry.
  The `fsr_means_sgsr` convar (default on) restores plain FSR. Source: ours.
- **0010** A frame that misses its vblank no longer waits a whole extra period: the fixed-refresh
  limiter releases frames by elapsed time since the last latch instead of a vblank-count
  divisor. The `limiter_use_elapsed_time` convar (default on) restores the divisor.
  Source: armada 0027.
- **0011** The composite skips identity colour LUTs, the larger half of sm8250's every-frame
  composite (the shaper + 3D LUT taps). Steam's 0.5 gamut wideness counts as native where scanout
  cannot be colour managed (new `IBackend::SupportsScanoutColorManagement`), and a virtual white
  within 0.001 xy of the display's is no override. The `color_mgmt_skip_identity_luts` and
  `color_mgmt_native_gamut_without_plane_cm` convars (default on) turn each half off.
  Trap: a raw shaper/3D LUT override is never treated as identity. Source: ours.
- **0016** Night mode and the colour sliders reach directly scanned-out games at no GPU cost:
  on SDR gamma 2.2 output the shaper + 3D LUT go to the msm DPU's CRTC `DEGAMMA_LUT` +
  `DPU_3D_LUT` and the shader leaves them unbound; turning them on or off asks for a modeset
  (sm8550 1124 and sm8250 1126 keep the topology, so the kernel does no full one). Where the
  kernel lacks `DPU_3D_LUT` (an older kernel), a non-identity LUT composites instead of being
  dropped at scanout. It also makes the DRM backend report scanout colour management, so
  Steam's gamut wideness applies (0011's native override lifts). The `drm_output_luts` convar
  (default on) keeps it in the shader. Needs: 0011; sm8550 kernel 1121-1124 or sm8250 kernel 1125-1126. Trap: scanout
  colour management is reported per capability, not per frame, so with PQ output or an
  HDR/scRGB layer (output LUTs off) Steam's wideness reaches composited frames only; the
  degamma size (256) is hardcoded to match 1121. Source: armada 0017, without its armada 0004
  hunks (HDR output composite rule and its test); the deferred backend forwards the new hooks.
- **0019** A panel profiled with exact Display P3 primaries counts as wide gamut, so vibrance 0
  is accurate sRGB and Steam's 0.5 a mild boost (`BIsWideGamut` wanted red y < 0.320; P3 red
  is 0.320). Source: armada 0019, verbatim.

### Steam focus

- **0014** An app whose only window is native Wayland (Lepton's Android container) leaves the
  launch spinner: mapped xdg-shell windows that carry an appid are reported in
  GAMESCOPE_FOCUSABLE_APPS/WINDOWS (id = top bit + xdg id, also published as
  GAMESCOPE_FOCUSED_WINDOW and honoured in GAMESCOPECTRL_BASELAYER_WINDOW).
  Source: armada 0024, verbatim.

## Not taken

- ROCKNIX 0008 --rotated-output-max-height: no such board yet.
- The revert of upstream e572411d (mangoapp frametimes): its early return skips
  `wlserver_app_presented()`, dropping the game's presentation feedback.

## Retired numbers

0005, 0007, 0008
