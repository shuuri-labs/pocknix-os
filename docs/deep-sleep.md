# Deep sleep (Wi-Fi off while asleep)

Nights are where a handheld loses its charge. On the Retroid Pocket 5 the device does enter
`s2idle`, but the Wi-Fi radio keeps drawing while it does. Deep sleep switches the radio off
for the duration of the suspend and back on when the device wakes.

Turn it on in Pocknix Tools: **Deep sleep (Wi-Fi off asleep)**. From a terminal the same
switch is `pocknix-deep-sleep on`, with `off` and `status` alongside. The setting lives in
`/etc/pocknix/deep-sleep`, so it survives reboots until it is turned off again.

The switch is sm8250 only: on sm8550 the radio driver already powers down in suspend and the
effect there is unmeasured.

## What it is worth

Measured on a Retroid Pocket 5 over unplugged suspend windows, using the fuel gauge
(`charge_now`) before and after each sleep:

| Configuration | Sleep rate | Battery per hour |
| --- | --- | --- |
| stock | ~104 mA (~400 mW) | ~2 % |
| stock, radio off while asleep | ~52 mA | ~1 % |

The gauge reports in steps of 50 mAh, so a single window carries about ±25 %; the figures
above are ten-hour windows.

The radio is roughly half of the standby draw, which is why this is the cheapest large win:
a configuration change rather than a driver rewrite.

## Trade-offs

- No downloads, updates or wake-on-WLAN while the device is asleep.
- Wi-Fi needs a few seconds to come back after waking, the same delay a normal resume already
  has.
- Bluetooth is left alone, so controllers keep pairing.

## How it works

The switch writes a marker file; two hooks in the sleep.d set act on it. The pre-suspend hook
blocks every `wlan` radio that is currently on and records which ones it changed; the
post-resume hook unblocks exactly those. A radio you had already switched off stays off.

Note one naming trap: this device only offers `s2idle` for suspend; the switch named here is
about the radio, not about the kernel's `deep` state.
