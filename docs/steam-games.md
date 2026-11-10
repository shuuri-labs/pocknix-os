# Steam games

Android apps can run from your Steam library too: see [Android apps](android-apps.md#gaming-mode-lepton).

## Launch options

Every game's Steam launch options (**Properties → General → Launch Options**) start out as
`pocknix-game-launch %command%`. `pocknix-game-launch` applies the game's
[Pocknix Control tweaks](pocknix-control.md#game-tweaks) at launch. If it goes missing,
Pocknix Control adds it back.

When you add your own launch options, keep this order:

1. **Environment variables** (`KEY=value`) first, before `pocknix-game-launch`.
2. **Wrapper programs** (like `mangohud`) next, either side of `pocknix-game-launch`.
3. **`pocknix-game-launch %command%`**
4. **Game arguments** last, after `%command%`.

```
WINEDLLOVERRIDES="icu=d" DOTNET_GCHeapHardLimit=0x400000000 pocknix-game-launch %command% --rendering-driver vulkan
```

An environment variable placed after `pocknix-game-launch` stops the game from starting.
A variable set in the launch options wins over the same variable set by Pocknix Control.

`pocknix-game-launch` always goes directly in front of `%command%`, even when `%command%` sits
inside quotes, as in launch options that rewrite the game's command:

```
echo "pocknix-game-launch %command%" | sed 's|isaac-ng.exe|REPENTOGONLauncher/REPENTOGONLauncher.exe|' | sh
```

## If a game won't run

### Try another Proton

Change the Proton a game runs on in Pocknix Control's **Proton Version** tweak, or in the
game's **Properties → Compatibility**. Try them in this order:

1. **Proton 11.0 (ARM64)**, the default.
2. **Proton Experimental (ARM64)**.
3. An x86 Proton (one without "ARM64" in its name), as a last resort. These run through x86
   translation, so expect lower performance.

### DirectX 12 games

If a DirectX 12 game doesn't launch, add this to its launch options:

```
VKD3D_FEATURE_LEVEL=12_1 pocknix-game-launch %command%
```

### Proton logs

To see why a game fails, turn on Proton logging:

```
PROTON_LOG=1 pocknix-game-launch %command%
```

The log is saved in your home folder as `~/steam-<APPID>.log`, where `<APPID>` is the game's
Steam ID. Remove `PROTON_LOG=1` when you're done, as logging slows the game down.
