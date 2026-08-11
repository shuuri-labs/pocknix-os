"""Sysfs sensor reads (battery capacity, thermal zones).

Separated from _colour.py so the colour math stays pure and unit-testable without
mocking sysfs.
"""
from pathlib import Path

BATTERY_CAPACITY = Path("/sys/class/power_supply/battery/capacity")
THERMAL_DIR = Path("/sys/class/thermal")


def read_capacity():
    try:
        return max(0, min(100, int(BATTERY_CAPACITY.read_text(encoding="utf-8").strip())))
    except (OSError, ValueError):
        return None


def thermal_zones():
    # Mirror pocknix-fancontrol's sensor selection: cpu*/gpu* zone types only, so the
    # LED and the fan see the same number. Returns the matching temp-file paths.
    zones = []
    for z in THERMAL_DIR.glob("thermal_zone*"):
        try:
            ztype = (z / "type").read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if ztype.startswith(("cpu", "gpu")):
            zones.append(z / "temp")
    return zones


def read_temp():
    # Arithmetic mean of all cpu*/gpu* zones, in °C. Matches pocknix-fancontrol's
    # awk '{s+=$1;n++} END{printf "%d", (n? s/n : 0)}' on the same file set.
    temps = []
    for tf in thermal_zones():
        try:
            temps.append(int(tf.read_text(encoding="utf-8").strip()))
        except (OSError, ValueError):
            continue
    if not temps:
        return None
    return (sum(temps) // len(temps)) // 1000
