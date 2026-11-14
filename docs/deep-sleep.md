# Wi-Fi off while the device sleeps

Nights are where a handheld loses its charge. On the Retroid Pocket 5 the device does enter
`s2idle`, but the Wi-Fi radio keeps drawing while it does, and it is about half of the
standby draw.

The sm8250 board package now drops the radio for the suspend window: two hooks in the sleep.d
set block every `wlan` radio that is currently on, record which ones they changed, and
restore exactly those on resume. A radio you had already switched off stays off, and Bluetooth
is untouched, so controllers keep pairing.

## What it is worth

Measured on a Retroid Pocket 5 over unplugged suspend windows, using the fuel gauge
(`charge_now`) before and after each sleep:

| Configuration | Sleep rate | Battery per hour |
| --- | --- | --- |
| Wi-Fi left on | ~104 mA (~400 mW) | ~2 % |
| Wi-Fi off while asleep | ~52 mA | ~1 % |

The gauge reports in steps of 50 mAh, so a single window carries about ±25 %; the figures above
are ten-hour windows.

## Trade-offs

- No downloads, updates or wake-on-WLAN while the device is asleep: the radio is off.
- Wi-Fi returns a few seconds after wake, about the same delay a normal resume already has.

## Undoing it

Remove or make non-executable `/usr/lib/pocknix/sleep.d/pre/005-sleep-power` and
`/usr/lib/pocknix/sleep.d/post/005-sleep-power` in the sm8250 board package; nothing else
reads state they write.

Note one naming trap: this device only offers `s2idle` for suspend; what these hooks do is
about the radio, not about the kernel's `deep` state.
