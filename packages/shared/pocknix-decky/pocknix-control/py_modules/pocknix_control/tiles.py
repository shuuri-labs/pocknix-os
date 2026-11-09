from pathlib import Path

# Same dirs and parsing as pocknix-tiles' manifest(): if they drift, a tile's name stops matching
# and it gets wrapped (and re-added) again. launch=plain marks a settings app.
MANIFEST_DIRS = (Path("/usr/share/pocknix-emulation/steam"), Path("/usr/share/pocknix/tiles"))


def plain_tiles(dirs=MANIFEST_DIRS):
    tiles = []
    for d in dirs:
        for path in sorted(d.glob("*.conf")):
            m = {}
            try:
                for line in path.read_text(encoding="utf-8").splitlines():
                    k, sep, v = line.strip().partition("=")
                    if sep and not k.startswith("#"):
                        m[k.strip()] = v.strip()
            except OSError:
                continue
            if m.get("launch") == "plain" and m.get("name") and m.get("exe"):
                tiles.append({"name": m["name"], "exe": m["exe"], "args": m.get("args", "")})
    return tiles
