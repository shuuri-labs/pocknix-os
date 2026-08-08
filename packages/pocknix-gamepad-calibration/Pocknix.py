"""
    Pocknix: runtime hardware discovery for GPcal
    SPDX-License-Identifier: MIT

    Upstream hardcodes the RP5's driver, evdev name and trigger axis codes.
    One package serves every board, so all three are discovered at runtime.
"""

import os
from pathlib import Path

# Persisted calibration, replayed at boot by pocknix-gamepad-calibration.service.
CONFIG_PATH = Path("/etc/pocknix/gamepad-calibration.conf")

SYS_MODULE = Path("/sys/module")
INPUT_CLASS = Path("/sys/class/input")
INPUT_DEV_DIR = Path("/dev/input")

# evdev ABS codes. rsinput (sm8550) reports the analog triggers on Z/RZ,
# retroid and mangmi (sm8250) on HAT2X/HAT2Y.
ABS_X = 0x00
ABS_Y = 0x01
ABS_Z = 0x02
ABS_RX = 0x03
ABS_RY = 0x04
ABS_RZ = 0x05
ABS_HAT2X = 0x14
ABS_HAT2Y = 0x15

# 320x240 at scale 1 is a postage stamp on a 1080p panel.
DISPLAY_SCALE = int(os.environ.get("POCKNIX_GPCAL_SCALE", "3"))

# Physical pads we know; anything else falls back to capability matching.
KNOWN_PHYS = ("rsinput-gamepad", "retroid-pocket-gamepad", "mangmi-pocket-max")


def find_parameters_dir():
    for params in sorted(SYS_MODULE.glob("*/parameters")):
        if (params / "axis_leftx_max").exists() and (params / "update_params").exists():
            return params
    return None


def _read_attr(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def _abs_capabilities(device):
    """Parse the evdev ABS bitmask (kernel prints 64-bit words, most significant first)."""
    value = 0
    for word in _read_attr(device / "capabilities" / "abs").split():
        value = (value << 64) | int(word, 16)
    return value


def _has(caps, *codes):
    return all(caps & (1 << code) for code in codes)


def find_gamepad():
    """Return (event node path or None, (left trigger code, right trigger code)).

    Physical devices only: InputPlumber's virtual `deck` target carries the same
    axes but reports values it has already scaled, not the raw ones.
    """
    fallback = None

    for event in sorted(INPUT_CLASS.glob("event*")):
        device = event / "device"
        if "/devices/virtual/" in str(event.resolve()):
            continue

        caps = _abs_capabilities(device)
        if not _has(caps, ABS_X, ABS_Y, ABS_RX, ABS_RY):
            continue

        if _has(caps, ABS_HAT2X, ABS_HAT2Y):
            triggers = (ABS_HAT2X, ABS_HAT2Y)
        else:
            triggers = (ABS_Z, ABS_RZ)

        candidate = (INPUT_DEV_DIR / event.name, triggers)
        phys = _read_attr(device / "phys")
        if phys.split("/")[0] in KNOWN_PHYS:
            return candidate
        if fallback is None:
            fallback = candidate

    return fallback if fallback else (None, (ABS_Z, ABS_RZ))
