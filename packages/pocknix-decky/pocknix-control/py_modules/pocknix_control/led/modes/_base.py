from dataclasses import dataclass
from typing import Any, Callable, Optional, Tuple

Target = Tuple[Tuple[int, int, int], int]  # ((r, g, b), brightness)


@dataclass(frozen=True)
class Reactive:
    """A drifting-source mode (battery, temperature): the conductor starts its `loop`
    on the effect thread so the colour keeps tracking while the QAM is closed.

    `target` selects which nodes the monitor drives: "rings" or "sides", so a ring and
    a side reactive mode can run concurrently on disjoint sysfs nodes."""
    available: Callable[[], bool]
    make_loop: Callable[[str], Callable[[], None]]


@dataclass(frozen=True)
class Mode:
    key: str
    available: Callable[[], bool]
    defaults: dict
    # Drive the ring hardware for this mode. Called by the conductor's _apply_rings and
    # the engine's handoff, eliminating key-string dispatch in the conductor.
    render_rings: Callable[[dict, bool, Any], None]
    sanitize: Optional[Callable[[dict, dict], None]] = None
    reactive: Optional[Reactive] = None
    # Single representative (rgb, brightness) for the mode, or None when it has no one
    # colour (rainbow). Used by side "match" to mirror the ring mode onto side nodes.
    colour: Optional[Callable[[dict], Optional[Target]]] = None
