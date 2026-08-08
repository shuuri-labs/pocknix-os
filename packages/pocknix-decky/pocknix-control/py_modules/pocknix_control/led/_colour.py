"""Pure colour math: HSV-to-RGB, clamp, and capacity/temperature → colour mapping.

Sensor reads (sysfs) live in _sensors.py. This module has no side effects and can be
unit-tested without mocking the filesystem.
"""


def clamp_byte(value):
    try:
        n = int(value)
    except (TypeError, ValueError):
        return 0
    return max(0, min(255, n))


def rgb(side):
    return (side["r"], side["g"], side["b"])


def hsv_to_rgb(hue):
    # Full-saturation, full-value colour for a hue in degrees (0-359).
    h = hue % 360
    i = int(h // 60)
    f = h / 60 - i
    q = 1 - f
    if i == 0:
        return (255, int(round(f * 255)), 0)
    if i == 1:
        return (int(round(q * 255)), 255, 0)
    if i == 2:
        return (0, 255, int(round(f * 255)))
    if i == 3:
        return (0, int(round(q * 255)), 255)
    if i == 4:
        return (int(round(f * 255)), 0, 255)
    return (255, 0, int(round(q * 255)))


def capacity_rgb(capacity):
    # Red below 10% (a clear "charge me" floor), then a slow red -> yellow climb over
    # 10-50%, then yellow -> green for the rest. Charge status is deliberately ignored
    # — the colour tracks the level only.
    if capacity <= 10:
        hue = 0.0
    elif capacity <= 50:
        hue = (capacity - 10) * (30 / 40)  # 10-50% -> 0-30 (red to yellow)
    else:
        hue = 30 + (capacity - 50) * (90 / 50)  # 50-100% -> 30-120 (yellow to green)
    return hsv_to_rgb(hue)


def temp_rgb(temp, lo, hi):
    # Blue (cool) -> cyan -> green -> yellow -> red (hot): hue sweeps 240 -> 0 across the
    # threshold window, clamped at the ends.
    if lo >= hi:
        span = 1
    else:
        span = hi - lo
    t = max(0.0, min(1.0, (temp - lo) / span))
    return hsv_to_rgb((1.0 - t) * 240)
