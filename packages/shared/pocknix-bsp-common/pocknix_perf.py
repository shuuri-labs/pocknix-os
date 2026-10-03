"""Power-profile data for pocknix-perfd: parse, layer, validate, resolve.

Pure (no D-Bus, no sysfs writes) so scripts/check-power-profiles.py runs the exact code the
daemon runs.
"""
import configparser

FAN_MODES = ("quiet", "moderate", "performance")
LAVD_MODES = ("autopilot", "performance", "balanced", "powersave")
UNDERCLOCK_LEVELS = ("none", "small", "medium", "large")
PROFILE_KEYS = {"label", "fan", "lavd", "underclock", "cpu_max", "gpu_min", "gpu_max"}
SOC_OVERLAY_KEYS = {"gpu_min", "gpu_max"}
GENERAL_KEYS = {"default_profile", "gpu_manual_min"}


class FactoryError(ValueError):
    pass


def _parser():
    # Case-sensitive keys and no interpolation: values are plain words and numbers.
    p = configparser.ConfigParser(interpolation=None, strict=True)
    p.optionxform = str
    return p


def _ratio(raw, lo, hi):
    v = float(raw)
    if not lo <= v <= hi:
        raise ValueError(f"{raw} outside {lo}..{hi}")
    return v


def validate_profile(pid, keys):
    """keys: merged str->str for one profile. Returns the typed profile or raises ValueError."""
    unknown = set(keys) - PROFILE_KEYS
    if unknown:
        raise ValueError(f"unknown key(s) {sorted(unknown)}")
    missing = PROFILE_KEYS - {"label"} - set(keys)
    if missing:
        raise ValueError(f"missing key(s) {sorted(missing)}")
    prof = {
        "id": pid,
        "label": keys.get("label", pid.title()),
        "fan": keys["fan"],
        "lavd": keys["lavd"],
        "underclock": keys["underclock"],
        "cpu_max": _ratio(keys["cpu_max"], 0.3, 1.0),
        "gpu_min": _ratio(keys["gpu_min"], 0.0, 1.0),
        "gpu_max": _ratio(keys["gpu_max"], 0.3, 1.0),
    }
    if prof["fan"] not in FAN_MODES:
        raise ValueError(f"fan {prof['fan']!r} not in {FAN_MODES}")
    if prof["lavd"] not in LAVD_MODES:
        raise ValueError(f"lavd {prof['lavd']!r} not in {LAVD_MODES}")
    if prof["underclock"] not in UNDERCLOCK_LEVELS:
        raise ValueError(f"underclock {prof['underclock']!r} not in {UNDERCLOCK_LEVELS}")
    if prof["gpu_min"] > prof["gpu_max"]:
        raise ValueError("gpu_min > gpu_max")
    return prof


def _validate_overlay(keys):
    unknown = set(keys) - SOC_OVERLAY_KEYS
    if unknown:
        raise ValueError(f"unknown key(s) {sorted(unknown)}")
    return {k: _ratio(v, 0.0 if k == "gpu_min" else 0.3, 1.0) for k, v in keys.items()}


def load_factory(text):
    """Parse the factory file. Any defect raises FactoryError: it is a build-time bug."""
    p = _parser()
    try:
        p.read_string(text)
    except configparser.Error as e:
        raise FactoryError(f"factory file does not parse: {e}") from e
    if not p.has_section("general"):
        raise FactoryError("no [general] section")
    unknown = set(p["general"]) - GENERAL_KEYS
    if unknown:
        raise FactoryError(f"[general] unknown key(s) {sorted(unknown)}")
    data = {"order": [], "raw": {}, "profiles": {}, "overlays": {}, "tables": {}}
    for sec in p.sections():
        parts = sec.split(".")
        try:
            if parts[0] == "profile" and len(parts) == 2:
                data["order"].append(parts[1])
                data["raw"][parts[1]] = dict(p[sec])
                data["profiles"][parts[1]] = validate_profile(parts[1], dict(p[sec]))
            elif parts[0] == "profile" and len(parts) == 3:
                data["overlays"][(parts[1], parts[2])] = _validate_overlay(dict(p[sec]))
            elif parts[0] == "underclock" and len(parts) == 3:
                soc, level = parts[1], parts[2]
                if level not in UNDERCLOCK_LEVELS[1:]:
                    raise ValueError(f"level {level!r} not in {UNDERCLOCK_LEVELS[1:]}")
                caps = {}
                for k, v in p[sec].items():
                    if not k.startswith("policy") or not k[6:].isdigit():
                        raise ValueError(f"key {k!r} is not policyN")
                    caps[k] = int(v)
                data["tables"].setdefault(soc, {})[level] = caps
            elif sec != "general":
                raise ValueError("unknown section")
        except ValueError as e:
            raise FactoryError(f"[{sec}]: {e}") from e
    if not data["order"]:
        raise FactoryError("no profiles")
    for pid, soc in data["overlays"]:
        if pid not in data["profiles"]:
            raise FactoryError(f"[profile.{pid}.{soc}] overlays an unknown profile")
    g = p["general"]
    data["default"] = g.get("default_profile", "")
    if data["default"] not in data["profiles"]:
        raise FactoryError(f"default_profile {data['default']!r} is not a profile")
    try:
        data["gpu_manual_min"] = _ratio(g.get("gpu_manual_min", "0"), 0.0, 1.0)
    except ValueError as e:
        raise FactoryError(f"[general] gpu_manual_min: {e}") from e
    return data


def layer_override(factory, text):
    """Apply the /etc override over a parsed factory. Never raises: a bad profile keeps its
    factory definition and a bad file is ignored whole; both come back as warnings."""
    eff = {
        "order": list(factory["order"]),
        "profiles": dict(factory["profiles"]),
        "overlays": dict(factory["overlays"]),
        "tables": factory["tables"],
        "default": factory["default"],
        "gpu_manual_min": factory["gpu_manual_min"],
    }
    warnings = []
    if text is None:
        return eff, warnings
    p = _parser()
    try:
        p.read_string(text)
    except configparser.Error as e:
        return eff, [f"override ignored, does not parse: {e}"]
    for sec in p.sections():
        parts = sec.split(".")
        if parts[0] == "profile" and len(parts) == 2:
            pid = parts[1]
            if pid not in factory["profiles"]:
                warnings.append(f"[{sec}] ignored: no such profile")
                continue
            merged = dict(factory["raw"][pid])
            merged.update(p[sec])
            try:
                eff["profiles"][pid] = validate_profile(pid, merged)
            except ValueError as e:
                warnings.append(f"[{sec}] ignored, factory values kept: {e}")
        elif parts[0] == "profile" and len(parts) == 3:
            key = (parts[1], parts[2])
            if parts[1] not in factory["profiles"]:
                warnings.append(f"[{sec}] ignored: no such profile")
                continue
            merged = dict(factory["overlays"].get(key, {}))
            try:
                merged.update(_validate_overlay(dict(p[sec])))
                eff["overlays"][key] = merged
            except ValueError as e:
                warnings.append(f"[{sec}] ignored, factory values kept: {e}")
        elif sec == "general":
            for k, v in p[sec].items():
                if k == "default_profile" and v in factory["profiles"]:
                    eff["default"] = v
                elif k == "gpu_manual_min":
                    try:
                        eff["gpu_manual_min"] = _ratio(v, 0.0, 1.0)
                    except ValueError as e:
                        warnings.append(f"[general] gpu_manual_min ignored: {e}")
                else:
                    warnings.append(f"[general] {k}={v} ignored")
        else:
            # Underclock tables are hardware data, not a user preference.
            warnings.append(f"[{sec}] ignored: only profile and general sections are overridable")
    return eff, warnings


def choose_at_most(freqs, target):
    below = [f for f in freqs if f <= target]
    return max(below) if below else min(freqs)


def choose_at_least(freqs, target):
    above = [f for f in freqs if f >= target]
    return min(above) if above else max(freqs)


def resolve(eff, pid, soc, cpu_freqs, gpu_freqs):
    """Concrete targets for one profile on this SoC.
    cpu_freqs: {"policy0": [kHz...]}; gpu_freqs: [Hz...] (may be empty)."""
    prof = eff["profiles"][pid]
    overlay = eff["overlays"].get((pid, soc), {})
    gpu_min = overlay.get("gpu_min", prof["gpu_min"])
    gpu_max = overlay.get("gpu_max", prof["gpu_max"])
    table = eff["tables"].get(soc, {}).get(prof["underclock"])
    caps = {}
    for policy, freqs in cpu_freqs.items():
        top = max(freqs)
        if prof["underclock"] == "none":
            target = top
        elif table is not None:
            target = table.get(policy, top)
        else:
            target = int(top * prof["cpu_max"])
        caps[policy] = choose_at_most(freqs, target)
    out = {"cpu_max": caps, "fan": prof["fan"], "lavd": prof["lavd"]}
    if gpu_freqs:
        top = max(gpu_freqs)
        hi = choose_at_most(gpu_freqs, int(top * gpu_max))
        lo = choose_at_least(gpu_freqs, int(top * gpu_min)) if gpu_min > 0 else min(gpu_freqs)
        out["gpu_min"], out["gpu_max"] = min(lo, hi), hi
    return out


def soc_class(compatible):
    """compatible: the NUL-separated /proc/device-tree/compatible string."""
    for c in compatible.split("\0"):
        if c.startswith("qcom,sm") and c[7:].isdigit():
            return "SM" + c[7:]
    return ""
