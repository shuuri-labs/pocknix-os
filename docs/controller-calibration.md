# Controller calibration

If a stick drifts when you let go of it, or doesn't reach the edge when you push it all the
way, calibrate it. Calibration measures each stick's centre and range and each trigger's
travel, then sets the controller driver to match. It stays in use after a restart.

## In Pocknix Tools

Open **Pocknix Tools** (game or desktop mode) and go to **Controller**.

- **Live readings**: the bars show what the sticks and triggers report right now. A stick at
  rest should read about 0, a full push about 100 (or -100 the other way), and a trigger 0% to
  100%. Use them to check your controller at any time.
- **Calibrate**: follow the steps on screen. You push each stick fully in each direction and
  hold it, then let go, and press each trigger all the way in, then let go. Each step moves on
  by itself once the reading has held still for a moment.
  - Your controller is paused for Steam while the steps run, so it can't control Pocknix Tools
    either: tap **Cancel** on the screen to stop. Cancelling, leaving the Controller page or
    closing Pocknix Tools puts everything back as it was.
- **Save** or **Discard**: when the steps are done, the new calibration is already in use and
  the readings show the result. Check the sticks and triggers, then **Save** to keep it, or
  **Discard** to go back to what you had.
- **Reset to Defaults**: deletes your saved calibration and returns to the controller's
  factory settings.

Finishing or cancelling a calibration, and resetting, reconnect the controller, so it stops
responding for about a second. That is how Steam picks up the new range.

Devices whose controller driver has no calibration settings show **This controller can't be
calibrated** instead.

## From a terminal

```bash
pocknix-gamepad-calibration status --json   # can this device calibrate, is one saved
sudo pocknix-gamepad-calibration live       # live readings until you press Ctrl+D
sudo pocknix-gamepad-calibration calibrate  # the guided steps; type save or discard at the end
sudo pocknix-gamepad-calibration recover    # give the controller back to Steam if a calibration was killed
sudo pocknix-gamepad-calibration reset      # back to the factory settings
```

The saved calibration is `/etc/pocknix/gamepad-calibration.conf`; it is applied at every
startup before Steam sees the controller.
