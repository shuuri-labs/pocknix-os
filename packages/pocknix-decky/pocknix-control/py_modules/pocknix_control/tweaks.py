import copy
import json
import re
from pathlib import Path

from .system import atomically_write

# Ported from armada-control's tweaks.py (path swap). The tweaks file is consumed at game
# launch by pocknix-proton-wrapper (pocknix-steam); the profile contract ships with the
# wrapper at /usr/share/pocknix/fex-profiles.json, with a plugin-dir fallback copy.
TWEAKS_CONFIG = Path("/etc/pocknix/game-tweaks.json")
FEX_PROFILES_CONFIG = Path("/usr/share/pocknix/fex-profiles.json")
PLUGIN_FEX_PROFILES_CONFIG = Path(__file__).resolve().parent.parent.parent / "fex-profiles.json"
TURNIP_DIRS = {"arm": Path("/usr/share/pocknix/vk-arm"), "x86": Path("/usr/share/pocknix/vk-x86")}


def mesa_versions():
    # ARM payloads only: an x86 Proton's graphics come from the FEX rootfs, so a host pin never lands.
    series = {}
    for arch, base in [("arm", TURNIP_DIRS["arm"])]:
        try:
            versions = [p.name for p in base.iterdir() if (p / "icd.json").is_file()]
        except OSError:
            continue
        for v in versions:
            m = re.match(r"([0-9]+)\.([0-9]+)", v)
            if not m:
                continue
            entry = series.setdefault(f"{m.group(1)}.{m.group(2)}", {"archs": set(), "rc": True, "devel": True})
            entry["archs"].add(arch)
            entry["rc"] = entry["rc"] and "rc" in v
            entry["devel"] = entry["devel"] and "devel" in v
    choices = []
    for key, entry in series.items():
        # "git" marks an unreleased main snapshot, so a devel payload can't read as a
        # shipped release (the series key alone would show a bare "26.3").
        label = key + (" RC" if entry["rc"] else "") + (" git" if entry["devel"] else "")
        choices.append({"data": key, "label": label})
    return sorted(choices, key=lambda c: tuple(int(x) for x in c["data"].split(".")))


def load_fex_contract():
    path = FEX_PROFILES_CONFIG if FEX_PROFILES_CONFIG.exists() else PLUGIN_FEX_PROFILES_CONFIG
    with path.open(encoding="utf-8") as f:
        contract = json.load(f)
    profiles = contract.get("profiles")
    if not isinstance(contract.get("defaults"), dict) or not isinstance(profiles, dict) or "default" not in profiles:
        raise ValueError("invalid FEX profile contract")
    for profile in profiles.values():
        if not isinstance(profile, dict) or not isinstance(profile.get("config"), dict):
            raise ValueError("invalid FEX profile contract")
    return contract


def fex_profile_labels(contract):
    return {
        name: {"label": profile.get("label", name.title()), "config": profile.get("config", {})}
        for name, profile in contract["profiles"].items()
        if isinstance(profile, dict)
    }


def load_tweaks():
    contract = load_fex_contract()
    try:
        with TWEAKS_CONFIG.open(encoding="utf-8") as f:
            loaded = json.load(f)
    except (OSError, ValueError):
        return copy.deepcopy(contract["defaults"])
    data = copy.deepcopy(contract["defaults"])
    if isinstance(loaded, dict):
        if isinstance(loaded.get("global"), dict):
            data["global"].update(loaded["global"])
        if isinstance(loaded.get("games"), dict):
            data["games"] = {
                str(k): v for k, v in loaded["games"].items()
                if str(k).isdigit() and isinstance(v, dict)
            }
    for game in data["games"].values():
        if not isinstance(game, dict):
            continue
        game["enabled"] = bool(game.get("enabled", False))
    return data


def sanitize_tweaks(data):
    # This file is read by the proton wrapper at game launch, so reject non-appid keys
    # and oversized input.
    if not isinstance(data, dict):
        raise ValueError("tweaks must be an object")
    if len(json.dumps(data)) > 256 * 1024:
        raise ValueError("tweaks payload too large")
    clean = {"global": {}, "games": {}}
    if isinstance(data.get("global"), dict):
        clean["global"] = data["global"]
    raw_games = data.get("games")
    if isinstance(raw_games, dict):
        for gid, game in raw_games.items():
            if str(gid).isdigit() and isinstance(game, dict):
                clean["games"][str(gid)] = game
    return clean


def save_tweaks(data):
    atomically_write(TWEAKS_CONFIG, json.dumps(sanitize_tweaks(data), indent=2, sort_keys=True) + "\n", 0o644)
