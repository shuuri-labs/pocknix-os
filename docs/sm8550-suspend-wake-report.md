# SM8550 (Retroid Pocket 6) — spurious wake from deep suspend

Findings from on-device testing, to share with the SM8550 suspend/resume maintainer.

> ## ✅ RESOLVED 2026-06-26 — the Layer-3 wake is FIXED in the kernel
>
> The residual ADSP/`BATTMGR_NOTIFICATION` wake (Layer 3 below) is the IPCC mailbox IRQ being
> `IRQF_NO_SUSPEND` — never masked during sleep, so the charger firmware's doorbell wakes the SoC.
> **The fix is one line: remove `IRQF_NO_SUSPEND` from `drivers/mailbox/qcom-ipcc.c`**, so the
> mailbox IRQ is masked during suspend like any other. Lifted verbatim from ROCKNIX's **SM8750
> (AYN Odin 3)** tree (`0504-wakeup-qcom-ipcc-remove-IRQF-NO-SUSPEND.patch`), which uses the same
> `battmgr`/`pmic_glink` charger model and sleeps fine. Ported to SM8550 (`kernel/patches/20-sm8550/`).
>
> **Verified on-device:** `suspend_stats` shows 2 clean ~14-min suspends, `CLOCK_BOOTTIME -
> CLOCK_MONOTONIC` = 1681 s suspended — no spurious wakes. The userspace workarounds this report
> documents (battery-wake hook, auto-resuspend) are now **removed as redundant**. What remains in
> `pocknix-bsp`: `001-inputplumber` (vhci suspend-veto fix — separate problem), `SuspendState=mem`,
> the power-key drop-in, and jaewun's foundation patches (UFS/TSENS/UART/rsinput).
>
> Cross-SoC context (why SM8550 was stuck): SM8250 uses the *old* direct-Linux charger (`SMB5`, normal
> maskable wakes → sleeps); SM8750 keeps the new charger but ships this IPCC patch → sleeps; SM8550
> had jaewun's foundation but was just *missing* the IPCC line. Worth upstreaming to jaewun's branch.
>
> Open/cosmetic: `rsinput` (`serial1-0`) logs a `-110` resume timeout (version handshake), but the
> gamepad works fine after wake — SM8750's `0508` does a full re-init if we want it clean. And whether
> it truly *power-collapses* (CX retention) is unmeasured (this kernel lacks `last_hw_sleep`); a
> battery-drain test would tell. Neither blocks "stays asleep," which is solved.
>
> The three-layer investigation below is kept as the record of how we got here.

# ============================================================================
# 2026-06-25 INVESTIGATION SUMMARY (read this first)
# ============================================================================
#
# Running the same kernel under **pocknix** turned out to involve THREE distinct
# problems stacked on top of each other. The original report below (battery wake)
# is Layer 2. Don't conflate them — each was masking the next.

## Layer 1 — `vhci_hcd` vetoes suspend entirely (FIXED, userspace)

pocknix sets the InputPlumber `target_devices: [deck]`. The `deck` (Steam Deck) target
emulates the pad as a **virtual USB device over USB/IP (`vhci_hcd`)**. `vhci_hcd` hard-refuses
to suspend while any virtual device is attached:

```
vhci_hcd vhci_hcd.0: We have 1 active connection. Do not suspend.
vhci_hcd vhci_hcd.0: PM: failed to suspend: error -16   (-EBUSY)
PM: Some devices failed to suspend, or early wake event detected
PM: suspend exit
```

→ the whole system suspend aborts *before sleeping*. Signature: `echo mem > /sys/power/state`
returns `EBUSY` instantly; `pm_wakeup_irq` = ENODATA (nothing slept). ROCKNIX avoids this by
using the `ds5` target (uhid, not USB/IP).
**Fix:** `pocknix-bsp` sleep.d hook `001-inputplumber` stops InputPlumber before suspend
(detaching the vhci device) and restarts it on resume. (Alternative: switch the target to
`ds5`/`xb360`, both uhid.) Also pinned `SuspendState=mem` (`10-pocknix-deeponly.conf`) so
systemd doesn't fall deep→s2idle (s2idle can wedge on SM8550).

## Layer 2 — the `battery` power-supply wakeup (FIXED, userspace)

Once Layer 1 is fixed the device enters deep sleep, then self-wakes every ~5s. The
`wakeup_sources` diff attributes it cleanly to the **`battery`** source (its `active_count`
increments and nothing else does). This is the pmic_glink/ADSP charger firmware pushing
battery-status updates; `power_supply_changed()` does `pm_stay_awake()` on the battery psy.

KEY DIFFERENCE FROM THE OLD REPORT BELOW: on kernel **7.0.11** the `battery` wakeup source is
**attached to the psy device** (it appears in `/sys/class/wakeup/` with a `device` symlink to
`.../pmic-glink/.../power_supply/battery`). So writing `disabled` to
`/sys/class/power_supply/battery/power/wakeup` **unregisters** the wakeup source and the
`pm_stay_awake()` becomes a no-op. The old report found the toggle useless because on that
kernel `battery` was a free-standing source with no device toggle — not true here.
**Fix:** `pocknix-bsp` sleep.d hook `002-battery-wake` disables that toggle before suspend,
re-enables on resume. Effect: ~5s wakes → minutes between wakes (the ~5s was partly a
resume→re-query→re-notify feedback loop that this breaks).

## Layer 3 — the pmic_glink doorbell on the IPCC line (OPEN, kernel/firmware)

With Layer 2 fixed it still self-wakes every ~2–7 min (variable, e.g. 97/213/244/272/407s).
Methodically ruled OUT, one by one:

| Suspect | Test | Result |
|---|---|---|
| WiFi | suspend with `nmcli radio wifi off` | still woke (213s) — not WiFi (the `+36 mhi` per cycle is just resume-time radio re-init) |
| usb/wls/ucsi psy wakeups | disable `power/wakeup` on ALL power_supply devices | still woke (113s), **empty** `wakeup_sources` diff |
| TSENS thermal | `/proc/interrupts` diff + temps | critical IRQs (24/26/28, the only GIC-wake-armed) **never fire**; the uplow storm (IRQ 23/27, +30k) is intermittent and absent in cycles that still woke; temps well below the 110°C critical trip |
| InputPlumber/vhci | stopped for the test | n/a |

The empty `wakeup_sources` diff with everything disabled means the wake arrives **below** the
Linux wakeup-source layer. `/proc/interrupts` consistently shows the **co-processor comms**
ticking: `ipcc_0` (13), `glink-smem` (214), `apps_rsc` (14, RPMh). It's the **ADSP charger
firmware's pmic_glink "doorbell"**, delivered via IPCC.

**Why we can't just disarm it (the crux):** `drivers/mailbox/qcom-ipcc.c` requests the IPCC
interrupt with **`IRQF_NO_SUSPEND`** (line ~324) and the irqchip is **`IRQCHIP_SKIP_SET_WAKE`**
(line ~113). So the IPCC line is *deliberately never masked during suspend* (the AP must always
hear its co-processors — RPMh's sleep handshake uses this same line) and it **ignores
`enable_irq_wake`** entirely. There is no wake flag to flip, and masking IPCC would break the
ability to *enter* deep sleep. The TSENS/geni `disable_irq_wake`-on-suspend technique does not
apply here.

**`standby-wake-filter` does not exist** in ROCKNIX/distribution (grepped). That earlier lead
(MonsterRider) was an informal description, not a real mechanism. No distro has solved SM8550
deep-sleep; jaewun's patches are experimental and unmerged. We're on our own.

### Layer 3 — wake message CONFIRMED (2026-06-25)

The `1010-DEBUG-...` logging patch (a `dev_info` of every `qcom_battmgr_callback` opcode)
nailed it. Filtered `dmesg`:

```
[105.759] PM: suspend entry (deep)
[106.298] qcom_battmgr ... pocknix-wakedbg: rx opcode 0x7      <- the wake
[109.277] PM: suspend exit
```

The flood of `0x30` (`BATTMGR_BAT_PROPERTY_GET`) is just the driver polling while awake. The
**first unsolicited message after suspend entry is `0x7` = `BATTMGR_NOTIFICATION`** — the
charger firmware's push, which rings the `IRQF_NO_SUSPEND` IPCC line ~0.5s into sleep. So the
Layer-3 wake is definitively the ADSP `BATTMGR_NOTIFICATION`.

### Layer 3 — the two paths forward

1. **Kernel/firmware (the real fix, R&D — uncertain).** Stop the firmware from *sending* the
   `0x7` notification during suspend, since we can't mask the IPCC IRQ. `qcom_battmgr` subscribes
   via `BATTMGR_REQUEST_NOTIFICATION` (worker, all-zero `{battery_id, power_state, low_capacity,
   high_capacity}`) at probe and has **no PM ops** — it never unsubscribes, and the protocol has
   **no documented disable opcode** (the `enable` field I first cited is in the unrelated
   `charge_ctrl` struct). So a kernel fix means adding suspend/resume PM ops that re-subscribe
   with notification-suppressing params (e.g. capacity thresholds set to "never") and restore on
   resume — experimental, against undocumented firmware semantics. Kernel iterates cheaply via
   `pacman -U linux-pocknix` (alpm hook rebuilds `/flash/KERNEL`), no reflash, so it's tractable
   to try, but may not work.

2. **Auto-resuspend safety net (usable now).** `pocknix-bsp` sleep.d `004-auto-resuspend`:
   on resume, if the **power key did not fire** (compare the `pwrkey` count in `/proc/interrupts`
   across the sleep), the wake was the ADSP doorbell, not the user → `systemctl suspend` again
   after 3s. A real power-button wake increments `pwrkey` → stay awake. Fails OPEN (never
   re-suspends on a missing/ambiguous reading); escape hatch `touch /run/pocknix-no-resuspend`.
   Net cost: the device blips awake ~2–3s every few minutes — negligible overnight drain.
   Requires the power button to *wake-and-stay*, so `20-pocknix-powerkey.conf` sets
   `HandlePowerKey=ignore` (systemd's default `poweroff` made a wake-press shut the device down;
   long-press still powers off; sleep is invoked from Steam's power menu / `systemctl suspend`).

The original battery-wake report below is Layer 2; it remains accurate for that layer.

# ============================================================================

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
- Result — the `battery` source's counters increment across one self-waking suspend:
```
8c8
< battery       9   10    0   0   0   81    13    1662810   0
---
> battery       10    11    0   0   0   92    13    1724194   0
```

## `power/wakeup` is the wrong knob — `battery` is a *virtual* wakeup source
The `battery` source appears in `/sys/kernel/debug/wakeup_sources` but **not** in
`/sys/class/wakeup/` — i.e. it's a **virtual** wakeup source with **no `power/wakeup` toggle**.
Disabling `power/wakeup` had no effect at any level:
- on `battery` and on **all** `/sys/class/power_supply/*` → still self-wakes ~3.4 s
- on **every device-backed source in `/sys/class/wakeup/` except `pwrkey`** (rtc, alarmtimer,
  mhi0, gpio-keys, both remoteprocs) → still self-wakes ~3.5 s

So the wake is delivered via `pmic_glink`/glink (the charger firmware on the ADSP) as a virtual
wakeup that none of the `power/wakeup` knobs gate (consistent with `pm_wakeup_irq`=ENODATA).

**But this is reportedly fixable in userspace** — another ROCKNIX tester (MonsterRider) on the
same SM8550 suspend patches: *"tsensors had to be disabled in the kernel, but the rest (battery,
charging, charger detect, gpio) could be disabled in userspace via **standby-wake-filter**."*
So the correct mechanism is `standby-wake-filter` (not `power/wakeup`); we're obtaining its exact
sysfs path/command. Likely a userspace fix after all — **not** confirmed kernel-level.

## Open questions
1. What exactly is **`standby-wake-filter`** (sysfs path / command / script)? It reportedly
   disarms the battery/charging/charger-detect/gpio wakes in userspace on this SoC.
2. Known behavior on the AYN Thor — does it stay in deep sleep on battery with that filter
   applied?
3. (If a kernel angle is still wanted) where would the battery/pmic_glink wake be disarmed —
   the `qcom-battmgr`/pmic_glink driver, the SPMI/PMIC IRQ, or DT?

> Status: likely a **userspace** fix via `standby-wake-filter` (per MonsterRider). Obtaining
> the exact mechanism, then it'll go into `pocknix-bsp`'s `sleep.d/pre` hook.
