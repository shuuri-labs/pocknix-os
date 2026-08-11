import copy
import json
import sys
import threading
from pathlib import Path

from ..system import atomically_write
from . import _colour

LED_CONFIG = Path("/etc/pocknix/led.json")

# The QAM flushes both sticks' pending edits in one tick on close, and the boot pulse
# runs on its own thread — every config read-modify-write, effect lifecycle op, and
# sysfs apply runs under this.
LOCK = threading.RLock()

# A background thread drives the rings: the boot pulse, or a reactive mode's monitor.
# Setters stop any running effect before applying a new state, so the user's choice
# always wins.
effect_thread = None
effect_stop = threading.Event()

# Side strips can run an independent reactive monitor (battery/temperature) alongside
# the ring thread — the two write disjoint sysfs nodes, so there's no write conflict.
side_thread = None
side_stop = threading.Event()

# Side modes available where side-strip nodes exist. "match" mirrors the ring mode;
# "off" is the explicit dark state (replaces the old sides: bool toggle).
SIDE_MODES = ("off", "match", "static", "battery", "temperature")


def stop_effect():
    # Caller holds LOCK. The monitor/pulse thread acquires LOCK for snapshots, so we
    # must release it before joining to avoid a deadlock (monitor blocked on LOCK
    # acquire while we're blocked on join). After the join, reacquire.
    global effect_thread
    t = effect_thread
    if t is not None and t is not threading.current_thread() and t.is_alive():
        effect_stop.set()
        LOCK.release()
        try:
            t.join(timeout=2.0)
        finally:
            LOCK.acquire()
    effect_stop.clear()
    effect_thread = None


def stop_side():
    # Mirror of stop_effect for the side-strip monitor.
    global side_thread
    t = side_thread
    if t is not None and t is not threading.current_thread() and t.is_alive():
        side_stop.set()
        LOCK.release()
        try:
            t.join(timeout=2.0)
        finally:
            LOCK.acquire()
    side_stop.clear()
    side_thread = None


# Base defaults shared by every mode; mode-specific entries are merged in by the
# conductor from the registry. left/right are the static-mode ring colour store; "side"
# is the side-static colour store.
BASE_DEFAULTS = {
    "enabled": False,
    "bootPulse": True,
    "linked": True,
    "mode": "static",
    "sideMode": "match",
    "modeBrightness": 255,
    "sideBrightness": 255,
    "left": {"r": 0, "g": 200, "b": 255, "brightness": 180},
    "right": {"r": 0, "g": 200, "b": 255, "brightness": 180},
    "side": {"r": 0, "g": 200, "b": 255, "brightness": 180},
}


def build_defaults(modes):
    # BASE_DEFAULTS + each mode's own defaults. The active mode's per-side store (linked,
    # modeBrightness, temp thresholds...) is contributed by its module.
    merged = copy.deepcopy(BASE_DEFAULTS)
    for mode in modes:
        for key, value in mode.defaults.items():
            merged[key] = copy.deepcopy(value)
    return merged


def _read_side(data, clean, key, defaults):
    src = data.get(key)
    if isinstance(src, dict):
        clean[key] = {
            "r": _colour.clamp_byte(src.get("r", defaults[key]["r"])),
            "g": _colour.clamp_byte(src.get("g", defaults[key]["g"])),
            "b": _colour.clamp_byte(src.get("b", defaults[key]["b"])),
            "brightness": _colour.clamp_byte(src.get("brightness", defaults[key]["brightness"])),
        }


def sanitize(data, modes):
    # Validate a raw dict against the schema. Base fields first, then each mode's own
    # sanitize callback mutates `clean` for its keys.
    defaults = build_defaults(modes)
    keys = {m.key for m in modes}
    clean = copy.deepcopy(defaults)
    if not isinstance(data, dict):
        return clean
    clean["enabled"] = bool(data.get("enabled", defaults["enabled"]))
    clean["bootPulse"] = bool(data.get("bootPulse", defaults["bootPulse"]))
    clean["linked"] = bool(data.get("linked", defaults["linked"]))
    # Shared by the rainbow/battery/temperature modes (no per-side brightness there).
    clean["modeBrightness"] = _colour.clamp_byte(data.get("modeBrightness", defaults["modeBrightness"]))
    clean["sideBrightness"] = _colour.clamp_byte(data.get("sideBrightness", defaults["sideBrightness"]))
    mode = data.get("mode", defaults["mode"])
    clean["mode"] = mode if mode in keys else defaults["mode"]
    # sideMode, with migration from the legacy sides: bool toggle and from the removed
    # sideLinked: if sideMode is "static" but sideLinked was True, migrate to "match".
    if "sideMode" in data:
        sm = data["sideMode"]
        if sm == "static" and data.get("sideLinked", False):
            sm = "match"
        clean["sideMode"] = sm if sm in SIDE_MODES else defaults["sideMode"]
    elif "sides" in data:
        clean["sideMode"] = "match" if bool(data["sides"]) else "off"
    for key in ("left", "right", "side"):
        _read_side(data, clean, key, defaults)
    for mode in modes:
        if mode.sanitize is not None:
            mode.sanitize(data, clean)
    return clean


def load(modes):
    try:
        return sanitize(json.loads(LED_CONFIG.read_text(encoding="utf-8")), modes)
    except (OSError, ValueError, TypeError) as exc:
        print(f"[led] config load failed ({exc}); using defaults", file=sys.stderr, flush=True)
        return build_defaults(modes)


def save(data):
    atomically_write(LED_CONFIG, json.dumps(data, indent=2, sort_keys=True) + "\n", 0o644)
