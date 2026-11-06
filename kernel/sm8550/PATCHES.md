# kernel/sm8550 patches

What this SoC carries on top of ROCKNIX's sync and why, one entry per patch. How each patch
works is in its header.

## Base

Stock 7.2.10 + ROCKNIX `next` 6103571f67 (2026-10-11)

Pins are in `kernel/sm8550/kernel.conf`. Stack: `patches/10-mainline`, `20-version`, `30-sm8550`
(ROCKNIX's set plus our 1000+ numbers), then `kernel/common`.

ROCKNIX 1000+ (synced, not ours): 1000, 1002, 1003, 1005, 1020.

Last rebased: 2026-10-27 (RP6 LRA haptics).

## Carried

### Gamepad and stick LEDs

- **1004** The gamepad works after resume: rsinput quiesces the MCU across suspend.
  Source: jaewun.
- **1009** The gamepad no longer dies on an unlucky resume: rsinput handshakes the MCU version
  before sending its report mode. Source: jaewun.
- **1063** Small stick movements are no longer dropped: rsinput reports at 250 Hz (MCU SET_PAR
  threshold 40 -> 6 counts, period 9 -> 4 ms). Source: values from armada PR #470 by diogotr7,
  carried as a separate patch so make sync cannot drop it.
- **1064** The rsinput trigger release reference is decoupled from the calibrated
  trigger_*_max, so calibration no longer costs trigger travel. Source: armada 1301, verbatim.
- **1065** rsinput reassembles UART frames instead of dropping them, so input after resume is
  not thrown away. Source: armada 0515, verbatim.
- **1068** The sn3112 stick LED driver powers down across system suspend. Applies: inert while
  our Odin 2 dts keeps both sn3112 nodes disabled. Source: armada 0054c.

### Suspend (s2idle stack 2)

- **1055** The gamepad MCU supply is cut across suspend. Source: armada PR #545.
- **1056** The htr3212 stick LEDs get PM ops, so they release the rail they share with the MCU.
  Source: armada PR #545.
- **1057, 1058, 1059** The ADSP graphs are released across suspend, so an open sound no longer
  keeps the ADSP awake. Trap: 1059 is rebased onto ROCKNIX 0612 and needs 1058, so 1057-1059
  stay together. Source: armada PR #545.
- **1049** sm8550.dtsi marks a PCIe suspend OPP, the one kernel/common 1048 keeps as the memory
  floor in s2idle. Source: armada.

### Display, touch, GPU

- **1021** The RP6 panel exposes only its 120Hz mode. Source: ours.
- **1050** edt-ft5x06 power is retained in suspend (Thor's lower touchscreen). Needs: ROCKNIX
  0053. Source: jaewun.
- **1051** sm8550.dtsi gains the lowest GPU OPP. Source: Thorch contributors.

### Haptics

- **1081** The RP6 LRA rumbles at its own resonance: qcom-hv-haptics checks the calibrated LRA
  period against the board's `qcom,lra-period-us` (10%) and falls back to it, instead of
  ROCKNIX's fixed 185-215 Hz window and forced 205 Hz (the RP6 LRA calibrates at ~173 Hz).
  Source: ours.

## Edits to synced files

The local delta `kernel/sm8550/sync-keep` restores after each make sync.

- `kernel/sm8550/dts/qcom/qcs8550-ayn-common.dtsi`: sdhc_2 without `sdhci-caps-mask` (UHS-I
  SDR104 on stock sdhci-msm, as armada carries it); rail and WAKE# constraints, bob1 LPM, and the
  gamepad MCU on vdd_mcu_3v3 without always-on (armada PR #545).
- `kernel/sm8550/dts/qcom/qcs8550-ayn-odin2.dts`: `&vreg_l12b_1p8` always-on (armada 8675d40:
  the panel draws over a watt in sleep with its IO supply cut).
- `kernel/sm8550/dts/qcom/qcs8550-ayn-thor.dts`: touchscreens without `touchscreen-swapped-x-y`
  / `touchscreen-inverted-x` (armada's Thor dts patch: gamescope and kwin rotate touch by the
  panel orientation, so a kernel-side rotation landed touch 90 degrees off).
- `kernel/sm8550/dts/qcom/qcs8550-retroidpocket-rp6.dts`: haptics driven as an LRA (no
  `use-erm`, 1300 mV node and effect drive, effect auto-res off, stock effect_0 pattern; armada
  PR #694, values from the stock Android board-id 0x1001f overlay). Nova and top-dpad include
  rp6.dts and inherit it.
- Deleted: 20-version/0011 adc-tm5 (already in 7.2.x stable), 20-version/9999 (perf rust
  target, perf not built), 30-sm8550/0502 IPCC IRQF_NO_SUSPEND removal (kernel/common 1095
  keeps the doorbell live in s2idle instead).

## Not taken

None.

## Retired numbers

None.
