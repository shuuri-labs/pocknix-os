import os
import threading
from pathlib import Path

from .tweaks import load_tweaks, settings_for

# "<pid> <fan> <lavd>", written by pocknix-game-launch at every launch; pocknix-fancontrol and
# pocknix-lavd-mode poll it, so rewriting it applies a per-game pick to the running game.
GAME_MODE_FILE = Path("/run/pocknix/game-mode")
FAN_MODES = ("quiet", "moderate", "performance")
LAVD_MODES = ("autopilot", "performance", "balanced", "powersave")
_lock = threading.Lock()


def _pick(value, allowed):
    value = str(value or "").strip()
    return value if value in allowed else "-"


def running_game(record, proc=Path("/proc")):
    # The launcher execs Steam's chain in place, so its pid keeps reaper's AppId= while the game
    # runs; a dead or reused pid has none and leaves the record alone.
    fields = record.split()
    if len(fields) != 3 or not fields[0].isdigit():
        return None, None
    try:
        args = (proc / fields[0] / "cmdline").read_bytes().decode(errors="replace").split("\0")
    except OSError:
        return None, None
    for arg in args:
        if arg.startswith("AppId=") and arg[6:].isdigit():
            return fields[0], arg[6:]
    return None, None


def sync_game_mode(path=GAME_MODE_FILE, proc=Path("/proc")):
    with _lock:
        _sync(path, proc)


def _sync(path, proc):
    try:
        record = path.read_text(encoding="utf-8")
        st = path.stat()
    except OSError:
        return
    pid, appid = running_game(record, proc)
    if not pid:
        return
    settings = settings_for(load_tweaks(), appid)
    line = f"{pid} {_pick(settings.get('fanMode'), FAN_MODES)} {_pick(settings.get('lavdMode'), LAVD_MODES)}\n"
    if line == record:
        return
    # Keeps the launcher's ownership: it runs as deck and must overwrite this file next launch.
    tmp = path.with_name(f".{path.name}.tmp")
    try:
        tmp.write_text(line, encoding="utf-8")
        os.chown(tmp, st.st_uid, st.st_gid)
        os.chmod(tmp, 0o644)
        # A game launched since the read owns the record now; ours would point the daemons at a dead pid.
        if path.read_text(encoding="utf-8") != record:
            tmp.unlink(missing_ok=True)
            return
        os.replace(tmp, path)
    except OSError as exc:
        print(f"pocknix-control: failed to update the running game's mode: {exc}")
        tmp.unlink(missing_ok=True)
