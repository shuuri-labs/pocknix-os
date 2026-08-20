import copy
import json
import threading
from pathlib import Path

from .system import atomically_write

# Stick RGB rings are multicolor LED-class devices; sysfs resets on reboot, so state is
# persisted here and re-applied from Plugin._main on load. Same multi_intensity/brightness
# ABI on both node layouts: RP6/RP5/Flip 2 name four ring segments per stick as
# rgb:l1..l4 / rgb:r1..r4, Odin 2 names one node per stick (left-joystick, right-joystick).
LED_CONFIG = Path("/etc/pocknix/led.json")
LED_CLASS_DIR = Path("/sys/class/leds")

# The QAM flushes both sticks' pending edits in one tick on close, so setters land concurrently.
_LOCK = threading.Lock()


def _segments(side):
    # Probed per call, not at import: plugin load can precede the LED driver.
    segs = sorted(LED_CLASS_DIR.glob(f"rgb:{side[0]}[0-9]*"))
    if segs:
        return segs
    node = LED_CLASS_DIR / f"{side}-joystick"
    return [node] if node.is_dir() else []


def _side_segments(side):
    node = LED_CLASS_DIR / f"{side}-side"
    return [node] if node.is_dir() else []


def _available():
    return bool(_segments("left") or _segments("right"))


def _sides_available():
    return bool(_side_segments("left") or _side_segments("right"))


DEFAULTS = {
    "enabled": False,
    "linked": True,
    "sides": True,
    "left": {"r": 0, "g": 200, "b": 255, "brightness": 180},
    "right": {"r": 0, "g": 200, "b": 255, "brightness": 180},
}


def _clamp_byte(value):
    try:
        n = int(value)
    except (TypeError, ValueError):
        return 0
    return max(0, min(255, n))


def _rgb(side):
    return (side["r"], side["g"], side["b"])


def _sanitize(data):
    clean = copy.deepcopy(DEFAULTS)
    if not isinstance(data, dict):
        return clean
    clean["enabled"] = bool(data.get("enabled", DEFAULTS["enabled"]))
    clean["linked"] = bool(data.get("linked", DEFAULTS["linked"]))
    clean["sides"] = bool(data.get("sides", DEFAULTS["sides"]))
    for side in ("left", "right"):
        src = data.get(side)
        if isinstance(src, dict):
            clean[side] = {
                "r": _clamp_byte(src.get("r", DEFAULTS[side]["r"])),
                "g": _clamp_byte(src.get("g", DEFAULTS[side]["g"])),
                "b": _clamp_byte(src.get("b", DEFAULTS[side]["b"])),
                "brightness": _clamp_byte(src.get("brightness", DEFAULTS[side]["brightness"])),
            }
    return clean


def _load():
    try:
        return _sanitize(json.loads(LED_CONFIG.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        return copy.deepcopy(DEFAULTS)


def _save(data):
    atomically_write(LED_CONFIG, json.dumps(data, indent=2, sort_keys=True) + "\n", 0o644)


def _write_segment(led, rgb, brightness):
    # multi_intensity is laid out in the channel order named by multi_index, which
    # isn't always R G B (the Retroid Pocket 6 is blue green red).
    try:
        names = (led / "multi_index").read_text(encoding="utf-8").split()
    except OSError:
        names = ["red", "green", "blue"]
    named = {"red": rgb[0], "green": rgb[1], "blue": rgb[2]}
    intensity = " ".join(str(named.get(name, 0)) for name in names)
    try:
        max_brightness = int((led / "max_brightness").read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        max_brightness = 255
    value = max(0, min(max_brightness, brightness))
    (led / "multi_intensity").write_text(intensity + "\n", encoding="utf-8")
    (led / "brightness").write_text(f"{value}\n", encoding="utf-8")


def _apply_side(segments, rgb, brightness):
    for led in segments:
        try:
            _write_segment(led, rgb, brightness)
        except OSError:
            pass


def _apply_config(data):
    left_leds = _segments("left")
    right_leds = _segments("right")
    left_sides = _side_segments("left")
    right_sides = _side_segments("right")
    if not data["enabled"]:
        for led in left_leds + right_leds + left_sides + right_sides:
            try:
                (led / "brightness").write_text("0\n", encoding="utf-8")
            except OSError:
                pass
        return
    left = data["left"]
    right = data["right"] if not data["linked"] else left
    _apply_side(left_leds, _rgb(left), left["brightness"])
    _apply_side(right_leds, _rgb(right), right["brightness"])
    if data["sides"]:
        _apply_side(left_sides, _rgb(left), left["brightness"])
        _apply_side(right_sides, _rgb(right), right["brightness"])
    else:
        for led in left_sides + right_sides:
            try:
                (led / "brightness").write_text("0\n", encoding="utf-8")
            except OSError:
                pass


def _with_available(data):
    data["available"] = _available()
    data["sidesAvailable"] = _sides_available()
    return data


def led_config():
    return _with_available(_load())


def set_led(side, r, g, b, brightness):
    if side not in ("left", "right", "both"):
        raise ValueError(f"unknown led side: {side!r}")
    rgb = {"r": _clamp_byte(r), "g": _clamp_byte(g), "b": _clamp_byte(b), "brightness": _clamp_byte(brightness)}
    with _LOCK:
        data = _load()
        if side == "both":
            data["left"] = copy.deepcopy(rgb)
            data["right"] = copy.deepcopy(rgb)
        else:
            data[side] = rgb
        _save(data)
        _apply_config(data)
        return _with_available(data)


def set_led_linked(linked):
    with _LOCK:
        data = _load()
        data["linked"] = bool(linked)
        if data["linked"]:
            data["right"] = copy.deepcopy(data["left"])
        _save(data)
        _apply_config(data)
        return _with_available(data)


def set_led_enabled(enabled):
    with _LOCK:
        data = _load()
        data["enabled"] = bool(enabled)
        _save(data)
        _apply_config(data)
        return _with_available(data)


def set_led_sides(sides):
    with _LOCK:
        data = _load()
        data["sides"] = bool(sides)
        _save(data)
        _apply_config(data)
        return _with_available(data)


def restore_led():
    with _LOCK:
        if _available():
            _apply_config(_load())
