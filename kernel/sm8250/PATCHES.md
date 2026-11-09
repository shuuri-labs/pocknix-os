# kernel/sm8250 patches

What this SoC carries on top of ROCKNIX's sync and why, one entry per patch. How each patch
works is in its header.

## Base

Stock 7.2.10 + ROCKNIX `next` 6103571f67 (2026-10-11)

Pins are in `kernel/sm8250/kernel.conf`. Stack: `patches/10-mainline`, `20-version`, `30-sm8250`
(ROCKNIX's set: retroid-gamepad MCU, CH13726A + Visionox panels, pm8150b charger + PR swap + DP
audio, wsa881x, jack-detect, SDE rotator + QSEED set from ROCKNIX PR #3377, 9998-gpu-tuning OC
ladder + ACD + bw votes; plus our 1000+ numbers), then `kernel/common`.

ROCKNIX 1000+ (synced, not ours): none.

Last rebased: 2026-11-06 (s2idle stack 3).

## Carried

### Gamepad

- **1069** Home works as a chord modifier (Guide+A on the Flip 2): retroid-gamepad stretches the
  firmware's fixed home pulse. Source: ours.

### Suspend

- **1118** DDR can self-refresh in sleep: the CPU to DDR interconnect votes are tagged active-only,
  so they leave the sleep set. Source: gennro, via kettlelinux 0114 and armada 0568.

### Charger and battery

- **1070** Rebinding the pm8150b charger no longer fails probe: the wakeirq no longer leaks.
  Source: ROCKNIX PR #3417 0020, verbatim, renumbered. Drop: swap for ROCKNIX's copy once merged.
- **1071** Charging can stop at a chosen level: opt-in charge_control thresholds.
  Source: ROCKNIX PR #3417 0022, verbatim, renumbered. Drop: swap for ROCKNIX's copy once merged.
- **1072** The charger range checks the battery info it programs. Source: ROCKNIX PR #3417 0023,
  verbatim, renumbered. Drop: swap for ROCKNIX's copy once merged.
- **1073** A USB-PD charger no longer leaves the battery draining: the charger handles a USB-PD
  sink input limit. Source: ROCKNIX PR #3417 0024, verbatim, renumbered. Drop: swap for ROCKNIX's
  copy once merged.
- **1084** UPower gets an energy level and Steam a time remaining: qcom_fg reports CHARGE_FULL as
  the design capacity and CHARGE_NOW as state of charge times it (-ENODATA without a design
  capacity). Source: ours.
- **1085** The battery no longer shows as discharging while it charges: pm8150b charger ONLINE
  reads 0/1 instead of the raw plug-in bit (16), which UPower rejected. Source: ours, fixing
  ROCKNIX's own 0011; goes to ROCKNIX. Drop: once their 0011 carries it (the sync's apply check
  then fails it as already applied).
- **1086** Steam keeps the charging indicator after plug-in: qcom_fg CURRENT_NOW is negated so
  charging reads positive. Source: ours, fixing ROCKNIX's own 0011; goes to ROCKNIX. Drop: once
  their 0011 carries it (the sync's apply check then fails it as already applied).

### Display and audio

- **1079** Dock stereo survives on USB-C DisplayPort: q6afe sends the HDMI-over-DP stream index
  and controller index (both 0) before it starts port 0x6020, as Android's q6afe does. Without
  them the DSP copied front left to both channels. Source: ours, from Android's q6afe; goes
  upstream (ASoC).
- **1092** USB-C DisplayPort docks work in both plug orientations: `qmp_v4_dp_aux_init()` writes
  `QSERDES_DP_PHY_MODE` (`0x4c` reversed / `0x5c` normal) before the first AUX DPCD read instead
  of waiting for `phy_configure()` at link training. Source: ours; goes upstream.
- **1093** USB-C PD and DisplayPort survive across docked suspend: `qcom_pmic_typec` delivers any
  PD message received while SPMI interrupts were masked in `s2idle` and re-reads CC/VBUS on
  resume instead of leaving the PD PHY receive buffer wedged (`-EBUSY`). Source: ours.
- **1094** A docked DisplayPort monitor wakes from suspend and DPMS off without AUX timeouts:
  `msm_dp` puts the sink in `D3` on a DRM-initiated disable, wakes it to `D0` before re-training,
  and routes USB-C DisplayPort Attention VDMs (`IRQ_HPD`) to `EV_IRQ_HPD_INT`. Source: ours.

## Edits to synced files

The local delta `kernel/sm8250/sync-keep` restores after each make sync.

- `kernel/sm8250/patches/30-sm8250/0105-drm-panel-visionox-vtdr6130-add-sm8250.patch`: ROCKNIX's
  Visionox sm8250 compatible, with a 60Hz-first mode table exposed as the single mode.
- `kernel/sm8250/dts/qcom/sm8250-retroidpocket-common.dtsi`: ROCKNIX's fan rework and its two
  includes left out (see Not taken).
- `kernel/sm8250/dts/qcom/sm8250-retroidpocket-rp5.dts`: RP5 `&battery` 5000 mAh.
- `kernel/sm8250/dts/qcom/sm8250-retroidpocket-flip2.dts`: the lid wakes only on opening, so
  closing it on a sleeping Flip 2 no longer wakes it (armada's Flip 2 dts).
- Deleted: 20-version/0011 adc-tm5 (already in 7.2.x stable), 20-version/9999 (perf rust
  target, perf not built).

## Not taken

- ROCKNIX's fan rework in retroidpocket-common.dtsi (9 cooling levels, tach on gpio0) and its
  `sm8250-pwm-fan-cooling.dtsi` include: pocknix-fancontrol owns pwm1.
- The `sm8250-sde-rotator.dtsi` include: gamescope's three rotated planes paced at 30 fps through
  the SDE rotator.

## Retired numbers

None.
