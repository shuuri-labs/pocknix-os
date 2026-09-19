import copy
import json
import math
import threading
import time
import urllib.request
from pathlib import Path

from .system import atomically_write

# Stick RGB rings are multicolor LED-class devices; sysfs resets on reboot, so state is
# persisted here and re-applied from Plugin._main on load. Same multi_intensity/brightness
# ABI on both node layouts: RP6/RP5/Flip 2 name four ring segments per stick as
# rgb:l1..l4 / rgb:r1..r4, Odin 2 names one node per stick (left-joystick, right-joystick).
LED_CONFIG = Path("/etc/pocknix/led.json")
LED_CLASS_DIR = Path("/sys/class/leds")

# The QAM flushes both sticks' pending edits in one tick on close, and the boot pulse runs
# on its own thread: every config read-modify-write, effect lifecycle op and sysfs apply
# happens under this.
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
    "bootPulse": True,
    "left": {"r": 0, "g": 200, "b": 255, "brightness": 180},
    "right": {"r": 0, "g": 200, "b": 255, "brightness": 180},
}

WHITE = (255, 255, 255)


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
    clean["bootPulse"] = bool(data.get("bootPulse", DEFAULTS["bootPulse"]))
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


def _segment_caps(leds):
    # Channel order and max brightness are fixed by the driver, so resolve them once per
    # apply rather than re-reading sysfs on every frame of a 30 fps ramp.
    caps = []
    for led in leds:
        try:
            names = (led / "multi_index").read_text(encoding="utf-8").split()
        except OSError:
            names = ["red", "green", "blue"]
        try:
            max_brightness = int((led / "max_brightness").read_text(encoding="utf-8").strip())
        except (OSError, ValueError):
            max_brightness = 255
        caps.append((led, max_brightness, names))
    return caps


def _write_rgb(cap, rgb, brightness):
    led, max_brightness, names = cap
    named = {"red": rgb[0], "green": rgb[1], "blue": rgb[2]}
    intensity = " ".join(str(named.get(name, 0)) for name in names)
    value = max(0, min(max_brightness, brightness))
    try:
        (led / "multi_intensity").write_text(intensity + "\n", encoding="utf-8")
        (led / "brightness").write_text(f"{value}\n", encoding="utf-8")
    except OSError:
        pass


def _write_brightness(cap, brightness):
    led, max_brightness, _ = cap
    value = max(0, min(max_brightness, brightness))
    try:
        (led / "brightness").write_text(f"{value}\n", encoding="utf-8")
    except OSError:
        pass


def _apply_caps_rgb(caps, rgb, brightness):
    for cap in caps:
        _write_rgb(cap, rgb, brightness)


def _apply_caps_brightness(caps, brightness):
    for cap in caps:
        _write_brightness(cap, brightness)


# A background thread may drive the rings (the boot pulse). Setters stop any running effect
# before applying a static state, so the user's choice always wins.
_effect_thread = None
_effect_stop = threading.Event()


def _stop_effect():
    # Caller holds _LOCK. The pulse thread never acquires _LOCK (it polls _effect_stop),
    # so joining it here cannot deadlock.
    global _effect_thread
    t = _effect_thread
    if t is not None and t is not threading.current_thread() and t.is_alive():
        _effect_stop.set()
        t.join(timeout=2.0)
    _effect_stop.clear()
    _effect_thread = None


def _apply_static(data):
    # Resolves nodes per call: the effect may have just been stopped, and the driver
    # can still be probing on a fresh boot.
    ring_caps = _segment_caps(_segments("left") + _segments("right"))
    side_caps = _segment_caps(_side_segments("left") + _side_segments("right"))
    if not data["enabled"]:
        _apply_caps_brightness(ring_caps + side_caps, 0)
        return
    left = data["left"]
    right = data["right"] if not data["linked"] else left
    left_ring_caps = _segment_caps(_segments("left"))
    right_ring_caps = _segment_caps(_segments("right"))
    _apply_caps_rgb(left_ring_caps, _rgb(left), left["brightness"])
    _apply_caps_rgb(right_ring_caps, _rgb(right), right["brightness"])
    if data["sides"]:
        left_side_caps = _segment_caps(_side_segments("left"))
        right_side_caps = _segment_caps(_side_segments("right"))
        _apply_caps_rgb(left_side_caps, _rgb(left), left["brightness"])
        _apply_caps_rgb(right_side_caps, _rgb(right), right["brightness"])
    else:
        _apply_caps_brightness(side_caps, 0)


PULSE_FRAME = 1.0 / 30.0
PULSE_MAX_WAIT = 120.0
# The gamepad UI shows up in CEF's target list as a tab named "SP" pointing at the
# steamloopback host, the same predicate upstream Decky's injector blocks on
# (/json/version responds too early, mid-splash).
CEF_TABS_URL = "http://127.0.0.1:8080/json"
GAMEPADUI_TITLES = ("SP", "Steam", "SharedJSContext")
GAMEPADUI_URL_HINTS = ("steamloopback.host/routes/", "steamloopback.host/index.html")


def _gamepadui_tab_up():
    try:
        with urllib.request.urlopen(CEF_TABS_URL, timeout=1.0) as response:
            tabs = json.loads(response.read().decode("utf-8"))
    except Exception:
        return False
    if not isinstance(tabs, list):
        return False
    for tab in tabs:
        if not isinstance(tab, dict):
            continue
        title = str(tab.get("title", ""))
        url = str(tab.get("url", ""))
        if title in GAMEPADUI_TITLES and any(hint in url for hint in GAMEPADUI_URL_HINTS):
            return True
    return False


def _in_game_mode():
    # In a Plasma desktop session Steam never starts, so the readiness probe would stall
    # until the timeout. Nothing records the session choice, so detect it from /proc and
    # default to game mode when uncertain (the common boot path).
    try:
        comms = set()
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                comms.add((entry / "comm").read_text(encoding="utf-8").strip())
            except OSError:
                continue
    except OSError:
        return True
    # ksmserver/plasmashell are Plasma-only; kwin alone is ambiguous (gamescope can
    # nest it), so it only counts alongside a Plasma shell.
    if "plasmashell" in comms or ("kwin_wayland" in comms and "ksmserver" in comms):
        return False
    return True


def _ramp(caps, peak):
    # Sin-eased brightness 0 -> peak -> 0 over half a second; bails as soon as stopped.
    steps = int(round(0.5 / PULSE_FRAME))
    for half in (0, 1):
        for i in range(steps):
            if _effect_stop.is_set():
                return
            t = i / (steps - 1)
            eased = t if half == 0 else 1 - t
            _apply_caps_brightness(caps, int(round(peak * (1 - math.cos(math.pi * eased)) / 2)))
            _effect_stop.wait(PULSE_FRAME)


def _handoff_to_user(data, left_rings, right_rings, left_sides, right_sides):
    # White pulses out, then each side ramps its own saved colour up from 0: left and right
    # may differ, and side strips follow their stick behind the sides toggle. Lights the
    # user keeps off stay off from here on.
    if _effect_stop.is_set():
        return
    rings = left_rings + right_rings
    sides = left_sides + right_sides
    _ramp(rings + sides, 100)
    if _effect_stop.is_set():
        return
    if not data["enabled"]:
        _apply_caps_brightness(rings + sides, 0)
        return
    left = data["left"]
    right = data["right"] if not data["linked"] else left
    _apply_caps_rgb(left_rings, _rgb(left), 0)
    _apply_caps_rgb(right_rings, _rgb(right), 0)
    if data["sides"]:
        _apply_caps_rgb(left_sides, _rgb(left), 0)
        _apply_caps_rgb(right_sides, _rgb(right), 0)
    else:
        _apply_caps_brightness(sides, 0)
    steps = int(round(0.5 / PULSE_FRAME))
    for i in range(steps):
        if _effect_stop.is_set():
            return
        t = i / (steps - 1)
        eased = (1 - math.cos(math.pi * t)) / 2
        _apply_caps_rgb(left_rings, _rgb(left), int(left["brightness"] * eased))
        _apply_caps_rgb(right_rings, _rgb(right), int(right["brightness"] * eased))
        if data["sides"]:
            _apply_caps_rgb(left_sides, _rgb(left), int(left["brightness"] * eased))
            _apply_caps_rgb(right_sides, _rgb(right), int(right["brightness"] * eased))
        _effect_stop.wait(PULSE_FRAME)


def _boot_pulse_loop():
    global _effect_thread
    data = _load()
    left_rings = _segment_caps(_segments("left"))
    right_rings = _segment_caps(_segments("right"))
    left_sides = _segment_caps(_side_segments("left"))
    right_sides = _segment_caps(_side_segments("right"))
    rings = left_rings + right_rings
    sides = left_sides + right_sides
    # Side strips pulse with the rings only when the user keeps them on.
    pulse_caps = rings + (sides if data["sides"] else [])
    _apply_caps_rgb(pulse_caps, WHITE, 0)
    start = time.monotonic()
    steam_up = False
    # The probe runs at the bottom of each cycle, while the rings are fully off, so its
    # blocking fetch is invisible.
    while True:
        if _effect_stop.is_set():
            _effect_thread = None
            return
        if steam_up or time.monotonic() - start > PULSE_MAX_WAIT:
            break
        _ramp(pulse_caps, 100)
        if _effect_stop.is_set():
            _effect_thread = None
            return
        # Re-checked every cycle: the loader can start before Plasma, so a game-mode verdict
        # at init can flip a few seconds in, and a desktop session has no Steam to wait for.
        if not _in_game_mode():
            break
        if _gamepadui_tab_up():
            steam_up = True
    _handoff_to_user(data, left_rings, right_rings, left_sides, right_sides)
    _effect_thread = None


def start_boot_pulse():
    with _LOCK:
        global _effect_thread
        if _effect_thread is not None and _effect_thread.is_alive():
            return
        _stop_effect()
        _effect_thread = threading.Thread(target=_boot_pulse_loop, name="led-boot-pulse", daemon=True)
        _effect_thread.start()


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
        _stop_effect()
        _apply_static(data)
        return _with_available(data)


def set_led_linked(linked):
    with _LOCK:
        data = _load()
        data["linked"] = bool(linked)
        if data["linked"]:
            data["right"] = copy.deepcopy(data["left"])
        _save(data)
        _stop_effect()
        _apply_static(data)
        return _with_available(data)


def set_led_enabled(enabled):
    with _LOCK:
        data = _load()
        data["enabled"] = bool(enabled)
        _save(data)
        _stop_effect()
        _apply_static(data)
        return _with_available(data)


def set_led_sides(sides):
    with _LOCK:
        data = _load()
        data["sides"] = bool(sides)
        _save(data)
        _stop_effect()
        _apply_static(data)
        return _with_available(data)


def set_boot_pulse(enabled):
    with _LOCK:
        data = _load()
        data["bootPulse"] = bool(enabled)
        _save(data)
        return _with_available(data)


def init_leds():
    # Plugin._main entry. The pulse is boot feedback, so it runs whether or not the lights
    # are on; the saved state only takes over at the handoff. The pulse thread resolves its
    # own nodes, so no lock is held while it runs.
    if not _available():
        return
    data = _load()
    if data["bootPulse"] and _in_game_mode():
        start_boot_pulse()
    else:
        with _LOCK:
            _stop_effect()
            _apply_static(data)
