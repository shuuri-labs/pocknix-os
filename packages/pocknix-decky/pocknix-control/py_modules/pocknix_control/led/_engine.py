import json
import math
import threading
import time
import urllib.request
from pathlib import Path

from . import _colour, _renderer, _state

PULSE_FRAME = 1.0 / 30.0
PULSE_MAX_WAIT = 120.0
WHITE = (255, 255, 255)
FADE_DURATION = 0.3
# The gamepad UI shows up in CEF's target list as a tab named "SP" pointing at the
# steamloopback host — the same predicate upstream Decky's injector blocks on
# (/json/version responds too early, mid-splash).
CEF_TABS_URL = "http://127.0.0.1:8080/json"
GAMEPADUI_TITLES = ("SP", "Steam", "SharedJSContext")
GAMEPADUI_URL_HINTS = ("steamloopback.host/routes/", "steamloopback.host/index.html")


def gamepadui_tab_up():
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


def in_game_mode():
    # The pulse only makes sense while Steam loads; in a Plasma desktop session Steam
    # never starts, so the readiness probe would stall until the timeout. No file
    # records the session choice, so detect it from /proc. Default to game mode when
    # uncertain — that is the common boot path.
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


def _lerp(a, b, t):
    return a + (b - a) * t


def _lerp_rgb_bri(from_rgb, from_bri, to_rgb, to_bri, t):
    rgb = (int(round(_lerp(from_rgb[0], to_rgb[0], t))),
           int(round(_lerp(from_rgb[1], to_rgb[1], t))),
           int(round(_lerp(from_rgb[2], to_rgb[2], t))))
    return rgb, int(round(_lerp(from_bri, to_bri, t)))


def transition(caps, from_rgb, from_bri, to_rgb, to_bri, stop):
    # Linear interpolation of RGB (per-channel) and brightness over FADE_DURATION,
    # written frame-by-frame. Used by the renderer for single-group fades.
    steps = max(1, int(round(FADE_DURATION / PULSE_FRAME)))
    for i in range(steps + 1):
        if stop.is_set():
            return True  # interrupted
        t = i / steps if steps else 1
        rgb, bri = _lerp_rgb_bri(from_rgb, from_bri, to_rgb, to_bri, t)
        from . import _sysfs
        _sysfs.apply_caps_rgb(caps, rgb, bri)
        if i < steps:
            stop.wait(PULSE_FRAME)
    return False  # completed


def animate_many(specs, stop):
    # Drive several group-fades on one shared frame clock so they ease in parallel.
    # specs: {group: (caps, (from_rgb, from_bri), (to_rgb, to_bri))}.
    # Returns True if interrupted (stop was set mid-fade).
    steps = max(1, int(round(FADE_DURATION / PULSE_FRAME)))
    from . import _sysfs
    for i in range(steps + 1):
        if stop.is_set():
            return True
        t = i / steps if steps else 1
        for group, (caps, frm, to) in specs.items():
            rgb, bri = _lerp_rgb_bri(frm[0], frm[1], to[0], to[1], t)
            _sysfs.apply_caps_rgb(caps, rgb, bri)
        if i < steps:
            stop.wait(PULSE_FRAME)
    return False


def fade_brightness(caps, peak, stop):
    # Sin-eased brightness fade-in 0 -> peak over half a second; exits early if stopped.
    steps = max(2, int(round(0.5 / PULSE_FRAME)))
    from . import _sysfs
    for i in range(steps):
        if stop.is_set():
            return
        t = i / (steps - 1)
        eased = (1 - math.cos(math.pi * t)) / 2
        _sysfs.apply_caps_brightness(caps, int(round(peak * eased)))
        stop.wait(PULSE_FRAME)


def ramp(groups, peak, stop=None):
    # Sin-eased brightness ramp 0 -> peak -> 0 over half a second for the boot pulse.
    # `groups` is a list of (group_key, caps); all ramp together on one frame clock.
    if stop is None:
        stop = _state.effect_stop
    steps = max(2, int(round(0.5 / PULSE_FRAME)))
    from . import _sysfs
    for half in (0, 1):
        for i in range(steps):
            if stop.is_set():
                return
            t = i / (steps - 1)
            eased = t if half == 0 else 1 - t
            value = int(round(peak * (1 - math.cos(math.pi * eased)) / 2))
            for _group, caps in groups:
                _sysfs.apply_caps_brightness(caps, value)
            stop.wait(PULSE_FRAME)


def handoff_to_user(data, ring_groups, side_groups):
    # Final transition: white pulse out on the rings, then rings and sides each fade
    # in to their own saved state. Side strips were dark during the boot pulse; they
    # fade in here for the first time.
    if _state.effect_stop.is_set():
        return
    ramp(ring_groups, 100, stop=_state.effect_stop)
    if _state.effect_stop.is_set():
        return
    from .modes import by_key
    mode = by_key(data.get("mode")) or by_key("static")
    ring_brightness = data.get("modeBrightness", 255)
    if mode.colour is None:
        # Rainbow (or any no-single-colour mode): snap the spread at target brightness.
        for group, caps in ring_groups:
            _renderer.set_rainbow(group, ring_brightness, stop=_state.effect_stop)
    else:
        c = mode.colour(data)
        rgb = c[0] if c is not None else (0, 0, 0)
        # Static with different L/R: per-side ramp. Otherwise uniform brightness fade.
        if mode.key == "static" and not data.get("linked", True):
            left = data["left"]
            right = data["right"]
            specs = {}
            for group, caps in ring_groups:
                src = left if group == "ringL" else right
                src_rgb = _colour.rgb(src)
                _renderer.animate_frame(group, src_rgb, 0, caps=caps)
                specs[group] = (caps, ((src_rgb, 0), (src_rgb, src["brightness"])))
            _static_ramp_groups(specs, _state.effect_stop)
        else:
            for group, caps in ring_groups:
                _renderer.animate_frame(group, rgb, 0, caps=caps)
            _fade_brightness_groups(ring_groups, ring_brightness, _state.effect_stop)
    _fade_sides(data, side_groups, _state.effect_stop)


def _fade_brightness_groups(groups, peak, stop):
    # Sin-eased brightness fade 0 -> peak across multiple groups on one frame clock.
    # Each group's colour was set by an animate_frame call just before this; cache the rgb
    # once (it doesn't move during a brightness fade) and write each frame through the
    # renderer so the cache stays in sync.
    steps = max(2, int(round(0.5 / PULSE_FRAME)))
    rgb_by_group = {}
    for group, caps in groups:
        cached = _renderer.current(group)
        rgb_by_group[group] = cached[0] if cached is not None else (0, 0, 0)
    for i in range(steps):
        if stop.is_set():
            return
        t = i / (steps - 1)
        eased = (1 - math.cos(math.pi * t)) / 2
        value = int(round(peak * eased))
        for group, caps in groups:
            _renderer.animate_frame(group, rgb_by_group[group], value, caps=caps)
        stop.wait(PULSE_FRAME)


def _static_ramp_groups(specs, stop):
    # Per-side brightness ramp for the static handoff, all groups on one frame clock.
    steps = max(2, int(round(0.5 / PULSE_FRAME)))
    for i in range(steps):
        if stop.is_set():
            return
        t = i / (steps - 1)
        eased = (1 - math.cos(math.pi * t)) / 2
        for group, (caps, (frm, to)) in specs.items():
            bri = int(to[1] * eased)
            _renderer.animate_frame(group, frm[0], bri, caps=caps)
        stop.wait(PULSE_FRAME)


def _fade_sides(data, side_groups, stop):
    # Side strips reach their saved state after the ring handoff. Colour resolution is
    # shared with the conductor via _targets.side_colour to avoid divergence.
    from . import _targets
    if stop.is_set() or not side_groups:
        return
    target = _targets.side_colour(data)
    if target is None:
        for group, caps in side_groups:
            _renderer.animate_frame(group, (0, 0, 0), 0, caps=caps)
        return
    rgb, peak = target
    for group, caps in side_groups:
        _renderer.animate_frame(group, rgb, 0, caps=caps)
    _fade_brightness_groups(side_groups, peak, stop)


def _boot_pulse_loop():
    from .modes import MODES  # late: avoids the engine ↔ modes cycle
    self = threading.current_thread()
    data = _state.load(MODES)
    ring_groups = [("ringL", _renderer._caps_for("ringL")), ("ringR", _renderer._caps_for("ringR"))]
    side_groups = [("sideL", _renderer._caps_for("sideL")), ("sideR", _renderer._caps_for("sideR"))]
    # Boot pulse is rings-only: side strips stay dark until the handoff.
    for group, caps in ring_groups:
        _renderer.animate_frame(group, WHITE, 0, caps=caps)
    for group, caps in side_groups:
        _renderer.animate_frame(group, (0, 0, 0), 0, caps=caps)
    start = time.monotonic()
    steam_up = False
    while True:
        if _state.effect_stop.is_set():
            return
        if steam_up or time.monotonic() - start > PULSE_MAX_WAIT:
            break
        ramp(ring_groups, 100)
        if _state.effect_stop.is_set():
            return
        # Re-check the session here too: the loader can start before Plasma comes up,
        # so in_game_mode() may have been True at init time and flip a few seconds in.
        # A desktop session has no Steam to wait for, so bail straight to the saved state.
        if not in_game_mode():
            break
        if gamepadui_tab_up():
            steam_up = True
    # If a setter displaced us while we were running, bail — the setter owns the state now.
    if _state.effect_thread is not self:
        return
    # The ramp drove ring brightness only; the renderer can't track a single colour for
    # that, so mark the rings animated — the handoff below re-establishes the real state.
    _renderer.mark_animated("ringL", "ringR")
    handoff_to_user(data, ring_groups, side_groups)
    # Post-handoff: re-read config (it may have changed during the minutes-long pulse),
    # then start reactive monitors under LOCK, but only if we're still the registered thread.
    with _state.LOCK:
        if _state.effect_thread is not self:
            return
        _state.effect_thread = None
        current = _state.load(MODES)
        # Use the conductor's monitor-start helpers. Import the package itself (not
        # __init__ by name — that gives a method-wrapper, not the module).
        import pocknix_control.led as conductor
        conductor._start_ring_monitor(current)
        conductor._start_side_monitor(current)


def start_boot_pulse():
    with _state.LOCK:
        if _state.effect_thread is not None and _state.effect_thread.is_alive():
            return
        _state.stop_effect()
        _state.effect_thread = threading.Thread(target=_boot_pulse_loop, name="led-boot-pulse", daemon=True)
        _state.effect_thread.start()
