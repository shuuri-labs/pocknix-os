from .. import _renderer, _sysfs
from ._base import Mode


def _available():
    return len(_sysfs.segments("left")) >= 2 or len(_sysfs.segments("right")) >= 2


def _render_rings(data, fade, stop):
    brightness = data.get("modeBrightness", 255)
    _renderer.set_rainbow("ringL", brightness, stop=stop)
    _renderer.set_rainbow("ringR", brightness, stop=stop)


rainbow = Mode(
    key="rainbow",
    available=_available,
    defaults={"modeBrightness": 255},
    render_rings=_render_rings,
    colour=None,
)
