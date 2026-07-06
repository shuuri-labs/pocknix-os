pocknix — Your Games Folder
===========================

This folder (~/Emulation) is where everything goes. Copy your files into the
matching subfolder and they are picked up automatically the next time ES-DE starts.

1. ROMS -> ~/Emulation/ROMs/<system>/
   Put each game in the folder for its system, e.g.
     ROMs/snes/    Super Nintendo games
     ROMs/psx/     PlayStation 1 games
     ROMs/ps2/     PlayStation 2 games
     ROMs/switch/  Nintendo Switch games
   (One subfolder per system was created for you. Empty systems stay hidden in the
   menu until you add a game.)

2. BIOS FILES -> ~/Emulation/BIOS/
   Some systems need original BIOS/firmware files. Every emulator looks here.
   Exact filenames matter:
     PS2:       rename your BIOS dump to  ps2-bios.bin
     PS1:       scph5501.bin (and friends) as dumped
     Dreamcast: dc/dc_boot.bin + dc/dc_flash.bin (note the dc subfolder)
     GBA:       gba_bios.bin (optional — improves accuracy)
   If a game won't boot, it's usually a missing or misnamed BIOS — the emulator's
   error message names the exact file it wants.

3. NINTENDO SWITCH KEYS
   Switch emulation needs your own prod.keys (and firmware). Put them in
   ~/Emulation/BIOS/ or, if the emulator asks for a specific location, the folder
   it names on first run.

4. GET IT INTO YOUR STEAM LIBRARY
   In ES-DE, press the Favorite button on any game to star it. Starred games are
   added to your Steam library automatically (in a "Pocknix" collection) — no manual
   setup. Un-star to remove it again. New/removed favorites appear next time you
   enter Game Mode.

Saves and save-states live in ~/Emulation/Saves and ~/Emulation/States, so a single
copy of this ~/Emulation folder is fully self-contained and portable.

MOVING YOUR ROMS (e.g. to an SD card): ES-DE Menu -> Other Settings -> ROM directory,
pick the new location, move the files there. Everything else follows automatically.

You (and only you) are responsible for supplying game and BIOS files you legally own.
