# SM8550 (Retroid Pocket 6) — spurious wake from deep suspend

Findings from on-device testing, to share with the SM8550 suspend/resume maintainer.

## Environment
- Kernel **7.0.11** = ROCKNIX SM8550 + `thor-suspend-fixes` + RP6 delta (built fresh, GCC 16.1).
- **Retroid Pocket 6**, minimal Arch Linux ARM userland (pocknix-os), booted from SD.
- `/sys/power/mem_sleep` = `s2idle [deep]` (deep selected via `mem_sleep_default=deep`).

## Symptom
Spontaneous wake from **deep** suspend, untouched, **on battery (USB unplugged)**:
```
PM: suspend entry (deep)
  (~3.4 s later, no user input)
PM: suspend exit
```
**Intermittent** — some cycles stay asleep until the power key; others self-wake in a few
seconds (so it's event-driven, not a fixed-period timer). Occurs **on battery**, so it is not
charging-related — the power-supply subsystem wakes the SoC even with nothing plugged in.

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
wake delivered via pmic_glink/RPMSG rather than a GIC IRQ. Since this happens **on battery**,
the cause is the power-supply/battery-manager status path itself (periodic battery/charger
notifications over pmic_glink), **not** charging — the SoC won't stay in deep sleep unplugged.

> Caveat: `wakeup_sources` counters are cumulative since boot, so the snapshot above doesn't
> prove which source fired *during the suspend*. The diff test below attributes it precisely.

## Key test to attribute the exact source
Snapshot `wakeup_sources` around a single self-waking suspend and diff — the source whose
`active_count`/`event_count` increments is the culprit:
```sh
cat /sys/kernel/debug/wakeup_sources > /tmp/ws.before
systemctl suspend          # let it self-wake (don't touch it)
cat /sys/kernel/debug/wakeup_sources > /tmp/ws.after
diff /tmp/ws.before /tmp/ws.after
```
- Result: _<fill in — which source incremented>_

## Questions for the maintainer
1. On battery, the `pmic_glink`/UCSI/`qcom-battmgr`/`battery` power-supply wakeup sources
   appear to wake the SoC from deep sleep. Are they expected to be armed during suspend on
   SM8550, or should they be disarmed on RP6 (analogous to the TSENS uplow-wake fix)?
2. Known behavior on the AYN Thor — does it stay in deep sleep on battery, or see the same
   pmic_glink power-supply wakes?
3. Preferred way to mask the pmic_glink power-supply wakeups for s2idle/deep on these
   handhelds (DT `wakeup-source`, `/sys/.../power/wakeup`, or a driver-level change)?
