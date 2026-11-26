# Known issues

Things that are known not to work, or not to work well yet. Something missing from this list?
Ask on the [Discord](https://discord.gg/jEpwudj4Fx) or open an issue.

## Steam and game mode

- **Game mode can take a long time to come up.** On first boot, or after a Steam client update,
  Steam can take a *long* while to get ready, especially when running from an SD card. The
  pocknix wordmark stays on screen while it does; a short black gap before the wordmark appears
  is normal. Leave the device alone and it will get there.
- **Steam's "Add a Non-Steam Game" dialog does not work.** Use **Pocknix Control → Add Game** to add
  one instead.
- **MangoHud costs a little performance.** It is fine for dialing in settings, but turn it off
  for real play. Honestly, consider this a feature: stop staring at the numbers and enjoy the
  game 😃

## Hardware

- **Gyro is only enabled on the AYN Odin 2 Mini so far.** Other boards have not had their ADSP
  sensor axis maps verified yet, so the gyro bridge stays dormant on them.
- **2026 Retroid Pocket 5 / Flip 2 units (12 GB) stay black on first boot.** These have a
  different display panel that pocknix cannot detect before the screen comes up. The fix is
  picking the Visionox device model in the bootloader menu: see
  [newer RP5 / Flip 2 panels](install.md#newer-rp5--flip-2-panels).
