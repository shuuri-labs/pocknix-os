"""Single write-gateway to the LED sysfs nodes.

This module is the only caller of _sysfs.write_*. It keeps a per-group cache of what
each physical node-group currently shows, so callers just request "show this colour"
and the renderer decides whether to snap or fade — the "from" colour comes from its own
cache, not from callers passing stale snapshots.

Four disjoint groups, each with N segment nodes:
  ringL, ringR — left/right stick rings
  sideL, sideR — left/right side strips

Cache values: (rgb, brightness) for a known single colour, or None when the group is
dark / was last driven by a multi-colour animation (rainbow, boot pulse) whose single
representative colour we can't track. A fade from None eases in from dark.

The cache is only touched under _state.LOCK (every writer holds it), so it needs no
internal lock of its own.
"""

from . import _colour, _sysfs

GROUPS = ("ringL", "ringR", "sideL", "sideR")

# Per-group cache: group -> (rgb, brightness) | None (dark/unknown/animated).
_current = {g: None for g in GROUPS}


def reset():
    # Hardware state is unknown after a reboot (sysfs resets). Start from "dark/unknown"
    # so the first show eases in from dark rather than trusting a stale cached colour.
    global _current
    _current = {g: None for g in GROUPS}


def current(group):
    # Public accessor for the engine, which needs to snapshot colours before a fade.
    return _current.get(group)


def caps_for(group):
    # Public accessor — resolve the sysfs segment-caps for one group.
    if group == "ringL":
        return _sysfs.segment_caps(_sysfs.segments("left"))
    if group == "ringR":
        return _sysfs.segment_caps(_sysfs.segments("right"))
    if group == "sideL":
        return _sysfs.segment_caps(_sysfs.side_segments("left"))
    if group == "sideR":
        return _sysfs.segment_caps(_sysfs.side_segments("right"))
    raise ValueError(f"unknown led group: {group!r}")


# Alias kept for the engine, which was written before the rename.
_caps_for = caps_for


def _apply_and_cache(group, caps, rgb, brightness):
    # Write to sysfs and update the cache only if the write actually landed. A silent
    # OSError (driver hiccup, permissions) would otherwise desync the cache from the
    # hardware, making subsequent fades start from a wrong "from" colour.
    ok = _sysfs.apply_caps_rgb(caps, rgb, brightness)
    if ok:
        _current[group] = (rgb, brightness)
    else:
        _current[group] = None  # unknown — next fade eases in from dark


def set_many(targets, fade=False, stop=None):
    # Show colours on several groups at once. When fading, all groups animate on one
    # shared frame clock so they ease in parallel (not one after another).
    caps_map = {g: caps_for(g) for g in targets}
    if not fade:
        for g, (rgb, bri) in targets.items():
            _apply_and_cache(g, caps_map[g], rgb, bri)
        return
    from . import _engine
    # Build per-group (from, to) specs for animate_many. Skip groups whose target equals
    # the cached state — nothing to animate, so no wasted sysfs churn.
    specs = {}
    for g, (rgb, bri) in targets.items():
        frm = _current.get(g)
        if frm == (rgb, bri):
            continue
        if frm is None:
            _sysfs.apply_caps_rgb(caps_map[g], rgb, 0)
            specs[g] = (caps_map[g], (rgb, 0), (rgb, bri))
        else:
            specs[g] = (caps_map[g], (frm[0], frm[1]), (rgb, bri))
    interrupted = False
    if specs:
        interrupted = _engine.animate_many(specs, stop)
    # Only update the cache for groups that were rendered (or skipped as no-ops). An
    # interrupted fade leaves the cache at None so the next operation fades from dark
    # rather than trusting a mid-transition colour.
    for g, (rgb, bri) in targets.items():
        if g in specs and interrupted:
            _current[g] = None
        elif g not in specs or not interrupted:
            _current[g] = (rgb, bri)


def set_rainbow(group, brightness, stop=None):
    # A hue spread has no single representative colour. Mark the group animated so the
    # next fade eases in from dark instead of trusting a non-existent cached colour.
    caps = caps_for(group)
    _rainbow_caps(caps, brightness)
    _current[group] = None  # rainbow is always "animated"


def _rainbow_caps(caps, brightness):
    n = len(caps)
    for i, cap in enumerate(caps):
        _sysfs.write_rgb(cap, _colour.hsv_to_rgb((i * 360 // n) if n else 0), brightness)


def animate_frame(group, rgb, brightness, caps=None):
    # One frame of an engine-driven animation (boot pulse, handoff). Just write and
    # cache — the engine owns the easing curve and calls this per frame. `caps` may be
    # pre-resolved by the caller to avoid re-probing sysfs every frame.
    if caps is None:
        caps = caps_for(group)
    _apply_and_cache(group, caps, rgb, brightness)


def mark_animated(*groups):
    # The group is being driven by a multi-frame animation whose single colour we can't
    # track (boot-pulse brightness ramp). Subsequent fades start from dark.
    for g in groups:
        _current[g] = None
