from .. import _colour, _renderer, _sensors, _state
from ._base import Mode, Reactive

TEMP_RATES = {"slow": 5.0, "normal": 3.0, "fast": 1.0}
# Smoothing: average over the last TEMP_SAMPLES readings and only re-render when the
# smoothed value moves ≥TEMP_HYSTERESIS °C, so transient thermal jitter can't flicker.
# Count-based (not time-based) so the smoothing depth is independent of the poll rate.
TEMP_SAMPLES = 3
TEMP_HYSTERESIS = 2


def _available():
    # Same source as pocknix-fancontrol: cpu*/gpu* thermal-zone types. Without those
    # zones the temperature mode has nothing to read.
    return any(_sensors.thermal_zones())


def _render(target, data, stop=None, fade=False):
    temp = _sensors.read_temp()
    if temp is None:
        return
    rgb = _colour.temp_rgb(temp, data["tempMin"], data["tempMax"])
    brightness = data.get("modeBrightness" if target == "rings" else "sideBrightness", 255)
    groups = ("ringL", "ringR") if target == "rings" else ("sideL", "sideR")
    _renderer.set_many({g: (rgb, brightness) for g in groups}, fade=fade, stop=stop)


def _colour_fn(data):
    temp = _sensors.read_temp()
    if temp is None:
        return None
    return (_colour.temp_rgb(temp, data["tempMin"], data["tempMax"]), data.get("modeBrightness", 255))


def _safe_int(value, default):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _sanitize(data, clean):
    temp_lo = _safe_int(data.get("tempMin", 40), 40)
    temp_hi = _safe_int(data.get("tempMax", 80), 80)
    # Keep the window sane: 0-100°C, and min strictly below max.
    temp_lo = max(0, min(100, temp_lo))
    temp_hi = max(0, min(100, temp_hi))
    if temp_lo >= temp_hi:
        temp_lo, temp_hi = 40, 80
    clean["tempMin"] = temp_lo
    clean["tempMax"] = temp_hi
    rate = data.get("tempRate", "normal")
    clean["tempRate"] = rate if rate in TEMP_RATES else "normal"


def _make_loop(target):
    """Build a monitor that re-renders `target` with rolling-window smoothing."""
    own_key = "mode" if target == "rings" else "sideMode"

    def _loop():
        from collections import deque
        from . import MODES  # late: avoids the modes ↔ conductor import cycle
        stop = _state.effect_stop if target == "rings" else _state.side_stop
        samples = deque(maxlen=TEMP_SAMPLES)
        last_rendered = None
        while not stop.is_set():
            with _state.LOCK:
                rate = TEMP_RATES.get(_state.load(MODES).get("tempRate"), TEMP_RATES["normal"])
            temp = _sensors.read_temp()
            if temp is None:
                break
            samples.append(temp)
            smoothed = (sum(samples) // len(samples)) if samples else temp
            if last_rendered is None or abs(smoothed - last_rendered) >= TEMP_HYSTERESIS:
                with _state.LOCK:
                    data = _state.load(MODES)
                # Render outside the lock — the fade can take ~500ms and must not
                # block setters (which need LOCK for config read-modify-write).
                if data.get(own_key) == "temperature":
                    _render(target, data, stop=stop, fade=True)
                last_rendered = smoothed
            if stop.wait(rate):
                break

    return _loop


def _render_rings(data, fade, stop):
    temp = _sensors.read_temp()
    rgb = _colour.temp_rgb(temp, data["tempMin"], data["tempMax"]) if temp is not None else (0, 0, 0)
    bri = data.get("modeBrightness", 255)
    _renderer.set_many({"ringL": (rgb, bri), "ringR": (rgb, bri)}, fade=fade, stop=stop)


temperature = Mode(
    key="temperature",
    available=_available,
    defaults={
        "modeBrightness": 255,
        "tempMin": 40,
        "tempMax": 80,
        "tempRate": "normal",
    },
    render_rings=_render_rings,
    sanitize=_sanitize,
    reactive=Reactive(available=_available, make_loop=_make_loop),
    colour=_colour_fn,
)
