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

Last rebased: 2026-10-27 (battery time remaining).

## Carried

### Gamepad

- **1069** Home works as a chord modifier (Guide+A on the Flip 2): retroid-gamepad stretches the
  firmware's fixed home pulse. Source: ours.

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

### Suspend (s2idle)

- **1095** Standing DDR and bus BCM votes drop in s2idle: `sm8250.dtsi` tags the CPU interconnect
  paths `ACTIVE_ONLY`, matching `sm8550.dtsi`. Source: ours (also in armada PR #746).
- **1096** The idle crypto engine (`qce`) releases its DDR bandwidth vote via runtime PM.
  Source: LKML v6 (Udit Tiwari), same patch `sm8550` carries.
- **1097** `camcc-sm8250` enables its GDSC clock in probe without holding a framework vote on XO,
  matching `camcc-sm8150`. Source: ours.
- **1098** The DSI PHY releases its AHB clock prepare in runtime suspend so `disp_cc` drops its XO
  vote while the panel is off. Source: ours.
- **1099-1106** `pinctrl-lpass-lpi` and `lpass-{wsa,va,tx,rx}-macro` use the PM clock framework, so
  their `q6prm` and codec clocks release in runtime suspend. Source: upstream (Srinivas Kandagatla
  / Krzysztof Kozlowski).
- **1107** The `AUDIO` DRV no longer blocks CX power collapse in s2idle: LPASS macros, SoundWire
  masters, and `pinctrl-sm8250-lpass-lpi` force runtime suspend across system sleep. Needs:
  1099-1106. Source: ours.
- **1108** `retroid-gamepad` reassembles split UART frames and powers down the MCU across system
  sleep (matching `sm8550`'s 1055 and 1065). Needs: 1069. Source: ours.
- **1109** `leds-htr3212` shuts down and releases `vdd_mcu_3v3` across system sleep (matching
  `sm8550`'s 1056). Source: armada 0030.
- **1110** `pwm-fan` quiesces its tach timer and disables its supply in suspend so the fan rail does
  not stay powered in s2idle. Source: ours.

## Edits to synced files

The local delta `kernel/sm8250/sync-keep` restores after each make sync.

- `kernel/sm8250/patches/30-sm8250/0105-drm-panel-visionox-vtdr6130-add-sm8250.patch`: ROCKNIX's
  Visionox sm8250 compatible, with a 60Hz-first mode table exposed as the single mode.
- `kernel/sm8250/dts/qcom/sm8250-retroidpocket-common.dtsi`: ROCKNIX's fan rework and its two
  includes left out (see Not taken).
- `kernel/sm8250/dts/qcom/sm8250-retroidpocket-rp5.dts`: RP5 `&battery` 5000 mAh.
- Deleted: 20-version/0011 adc-tm5 (already in 7.2.x stable), 20-version/9999 (perf rust
  target, perf not built).

## Not taken

- ROCKNIX's fan rework in retroidpocket-common.dtsi (9 cooling levels, tach on gpio0) and its
  `sm8250-pwm-fan-cooling.dtsi` include: pocknix-fancontrol owns pwm1.
- The `sm8250-sde-rotator.dtsi` include: gamescope's three rotated planes paced at 30 fps through
  the SDE rotator.

## Retired numbers

None.
