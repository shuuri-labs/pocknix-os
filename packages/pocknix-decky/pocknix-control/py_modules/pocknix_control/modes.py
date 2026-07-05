from pathlib import Path

from .system import atomically_write, run_cmd

# Both mode files live in /var/lib/pocknix and hold one bare word; both daemons treat an
# unknown/absent value as the default, so a bad write degrades gracefully.
FAN_MODE_FILE = Path("/var/lib/pocknix/fan-mode")
LAVD_MODE_FILE = Path("/var/lib/pocknix/lavd-mode")

FAN_MODES = ("quiet", "moderate", "performance")
FAN_DEFAULT = "quiet"
LAVD_MODES = ("autopilot", "performance")
LAVD_DEFAULT = "autopilot"


def _read_mode(path, allowed, default):
    try:
        mode = path.read_text(encoding="utf-8").strip()
    except OSError:
        return default
    return mode if mode in allowed else default


def fan_mode():
    return _read_mode(FAN_MODE_FILE, FAN_MODES, FAN_DEFAULT)


def lavd_mode():
    # pocknix-lavd-mode also accepts balanced/powersave for experiments; the UI only
    # offers autopilot/performance, so map anything else back to the default.
    return _read_mode(LAVD_MODE_FILE, LAVD_MODES, LAVD_DEFAULT)


def set_fan_mode(mode):
    if mode not in FAN_MODES:
        raise ValueError(f"unknown fan mode: {mode!r}")
    # pocknix-fancontrol re-reads this file every curve tick (~3s); no restart needed.
    atomically_write(FAN_MODE_FILE, mode + "\n", 0o644)


def set_lavd_mode(mode):
    if mode not in LAVD_MODES:
        raise ValueError(f"unknown lavd mode: {mode!r}")
    # The helper persists the mode and restarts pocknix-lavd.service (live scheduler swap).
    proc = run_cmd(["/usr/local/bin/pocknix-lavd-mode", mode], timeout=30)
    if proc is None:
        raise RuntimeError("pocknix-lavd-mode failed to spawn")
    if proc.returncode != 0:
        raise RuntimeError(f"pocknix-lavd-mode failed (rc={proc.returncode}): {(proc.stderr or '').strip()[:300]}")
