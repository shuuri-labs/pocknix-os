"""Gamepad calibration. Maths ported from GPcal (Kdog, MIT, LICENSE.gpcal); the conf is
replayed at boot by pocknix-gamepad-calibration, before InputPlumber claims the pad."""

import fcntl
import glob
import json
import os
import struct
import threading
import time
from pathlib import Path

from .system import atomically_write, run_cmd

CONF = Path("/etc/pocknix/gamepad-calibration.conf")
DEFAULTS = Path("/run/pocknix/gamepad-calibration.defaults")
# composite left in intercept, for recover() after a crash
INTERCEPT_MARK = Path("/run/pocknix/calibration-intercept")

# coupled: the driver converts triggers as trigger_*_max - raw, so max is also the zero
# reference (retroid, mangmi). rsinput carries a fixed 0x610 reference (kernel 1064).
DRIVERS = {
    "rsinput": {"phys": "rsinput-gamepad/", "triggers": (2, 5), "coupled": False},
    "retroid": {"phys": "retroid-pocket-gamepad/", "triggers": (20, 21), "coupled": True},
    "mangmi_pocket_max": {"phys": "mangmi-pocket-max/", "triggers": (20, 21), "coupled": True},
}
STICK_CODES = {"axis_leftx": 0, "axis_lefty": 1, "axis_rightx": 3, "axis_righty": 4}
AXIS_SUFFIXES = ("max", "min", "center", "deadzone", "antideadzone")
TRIGGER_SUFFIXES = ("max", "deadzone", "antideadzone")

AXIS_MAX_PERCENT = 95
AXIS_DEADZONE_PERCENT = 150
AXIS_DEADZONE_PERCENT_MINI = 5
AXIS_ANTIDEADZONE_PERCENT = 80
TRIGGER_MAX_PERCENT = 100
TRIGGER_DEADZONE_PERCENT = 105
TRIGGER_ANTIDEADZONE_PERCENT = 80
# Above any raw reading, so a coupled-trigger capture is not cut short.
COUPLED_TRIGGER_CAPTURE_MAX = 0x755

HOLD_S = 0.5
HOLD_TOLERANCE = 0.03
SAMPLE_S = 0.01
# Status polls double as a heartbeat: without them the pad must not stay diverted from Steam.
WATCHDOG_S = 3.0

EVIOCGABS = 0x80184540
INTERCEPT_ALWAYS = 2
INTERCEPT_NONE = 0

STEPS = [
    ("stick", "axis_leftx", "Left stick", ("right", "left")),
    ("stick", "axis_leftx", "Left stick", ("left", "right")),
    ("stick", "axis_lefty", "Left stick", ("down", "up")),
    ("stick", "axis_lefty", "Left stick", ("up", "down")),
    ("stick", "axis_rightx", "Right stick", ("right", "left")),
    ("stick", "axis_rightx", "Right stick", ("left", "right")),
    ("stick", "axis_righty", "Right stick", ("down", "up")),
    ("stick", "axis_righty", "Right stick", ("up", "down")),
    ("trigger", "trigger_left", "Left trigger", None),
    ("trigger", "trigger_right", "Right trigger", None),
]


def _host(args, timeout=10):
    # busctl under PID 1: a loader restart cannot kill it mid-call.
    return run_cmd(["systemd-run", "--quiet", "--collect", "--wait", "--pipe", *args], timeout=timeout)


def _driver():
    for name, info in DRIVERS.items():
        params = Path(f"/sys/module/{name}/parameters")
        if (params / "axis_leftx_max").exists() and (params / "update_params").exists():
            return name, info, params
    return None, None, None


def _event_node(phys_prefix):
    for d in sorted(glob.glob("/sys/class/input/event*")):
        try:
            if Path(d, "device/phys").read_text().strip().startswith(phys_prefix):
                return "/dev/input/" + os.path.basename(d)
        except OSError:
            continue
    return None


def _absinfo(fd, code):
    buf = bytearray(24)
    fcntl.ioctl(fd, EVIOCGABS + code, buf)
    value, minimum, maximum, _fuzz, _flat, _res = struct.unpack("iiiiii", buf)
    return value, minimum, maximum


def _param_keys(control):
    suffixes = TRIGGER_SUFFIXES if control.startswith("trigger_") else AXIS_SUFFIXES
    return [f"{control}_{s}" for s in suffixes]


def _all_keys():
    keys = []
    for control in ("axis_leftx", "axis_lefty", "axis_rightx", "axis_righty", "trigger_left", "trigger_right"):
        keys += _param_keys(control)
    return keys


def _read_params(params):
    values = {}
    for key in _all_keys():
        try:
            values[key] = int((params / key).read_text().strip())
        except (OSError, ValueError):
            pass
    return values


def _write_params(params, values):
    for key, value in values.items():
        (params / key).write_text(str(int(value)))
    # the driver only re-reads its parameters (and re-advertises the evdev ranges) on this
    (params / "update_params").write_text("1")


def _parse_kv(text):
    values = {}
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not sep or not key or key.startswith("#"):
            continue
        try:
            values[key] = int(value)
        except ValueError:
            continue
    return values


def _defaults(params):
    try:
        values = _parse_kv(DEFAULTS.read_text())
    except OSError:
        values = {}
    return {k: v for k, v in values.items() if k in _all_keys() and (params / k).exists()}


def _composite_for(node):
    proc = _host(["busctl", "--list", "tree", "org.shadowblip.InputPlumber"])
    if proc is None or proc.returncode != 0:
        return None
    for path in proc.stdout.split():
        if not path.rsplit("/", 1)[-1].startswith("CompositeDevice"):
            continue
        prop = _host(["busctl", "--json=short", "get-property", "org.shadowblip.InputPlumber", path,
                      "org.shadowblip.Input.CompositeDevice", "SourceDevicePaths"])
        if prop is None or prop.returncode != 0:
            continue
        try:
            if node in json.loads(prop.stdout).get("data", []):
                return path
        except ValueError:
            continue
    return None


def _set_intercept(path, mode):
    proc = _host(["busctl", "set-property", "org.shadowblip.InputPlumber", path,
                  "org.shadowblip.Input.CompositeDevice", "InterceptMode", "u", str(mode)])
    return proc is not None and proc.returncode == 0


def stick_params(control, pos_extreme, pos_settle, neg_extreme, neg_settle):
    center = (pos_settle + neg_settle) / 2
    pos_extreme, pos_settle = pos_extreme - center, pos_settle - center
    neg_extreme, neg_settle = neg_extreme - center, neg_settle - center
    axis_max = AXIS_MAX_PERCENT * min(abs(neg_extreme), pos_extreme) / 100
    deadzone = AXIS_DEADZONE_PERCENT * (abs(neg_settle) + abs(pos_settle)) / 200
    if axis_max > 0 and 100 * deadzone / axis_max < AXIS_DEADZONE_PERCENT_MINI:
        deadzone = AXIS_DEADZONE_PERCENT_MINI * axis_max / 100
    return {
        f"{control}_max": int(axis_max),
        f"{control}_min": -int(axis_max),
        f"{control}_center": -int(center),
        f"{control}_deadzone": int(deadzone),
        f"{control}_antideadzone": int(AXIS_ANTIDEADZONE_PERCENT * deadzone / 100),
    }


def trigger_params(control, full, settle, coupled):
    if coupled:
        # max is also the zero reference here, so it moves down to the rest point.
        maximum = TRIGGER_MAX_PERCENT * (full - settle) / 100
        deadzone = (TRIGGER_DEADZONE_PERCENT - 100) * settle / 100
    else:
        # Fixed reference: rest still reads `settle`, so the deadzone must cover it.
        maximum = TRIGGER_MAX_PERCENT * full / 100
        deadzone = TRIGGER_DEADZONE_PERCENT * settle / 100
    return {
        f"{control}_max": int(maximum),
        f"{control}_deadzone": int(deadzone),
        f"{control}_antideadzone": int(TRIGGER_ANTIDEADZONE_PERCENT * deadzone / 100),
    }


class _Session:
    def __init__(self):
        self.lock = threading.Lock()
        self.phase = "idle"  # idle | capture | review
        self.step = 0
        self.progress = 0.0
        self.stage = "push"  # push | release, within the current step
        self.error = ""
        self.result = {}
        self.backup = {}
        self.composite = None
        self.thread = None
        self.stop = threading.Event()
        self.last_poll = 0.0


_session = _Session()


def _open_pad():
    name, info, params = _driver()
    if not name:
        return None, None, None, None
    node = _event_node(info["phys"])
    if not node:
        return name, info, params, None
    return name, info, params, os.open(node, os.O_RDONLY | os.O_NONBLOCK)


def _live(fd, info):
    out = {}
    for label, code in (("lx", 0), ("ly", 1), ("rx", 3), ("ry", 4)):
        value, minimum, maximum = _absinfo(fd, code)
        span = max(maximum, -minimum, 1)
        out[label] = round(max(-1.0, min(1.0, value / span)), 3)
    for label, code in zip(("lt", "rt"), info["triggers"]):
        value, _minimum, maximum = _absinfo(fd, code)
        out[label] = round(max(0.0, min(1.0, value / max(maximum, 1))), 3)
    return out


def _hold(fd, code, accept, scale, stage):
    """Mean of the first HOLD_S window where accept() held steady; InterruptedError on stop."""
    with _session.lock:
        _session.stage = stage
        _session.progress = 0.0
    window = []
    while not _session.stop.is_set():
        if time.monotonic() - _session.last_poll > WATCHDOG_S:
            raise InterruptedError("calibration screen stopped responding")
        value = _absinfo(fd, code)[0]
        now = time.monotonic()
        if accept(value) and (not window or abs(value - window[0][1]) <= HOLD_TOLERANCE * scale):
            window.append((now, value))
        else:
            window = [(now, value)] if accept(value) else []
        held = (window[-1][0] - window[0][0]) if window else 0.0
        with _session.lock:
            _session.progress = min(held / HOLD_S, 1.0)
        if held >= HOLD_S:
            return sum(v for _, v in window) / len(window)
        time.sleep(SAMPLE_S)
    raise InterruptedError("cancelled")


def _capture(fd, info, params, neutral_scale):
    result = {}
    stick = {}
    for index, (kind, control, _label, _dirs) in enumerate(STEPS):
        with _session.lock:
            _session.step = index
            _session.progress = 0.0
        if kind == "stick":
            code = STICK_CODES[control]
            scale = neutral_scale[control]
            first = control not in stick
            # Axis sign conventions differ per driver: accept either way first, then the opposite.
            if first:
                accept = lambda v, s=scale: abs(v) > s / 2
            else:
                sign = -1 if stick[control]["first_sign"] > 0 else 1
                accept = lambda v, s=scale, g=sign: g * v > s / 2
            extreme = _hold(fd, code, accept, scale, "push")
            settle = _hold(fd, code, lambda v, s=scale: abs(v) < s / 2, scale, "release")
            if first:
                stick[control] = {"first_sign": 1 if extreme > 0 else -1, "a": (extreme, settle)}
            else:
                a_ext, a_set = stick[control]["a"]
                if a_ext > 0:
                    pos, neg = (a_ext, a_set), (extreme, settle)
                else:
                    pos, neg = (extreme, settle), (a_ext, a_set)
                result.update(stick_params(control, pos[0], pos[1], neg[0], neg[1]))
        else:
            code = info["triggers"][0 if control == "trigger_left" else 1]
            scale = neutral_scale[control]
            full = _hold(fd, code, lambda v, s=scale: v > s / 2, scale, "push")
            settle = _hold(fd, code, lambda v, s=scale: v < s / 2, scale, "release")
            result.update(trigger_params(control, full, settle, info["coupled"]))
    return result


def _run(fd, info, params, neutral_scale):
    try:
        result = _capture(fd, info, params, neutral_scale)
        _write_params(params, result)
        with _session.lock:
            _session.result = result
            _session.phase = "review"
    except Exception as error:  # noqa: BLE001 - any failure must restore the pad
        try:
            _write_params(params, _session.backup)
        except OSError:
            pass
        with _session.lock:
            _session.phase = "idle"
            _session.error = "" if str(error) == "cancelled" else str(error)
    finally:
        _end_intercept()
        os.close(fd)


def _end_intercept():
    path = _session.composite
    if path:
        _set_intercept(path, INTERCEPT_NONE)
    _session.composite = None
    try:
        INTERCEPT_MARK.unlink()
    except FileNotFoundError:
        pass


def status():
    name, info, params = _driver()
    with _session.lock:
        _session.last_poll = time.monotonic()
        out = {
            "available": bool(name),
            "backend": name or "",
            "saved": CONF.exists(),
            "phase": _session.phase,
            "step": _session.step,
            "steps": len(STEPS),
            "progress": round(_session.progress, 2),
            "error": _session.error,
            "result": _session.result,
        }
        if _session.phase == "capture":
            kind, _control, label, dirs = STEPS[_session.step]
            out["control"] = label
            out["kind"] = kind
            out["direction"] = dirs[0] if dirs else ""
            out["stage"] = _session.stage
    if name:
        node = _event_node(info["phys"])
        if node:
            fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
            try:
                out["live"] = _live(fd, info)
            finally:
                os.close(fd)
    return out


def start():
    with _session.lock:
        if _session.phase == "capture":
            raise RuntimeError("Calibration is already running")
    name, info, params, fd = _open_pad()
    if not name:
        raise RuntimeError("No calibratable gamepad driver on this device")
    if fd is None:
        raise RuntimeError("Gamepad input device not found")
    try:
        backup = _read_params(params)
        defaults = _defaults(params)
        # Measure on neutral parameters so a recalibration never builds on the last one.
        neutral = {}
        neutral_scale = {}
        for control in STICK_CODES:
            rng = abs(defaults.get(f"{control}_max", backup.get(f"{control}_max", 0x580)))
            neutral.update({f"{control}_max": rng, f"{control}_min": -rng, f"{control}_center": 0,
                            f"{control}_deadzone": 0, f"{control}_antideadzone": 0})
            neutral_scale[control] = rng
        for control in ("trigger_left", "trigger_right"):
            if info["coupled"]:
                ref = COUPLED_TRIGGER_CAPTURE_MAX
            else:
                ref = defaults.get(f"{control}_max", backup.get(f"{control}_max", 0x610))
            neutral.update({f"{control}_max": ref, f"{control}_deadzone": 0, f"{control}_antideadzone": 0})
            neutral_scale[control] = ref
        node = _event_node(info["phys"])
        composite = _composite_for(node)
        if not composite:
            raise RuntimeError("InputPlumber is not managing the gamepad")
        _write_params(params, neutral)
        INTERCEPT_MARK.parent.mkdir(parents=True, exist_ok=True)
        INTERCEPT_MARK.write_text(composite)
        if not _set_intercept(composite, INTERCEPT_ALWAYS):
            INTERCEPT_MARK.unlink()
            _write_params(params, backup)
            raise RuntimeError("Could not take the gamepad from Steam for calibration")
    except Exception:
        os.close(fd)
        raise
    with _session.lock:
        _session.backup = backup
        _session.composite = composite
        _session.phase = "capture"
        _session.step = 0
        _session.progress = 0.0
        _session.error = ""
        _session.result = {}
        _session.stop.clear()
        _session.last_poll = time.monotonic()
        _session.thread = threading.Thread(target=_run, args=(fd, info, params, neutral_scale), daemon=True)
        _session.thread.start()
    return status()


def cancel():
    thread = _session.thread
    if thread and thread.is_alive():
        _session.stop.set()
        thread.join(timeout=5)
    _name, _info, params = _driver()
    with _session.lock:
        if _session.phase == "review" and params and _session.backup:
            _write_params(params, _session.backup)
        _session.phase = "idle"
        _session.result = {}
    return status()


def save():
    with _session.lock:
        if _session.phase != "review":
            raise RuntimeError("Nothing to save: run a calibration first")
        result = dict(_session.result)
    lines = ["# Written by Pocknix Control: gamepad driver parameters, replayed at boot."]
    lines += [f"{key}={result[key]}" for key in _all_keys() if key in result]
    atomically_write(CONF, "\n".join(lines) + "\n", mode=0o644)
    with _session.lock:
        _session.phase = "idle"
        _session.result = {}
        _session.backup = {}
    return status()


def reset():
    with _session.lock:
        if _session.phase == "capture":
            raise RuntimeError("Finish or cancel the calibration first")
    _name, _info, params = _driver()
    if not params:
        raise RuntimeError("No calibratable gamepad driver on this device")
    defaults = _defaults(params)
    if not defaults:
        raise RuntimeError("Driver defaults were not recorded this boot; reboot and try again")
    try:
        CONF.unlink()
    except FileNotFoundError:
        pass
    _write_params(params, defaults)
    with _session.lock:
        _session.phase = "idle"
        _session.result = {}
    return status()


def recover():
    # No session survives a plugin reload: drop its intercept and re-apply the saved values.
    try:
        path = INTERCEPT_MARK.read_text().strip()
    except OSError:
        return
    if path:
        _set_intercept(path, INTERCEPT_NONE)
    INTERCEPT_MARK.unlink(missing_ok=True)
    _name, _info, params = _driver()
    if not params:
        return
    try:
        values = _parse_kv(CONF.read_text())
    except OSError:
        values = _defaults(params)
    values = {k: v for k, v in values.items() if k in _all_keys() and (params / k).exists()}
    if values:
        _write_params(params, values)
