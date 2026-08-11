from pathlib import Path

# Stick RGB rings expose as multicolor LED-class devices. sysfs resets on reboot,
# so the chosen state is persisted and re-applied from Plugin._main on load.
# RP6/RP5/Flip 2: /sys/class/leds/rgb:l1..l4 and rgb:r1..r4 (4 ring segments per stick).
# Odin 2: /sys/class/leds/left-joystick and right-joystick (1 node per stick,
# pwm-leds-multicolor). Same multi_intensity/brightness ABI in both cases.
# Odin 2 also has left-side/right-side strips, which carry no colour of their own.
LED_CLASS_DIR = Path("/sys/class/leds")


def segments(side):
    # RP6 groups each ring segment under rgb:<l|r><n>; Odin names the whole stick.
    # Probed per call, not at import: plugin load can precede the LED driver.
    # Sort numerically by trailing digit so rgb:l10 doesn't sort before rgb:l2.
    segs = list(LED_CLASS_DIR.glob(f"rgb:{side[0]}[0-9]*"))
    if segs:
        def _numkey(p):
            digits = ''.join(c for c in p.name if c.isdigit())
            return int(digits) if digits else 0
        segs.sort(key=_numkey)
        return segs
    node = LED_CLASS_DIR / f"{side}-joystick"
    return [node] if node.is_dir() else []


def side_segments(side):
    node = LED_CLASS_DIR / f"{side}-side"
    return [node] if node.is_dir() else []


def available():
    return bool(segments("left") or segments("right"))


def sides_available():
    return bool(side_segments("left") or side_segments("right"))


# --- resolved hardware nodes -------------------------------------------------
# Channel order and max brightness are fixed by the driver, so resolve once per apply
# rather than re-reading sysfs on every frame of a 30 fps pulse ramp.

def segment_caps(leds):
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


def write_rgb(cap, rgb, brightness):
    # Returns True on success, False on OSError (so the renderer can skip cache update).
    led, max_brightness, names = cap
    named = {"red": rgb[0], "green": rgb[1], "blue": rgb[2]}
    intensity = " ".join(str(named.get(name, 0)) for name in names)
    value = max(0, min(max_brightness, brightness))
    try:
        (led / "multi_intensity").write_text(intensity + "\n", encoding="utf-8")
        (led / "brightness").write_text(f"{value}\n", encoding="utf-8")
        return True
    except OSError:
        return False


def write_brightness(cap, brightness):
    led, max_brightness, _ = cap
    value = max(0, min(max_brightness, brightness))
    try:
        (led / "brightness").write_text(f"{value}\n", encoding="utf-8")
        return True
    except OSError:
        return False


def apply_caps_rgb(caps, rgb, brightness):
    # Returns True only if every cap wrote successfully.
    return all(write_rgb(cap, rgb, brightness) for cap in caps)


def apply_caps_brightness(caps, brightness):
    return all(write_brightness(cap, brightness) for cap in caps)
