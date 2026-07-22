# Android apps (Waydroid)

pocknix-os can run Android apps through **Waydroid**. Each app opens as its own fullscreen
window in the Plasma Mobile desktop session, so it behaves much like a native app.

## First-time setup

Waydroid needs a one-time init to download its Android image. In the desktop session, open a
terminal and run:

```bash
sudo waydroid init
```

Then launch **Waydroid** from the app grid (or `waydroid session start`). The first boot takes
a minute or two.

## Installing apps

You have two easy options:

**Aurora Store (recommended).** Aurora is an open-source client for the Google Play catalog, so
you can browse and install the same apps you would from the Play Store, using anonymous sign-in.
Install its APK (see below) once, then use it like a store.

**Sideload an APK.** Download any `.apk` file, then open it from your file manager with
**Open With → Install with Waydroid**. It installs the app (starting a Waydroid session first if
needed) and adds a launcher shortcut automatically.

> To make the APK handler the default so a double-click just installs, run once:
> ```bash
> xdg-mime default waydroid-apk-install.desktop application/vnd.android.package-archive
> ```

## Google Play Store (optional)

Aurora is simpler and reaches the same catalog, but if you want the official Play Store it
works too. It needs a GApps Android image **plus a one-time Google device certification** -
until the device is certified, Google sign-in fails with "device is not Play Protect
certified".

1. Switch to the GApps image (**this wipes existing Android data** - see the warning below):
   ```bash
   sudo waydroid init -s GAPPS -f
   ```
2. Start a Waydroid session, then grab Waydroid's Android ID:
   ```bash
   sudo waydroid shell
   ANDROID_RUNTIME_ROOT=/apex/com.android.runtime ANDROID_DATA=/data \
   ANDROID_TZDATA_ROOT=/apex/com.android.tzdata ANDROID_I18N_ROOT=/apex/com.android.i18n \
   sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \
     "select * from main where name = \"android_id\";"
   ```
3. Signed in to your Google account, visit
   [google.com/android/uncertified](https://www.google.com/android/uncertified/), paste the
   number, and register it.
4. Give Google 10-20 minutes to process, then restart the Waydroid session and sign in to the
   Play Store normally.

Full details in the official
[Waydroid Google Play certification guide](https://docs.waydro.id/faq/google-play-certification).

## App shortcuts appear automatically

Every app you install, however you install it, automatically gets its own entry in the Plasma
Mobile app grid (Aurora, sideloaded APK, or Play Store all work the same way). Launch an Android
app from there just like any other app, and it opens in its own window. Waydroid's built-in
system apps stay hidden so they do not clutter your app list. No manual shortcut setup needed.

## Using apps

- Apps open fullscreen with an Android **back** button in the nav bar.
- Swipe or use the Plasma task switcher to move between apps (this doubles as Android Recents).
- Closing an app window returns you to the desktop.

## Files and storage

- Android's shared storage (`/sdcard`) lives under
  `~/.local/share/waydroid/data/media/0/`. Files an app downloads land there.
- Your Android data survives normally, but note that **re-running `waydroid init` wipes the
  Android data partition**, so back up anything important inside apps first.
