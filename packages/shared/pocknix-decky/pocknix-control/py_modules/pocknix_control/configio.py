import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

from .system import atomically_write
from .tweaks import load_tweaks, save_tweaks

# Per-game config export/import. Export writes one profile, but the schema keeps a "games"
# map so a shared community pack carrying several still imports. Device-local settings (fan,
# global defaults) are outside GAME_KEYS and so never travel between devices.
EXPORT_DIR = Path("/home/deck/PocknixGameConfigs")
STEAM_CONFIG_VDF = Path("/home/deck/.local/share/Steam/config/config.vdf")
SCHEMA_VERSION = 1
MAX_IMPORT_BYTES = 512 * 1024
MAX_FIELD_LEN = 4096

GAME_KEYS = ("fexProfile", "audioLatency", "mesaVersion", "envVars", "lavdMode", "cpuPin")


def _device_model():
    try:
        model = Path("/proc/device-tree/model").read_bytes().decode("utf-8", "replace")
        return model.strip("\x00").strip() or "unknown"
    except OSError:
        return "unknown"


def _clean_str(value):
    return str(value)[:MAX_FIELD_LEN] if isinstance(value, (str, int, float)) else ""


def _compat_tool_mapping():
    # Appid "0" is the global-default compat slot: never export it. Setting it makes Steam
    # refuse all Proton downloads (Valve bug 6874).
    try:
        text = STEAM_CONFIG_VDF.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    opener = re.search(r'"CompatToolMapping"\s*\{', text)
    if not opener:
        return {}
    i, depth, start = opener.end(), 1, opener.end()
    while i < len(text) and depth:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    tools = {}
    for entry in re.finditer(r'"(\d+)"\s*\{([^{}]*)\}', text[start:i]):
        appid, body = entry.groups()
        name = re.search(r'"name"\s*"([^"]*)"', body)
        if appid != "0" and name and name.group(1):
            tools[appid] = name.group(1)
    return tools


def _slug(text, fallback):
    return re.sub(r"[^A-Za-z0-9]+", "-", str(text)).strip("-").lower()[:64] or fallback


def _ensure_export_dir():
    EXPORT_DIR.mkdir(mode=0o755, parents=True, exist_ok=True)
    try:
        shutil.chown(EXPORT_DIR, "deck", "deck")
    except (LookupError, OSError):
        pass
    return str(EXPORT_DIR)


def config_dir():
    return _ensure_export_dir()


def export_config(appid, name, basename="", allow_overwrite=False):
    # Collision handling is two-phase: an existing target returns {exists} without writing so
    # the UI can offer rename-or-overwrite, then call again with allow_overwrite.
    appid = str(appid)
    if not appid.isdigit():
        raise ValueError("invalid appid")
    tweaks = load_tweaks()
    entry = tweaks.get("games", {}).get(appid)
    entry = entry if isinstance(entry, dict) else {}
    name = _clean_str(name) or _clean_str(entry.get("name", "")) or appid
    base = _slug(basename, "") or _slug(name, appid)
    _ensure_export_dir()
    path = EXPORT_DIR / f"{base}.pocknix.json"
    if path.exists() and not allow_overwrite:
        return {"exists": True, "base": base, "path": str(path)}
    out = {"name": name, "enabled": entry.get("enabled") is True}
    for key in GAME_KEYS:
        if str(entry.get(key, "") or "").strip():
            out[key] = _clean_str(entry[key])
    tool = _compat_tool_mapping().get(appid)
    if tool:
        out["protonTool"] = tool
    payload = {
        "pocknixConfig": SCHEMA_VERSION,
        "exported": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "device": _device_model(),
        "games": {appid: out},
    }
    atomically_write(path, json.dumps(payload, indent=2, sort_keys=True) + "\n", 0o644)
    try:
        shutil.chown(path, "deck", "deck")
    except (LookupError, OSError):
        pass
    return {"exists": False, "base": base, "path": str(path)}


def _load_payload(path):
    # Imported files are foreign input: cap size and reduce every entry to the GAME_KEYS
    # allowlist rather than trusting the payload's shape.
    p = Path(str(path))
    if p.suffix.lower() != ".json":
        raise ValueError("not a .json file")
    if p.stat().st_size > MAX_IMPORT_BYTES:
        raise ValueError("file too large")
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("pocknixConfig"), int):
        raise ValueError("not a Pocknix config export")
    if data["pocknixConfig"] > SCHEMA_VERSION:
        raise ValueError("config from a newer Pocknix version")
    clean_games = {}
    if isinstance(data.get("games"), dict):
        for appid, entry in data["games"].items():
            if not str(appid).isdigit() or not isinstance(entry, dict):
                continue
            out = {"name": _clean_str(entry.get("name", "")), "enabled": entry.get("enabled") is True}
            for key in GAME_KEYS:
                if str(entry.get(key, "") or "").strip():
                    out[key] = _clean_str(entry[key])
            tool = _clean_str(entry.get("protonTool", ""))
            clean_games[str(appid)] = (out, tool)
    if not clean_games:
        raise ValueError("no game profiles in this file")
    return clean_games, data


def read_config(path):
    clean_games, data = _load_payload(path)
    return {
        "device": _clean_str(data.get("device", "")),
        "exported": _clean_str(data.get("exported", "")),
        "games": [{"appid": appid, "name": entry.get("name", ""), "protonTool": tool}
                  for appid, (entry, tool) in sorted(clean_games.items())],
    }


def apply_config(path, source_appid, target_appid, target_name):
    # The target is chosen by the user, not keyed by the exporter's appid: a non-Steam copy
    # carries its own shortcut appid. The compat tool must go back through Steam's own
    # SpecifyCompatTool API, so it is returned to the frontend rather than written here.
    target_appid = str(target_appid)
    if not target_appid.isdigit():
        raise ValueError("invalid target game")
    clean_games, _ = _load_payload(path)
    picked = clean_games.get(str(source_appid))
    if not picked:
        raise ValueError("profile not found in file")
    entry, tool = picked
    entry = dict(entry)
    entry["name"] = _clean_str(target_name) or entry.get("name", "")
    tweaks = load_tweaks()
    tweaks.setdefault("games", {})[target_appid] = entry
    save_tweaks(tweaks)
    return {"protonTool": tool, "fexProfile": entry.get("fexProfile", ""), "enabled": entry.get("enabled") is True}
