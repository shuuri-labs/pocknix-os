# Android apps in Gaming mode (Lepton)

pocknix-os runs Android apps (`.apk` files) straight from your Steam library in Gaming mode
through **Lepton**, Steam's Android compatibility tool. Each app runs fullscreen with touch
and an on-screen keyboard. In the desktop session, use [Waydroid](waydroid.md) instead.

## Adding an app

1. Put the APK in a folder of its own, for example `~/Apps/Findroid/Findroid.apk`. An APK
   placed directly in your home folder won't start.
2. Add it with **Pocknix Control → Library → Add Non-Steam Game** (see
   [Adding non-Steam games](pocknix-control.md#adding-non-steam-games)). Leave **Launch with
   Proton** off.
3. In the app's **Properties → Compatibility**, tick **Force the use of a specific Steam Play
   compatibility tool** and pick **Lepton**. Steam downloads Lepton the first time.
4. Launch it from your library like any game. The first launch takes longer while Android
   boots and installs the app.
