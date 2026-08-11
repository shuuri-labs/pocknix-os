from .. import _colour, _renderer, _sensors, _state
from ._base import Mode, Reactive

BATTERY_POLL = 30.0


def _available():
    return _sensors.BATTERY_CAPACITY.is_file()


def _render(target, data):
    capacity = _sensors.read_capacity()
    if capacity is None:
        return
    rgb = _colour.capacity_rgb(capacity)
    brightness = data.get("modeBrightness" if target == "rings" else "sideBrightness", 255)
    groups = ("ringL", "ringR") if target == "rings" else ("sideL", "sideR")
    _renderer.set_many({g: (rgb, brightness) for g in groups}, fade=False)


def _render_rings(data, fade, stop):
    capacity = _sensors.read_capacity()
    rgb = _colour.capacity_rgb(capacity) if capacity is not None else (0, 0, 0)
    bri = data.get("modeBrightness", 255)
    _renderer.set_many({"ringL": (rgb, bri), "ringR": (rgb, bri)}, fade=fade, stop=stop)


def _colour_fn(data):
    capacity = _sensors.read_capacity()
    if capacity is None:
        return None
    return (_colour.capacity_rgb(capacity), data.get("modeBrightness", 255))


def _make_loop(target):
    """Build a monitor that re-renders `target` when the battery level moves. The bail
    guard checks the right field: rings check data["mode"], sides check data["sideMode"]."""
    own_key = "mode" if target == "rings" else "sideMode"

    def _loop():
        from . import MODES  # late: avoids the modes ↔ conductor import cycle
        stop = _state.effect_stop if target == "rings" else _state.side_stop
        last = -1
        while not stop.is_set():
            capacity = _sensors.read_capacity()
            if capacity is None:
                break
            if capacity != last:
                with _state.LOCK:
                    data = _state.load(MODES)
                # Render outside the lock to avoid blocking setters during sysfs writes.
                if data.get(own_key) == "battery":
                    _render(target, data)
                last = capacity
            stop.wait(BATTERY_POLL)

    return _loop


battery = Mode(
    key="battery",
    available=_available,
    defaults={
        "modeBrightness": 255,
    },
    render_rings=_render_rings,
    reactive=Reactive(available=_available, make_loop=_make_loop),
    colour=_colour_fn,
)
