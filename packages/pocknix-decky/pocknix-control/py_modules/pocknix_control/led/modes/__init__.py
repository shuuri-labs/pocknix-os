# The mode registry. Adding a mode = new module + one entry here; the conductor and
# engine never hardcode a mode key.
from ._base import Mode, Reactive
from .battery import battery
from .rainbow import rainbow
from .static import static
from .temperature import temperature

MODES = (static, rainbow, battery, temperature)

_BY_KEY = {m.key: m for m in MODES}


def by_key(key):
    return _BY_KEY.get(key)


def reactive_mode(key):
    # The Mode for `key` if it carries a Reactive spec, else None. The conductor builds
    # the actual loop per target (rings/sides) via mode.reactive.make_loop(target).
    m = _BY_KEY.get(key)
    return m if (m is not None and m.reactive is not None) else None
