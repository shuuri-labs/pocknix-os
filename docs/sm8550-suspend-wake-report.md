# SM8550 (Retroid Pocket 6) — spurious wake from deep suspend

Findings from on-device testing, to share with the SM8550 suspend/resume maintainer.

## Environment
- Kernel **7.0.11** = ROCKNIX SM8550 + `thor-suspend-fixes` + RP6 delta (built fresh, GCC 16.1).
- **Retroid Pocket 6**, minimal Arch Linux ARM userland (pocknix-os), booted from SD.
- `/sys/power/mem_sleep` = `s2idle [deep]` (deep selected via `mem_sleep_default=deep`).

## Symptom
Spontaneous wake from **deep** suspend, untouched:
```
PM: suspend entry (deep)
  (~3.4 s later, no user input)
PM: suspend exit
```
**Intermittent** — some cycles stay asleep until the power key; others self-wake in a few
seconds (so it's event-driven, not a fixed-period timer).

## Ruled out / confirmed working
- `/sys/power/pm_wakeup_irq` = **ENODATA** on the spurious wakes → a genuine post-deep-sleep
  wake, **not** a noirq-phase abort. The suspend *entry* path is clean.
- IRQ 21 = `pmic_pwrkey` (power button) — not involved in the spontaneous wakes.
- **TSENS uplow-wake fix is working**: `qcom-tsens …: leaving TSENS uplow IRQ 23/25/27 as
  non-wakeup on SM8550`. So this is a *different* source than the thermal one already fixed.

## Evidence — `/sys/kernel/debug/wakeup_sources` (only nonzero rows)
```
name                                 active_count  event_count  last_change
battery                              8             9            1076475
ucsi-source-psy-pmic_glink.ucsi.01   1             1            11124
qcom-battmgr-usb                     1             1            5640
qcom-battmgr-wls                     1             1            5640
```
All others zero: `pwrkey`, `…:rtc@6100`, `alarmtimer.0.auto`, `gpio-keys`, `mmc0`, `mhi0`,
`32300000.remoteproc`, `6800000.remoteproc`.

## Interpretation
The only active wakeup sources are the **`pmic_glink` power-supply path**: Type-C/**UCSI** +
**qcom-battmgr** (USB + wireless) + the **battery** power_supply. ENODATA is consistent with a
wake delivered via pmic_glink/RPMSG rather than a GIC IRQ. Hypothesis: **charger/Type-C/PD
status events are waking the SoC from deep sleep**, most likely while USB-connected.

## Key test still to run
- Suspend **on battery (USB unplugged)** vs plugged. Expectation: stays asleep unplugged,
  self-wakes when plugged → confirms the power-supply/Type-C wake path.
  - Result: _<fill in>_

## Questions for the maintainer
1. Are the `pmic_glink`/UCSI/`qcom-battmgr` power-supply wakeup sources expected to be armed
   during suspend on SM8550, or should they be disarmed on RP6 (analogous to the TSENS
   uplow-wake fix)?
2. Known behavior on the AYN Thor when charging / USB-connected during suspend?
3. Is there a preferred way to mask the pmic_glink power-supply wakeups for s2idle/deep on
   these handhelds (DT `wakeup-source`, `/sys/.../power/wakeup`, or a driver-level change)?
