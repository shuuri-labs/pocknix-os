import copy
import threading

from . import _colour, _renderer, _state, _sysfs, _targets
from .modes import MODES, by_key, reactive_mode

LED_MODES = tuple(m.key for m in MODES)
SIDE_MODES = _state.SIDE_MODES


def _safe_int(value, default):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _with_available(data):
    data["available"] = _sysfs.available()
    data["sidesAvailable"] = _sysfs.sides_available()
    data["rainbowAvailable"] = by_key("rainbow").available()
    data["batteryAvailable"] = by_key("battery").available()
    data["tempAvailable"] = by_key("temperature").available()
    return data


def led_config():
    return _with_available(_state.load(MODES))


# --- apply (request the renderer to show the current config) -----------------
# The renderer drives the hardware; _targets computes what a group *should* show,
# handing the result to the renderer (which decides snap vs fade from its cache).
_side_colour = _targets.side_colour

def _apply_rings(data, fade=False):
    if not data["enabled"]:
        _renderer.set_many({"ringL": ((0, 0, 0), 0), "ringR": ((0, 0, 0), 0)}, fade=fade, stop=_state.effect_stop)
        return
    mode = by_key(data.get("mode")) or by_key("static")
    mode.render_rings(data, fade, _state.effect_stop)


def _apply_sides(data, fade=False):
    if not data["enabled"]:
        _renderer.set_many({"sideL": ((0, 0, 0), 0), "sideR": ((0, 0, 0), 0)}, fade=fade, stop=_state.side_stop)
        return
    target = _side_colour(data)
    if target is None:
        _renderer.set_many({"sideL": ((0, 0, 0), 0), "sideR": ((0, 0, 0), 0)}, fade=fade, stop=_state.side_stop)
    else:
        _renderer.set_many({"sideL": target, "sideR": target}, fade=fade, stop=_state.side_stop)


def _apply_state(data, fade=False):
    _apply_rings(data, fade=fade)
    _apply_sides(data, fade=fade)


def _start_ring_monitor(data):
    if not data["enabled"]:
        return None
    spec = reactive_mode(data.get("mode"))
    if spec is None or not spec.reactive.available():
        return None
    thread = threading.Thread(target=spec.reactive.make_loop("rings"), name=f"led-rings-{data['mode']}", daemon=True)
    _state.effect_thread = thread
    thread.start()
    return thread


def _start_side_monitor(data):
    if not data["enabled"]:
        return None
    spec = reactive_mode(data.get("sideMode"))
    if spec is None or not spec.reactive.available():
        return None
    thread = threading.Thread(target=spec.reactive.make_loop("sides"), name=f"led-sides-{data['sideMode']}", daemon=True)
    _state.side_thread = thread
    thread.start()
    return thread


def _commit(data, fade=False):
    # Single setter path: persist, stop both threads, apply the new state, and spin up
    # whatever monitors the active ring/side modes need. `fade` is True for mode/enable
    # changes (ease in from the renderer's cached colour) and False for slider drags (snap).
    # Takes its own LOCK so it's safe to call directly; setters already inside `with LOCK`
    # get reentrant entry via the RLock.
    with _state.LOCK:
        _state.save(data)
        _state.stop_effect()
        _state.stop_side()
        _apply_state(data, fade=fade)
        _start_ring_monitor(data)
        _start_side_monitor(data)
        return _with_available(data)


def set_led(side, r, g, b, brightness):
    if side not in ("left", "right", "both"):
        raise ValueError(f"unknown led side: {side!r}")
    rgb = {"r": _colour.clamp_byte(r), "g": _colour.clamp_byte(g), "b": _colour.clamp_byte(b), "brightness": _colour.clamp_byte(brightness)}
    with _state.LOCK:
        data = _state.load(MODES)
        if side == "both":
            data["left"] = copy.deepcopy(rgb)
            data["right"] = copy.deepcopy(rgb)
        else:
            data[side] = rgb
        return _commit(data)


def set_led_linked(linked):
    with _state.LOCK:
        data = _state.load(MODES)
        data["linked"] = bool(linked)
        if data["linked"]:
            data["right"] = copy.deepcopy(data["left"])
        return _commit(data, fade=True)


def set_led_enabled(enabled):
    with _state.LOCK:
        data = _state.load(MODES)
        data["enabled"] = bool(enabled)
        return _commit(data, fade=True)


def set_led_mode(mode):
    with _state.LOCK:
        data = _state.load(MODES)
        spec = by_key(mode)
        if spec is None or not spec.available():
            mode = "static"
        data["mode"] = mode
        return _commit(data, fade=True)


def set_led_side_mode(side_mode):
    with _state.LOCK:
        data = _state.load(MODES)
        if side_mode not in SIDE_MODES:
            side_mode = "off"
        spec = reactive_mode(side_mode)
        if spec is not None and not spec.reactive.available():
            side_mode = "off"
        data["sideMode"] = side_mode
        return _commit(data, fade=True)


def set_led_side(r, g, b, brightness):
    with _state.LOCK:
        data = _state.load(MODES)
        data["side"] = {"r": _colour.clamp_byte(r), "g": _colour.clamp_byte(g), "b": _colour.clamp_byte(b), "brightness": _colour.clamp_byte(brightness)}
        return _commit(data)


def set_led_mode_brightness(brightness):
    with _state.LOCK:
        data = _state.load(MODES)
        data["modeBrightness"] = _colour.clamp_byte(brightness)
        return _commit(data)


def set_led_side_brightness(brightness):
    with _state.LOCK:
        data = _state.load(MODES)
        data["sideBrightness"] = _colour.clamp_byte(brightness)
        return _commit(data)


def set_led_temp_thresholds(lo, hi):
    with _state.LOCK:
        data = _state.load(MODES)
        data["tempMin"] = _safe_int(lo, data.get("tempMin", 40))
        data["tempMax"] = _safe_int(hi, data.get("tempMax", 80))
        return _commit(data)


def set_led_temp_rate(rate):
    from .modes.temperature import TEMP_RATES
    with _state.LOCK:
        data = _state.load(MODES)
        if rate not in TEMP_RATES:
            rate = "normal"
        data["tempRate"] = rate
        return _commit(data)


def set_boot_pulse(enabled):
    with _state.LOCK:
        data = _state.load(MODES)
        data["bootPulse"] = bool(enabled)
        _state.save(data)
        return _with_available(data)


def init_leds():
    # Called from Plugin._main: start the boot pulse if enabled and in game mode, else
    # apply the saved state. The pulse thread resolves its own nodes, so no lock is
    # held while it runs.
    from . import _engine
    if not _sysfs.available():
        return
    _renderer.reset()  # hardware state is unknown after a reboot
    data = _state.load(MODES)
    if data["enabled"] and data["bootPulse"] and _engine.in_game_mode():
        _engine.start_boot_pulse()
    else:
        with _state.LOCK:
            _state.stop_effect()
            _state.stop_side()
            _apply_state(data)
        _start_ring_monitor(data)
        _start_side_monitor(data)
