"""Shared colour-resolution: compute what each group *should* show from the config.

Both the conductor (apply path) and the engine (handoff) need to turn the config into a
target (rgb, brightness). Keeping it here avoids the conductor ↔ engine import cycle and
the duplication that caused.
"""

from . import _colour, _sensors


def ring_colour(data):
    # Representative (rgb, brightness) the rings show under the active mode, or None for
    # rainbow (a spread the renderer handles separately via set_rainbow).
    from .modes import by_key
    mode = by_key(data.get("mode")) or by_key("static")
    return mode.colour(data) if mode.colour is not None else None


def side_colour(data):
    # Representative (rgb, brightness) the side strips show, or None when dark/animated.
    sm = data.get("sideMode", "off")
    if sm == "off":
        return None
    if sm == "match":
        return ring_colour(data)
    if sm == "static":
        side = data["side"]
        # sideLinked does NOT mean "left side = right side" (unlike ring `linked` which
        # means L-ring = R-ring). It means "the side strips mirror the ring's left colour"
        # — so the `side` colour store is ignored until the user unlinks them.
        if data.get("sideLinked", True):
            left = data["left"]
            return (_colour.rgb(left), left["brightness"])
        return (_colour.rgb(side), side["brightness"])
    if sm == "battery":
        capacity = _sensors.read_capacity()
        return (_colour.capacity_rgb(capacity), data.get("sideBrightness", 255)) if capacity is not None else None
    if sm == "temperature":
        temp = _sensors.read_temp()
        return (_colour.temp_rgb(temp, data["tempMin"], data["tempMax"]), data.get("sideBrightness", 255)) if temp is not None else None
    return None
