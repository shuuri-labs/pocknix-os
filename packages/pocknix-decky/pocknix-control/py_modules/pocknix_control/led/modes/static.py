from .. import _colour, _renderer
from ._base import Mode


def _render_rings(data, fade, stop):
    # Per-side colours (L may differ from R when unlinked).
    left = data["left"]
    right = data["right"] if not data["linked"] else left
    _renderer.set_many({
        "ringL": (_colour.rgb(left), left["brightness"]),
        "ringR": (_colour.rgb(right), right["brightness"]),
    }, fade=fade, stop=stop)


def _colour_fn(data):
    return (_colour.rgb(data["left"]), data["left"]["brightness"])


static = Mode(
    key="static",
    available=lambda: True,
    defaults={"linked": True},
    render_rings=_render_rings,
    colour=_colour_fn,
)
