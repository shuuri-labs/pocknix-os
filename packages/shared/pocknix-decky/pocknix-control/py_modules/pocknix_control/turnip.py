import json
import os
import re
import stat
from pathlib import Path

ARM_DIR = Path("/usr/share/pocknix/vk-arm")
USER_DIR = Path("/home/deck/.local/share/pocknix/turnip")
USER_PREFIX = "user:"
# Same rule as pocknix-game-launch: no path separators, no ":" (the prefix), no hidden dirs.
USER_NAME = re.compile(r"[^/:.][^/:]{0,99}")
MAX_DRIVER_BYTES = 256 << 20
MAX_META_BYTES = 64 << 10


def _read_user_file(path, limit):
    # This runs as root over a deck-writable tree: never follow a symlink or block on a FIFO.
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    with os.fdopen(fd, "rb") as f:
        st = os.fstat(f.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_size > limit:
            return None
        return f.read(limit)


def is_arm64_glibc(data):
    # Android (bionic) Turnip builds link "libc.so" and can't load on this host.
    return data[:5] == b"\x7fELF\x02" and data[18:20] == b"\xb7\x00" and b"libc.so.6\0" in data


def user_drivers():
    if USER_DIR.is_symlink():
        return []
    try:
        dirs = [p for p in USER_DIR.iterdir() if USER_NAME.fullmatch(p.name) and p.is_dir() and not p.is_symlink()]
    except OSError:
        return []
    drivers = []
    for d in dirs:
        # One unreadable driver (pulled SD card, I/O error) must not fail the whole config.
        try:
            data = _read_user_file(d / "libvulkan_freedreno.so", MAX_DRIVER_BYTES)
            if not data or not is_arm64_glibc(data):
                continue
            meta = _read_user_file(d / "meta.json", MAX_META_BYTES)
        except OSError:
            continue
        label = d.name
        try:
            name = json.loads(meta or b"{}").get("name")
        except (ValueError, AttributeError):
            name = None
        if isinstance(name, str) and name.strip():
            label = name.strip()[:48]
        drivers.append({"data": USER_PREFIX + d.name, "label": f"{label} (ARM only)"})
    return sorted(drivers, key=lambda c: c["label"].lower())


def _series_key(name):
    return tuple(int(x) for x in re.findall(r"[0-9]+", name))


def mesa_versions():
    # "" runs each Proton's own default driver (ARM: host mesa; x86: the FEX rootfs's Turnip),
    # so it is labelled with mesa's manifest-only vk-arm dir, the host series.
    host, devel = [], []
    try:
        for p in ARM_DIR.iterdir():
            m = re.match(r"([0-9]+)\.([0-9]+)", p.name)
            if not m or not (p / "icd.json").is_file():
                continue
            series = f"{m.group(1)}.{m.group(2)}"
            if "devel" in p.name:
                devel.append(series)
            elif not (p / "libvulkan_freedreno.so").exists():
                host.append(series)
    except OSError:
        pass
    choices = [{"data": "", "label": f"{max(host, key=_series_key)} (default)" if host else "System default"}]
    if devel:
        choices.append({"data": "devel", "label": f"{max(devel, key=_series_key)} git (ARM only)"})
    return choices + user_drivers()
