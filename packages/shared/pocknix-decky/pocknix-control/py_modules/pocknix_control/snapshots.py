import json
import os
import re
import threading
from pathlib import Path

from .system import run_cmd
from .updates import _unit_running

# Status is file-reads only (poll-safe, no subprocess): the loader's private mount
# namespace inherits the boot-time fstab mounts, /run is the shared tmpfs, and the
# snapshot metadata is plain JSON written by the pocknix-snapshots alpm hooks.
SNAP_DIR = Path("/.snapshots")
SNAP_CONF = Path("/etc/pocknix/snapshots.conf")
ROLLBACK_INFO = Path("/var/lib/pocknix/rollback-info.json")
REBOOT_REQUIRED = Path("/run/pocknix/reboot-required")
ROLLBACK_CLI = "/usr/bin/pocknix-rollback"

ID_RE = re.compile(r"^[0-9]{4}$")

_rollback_lock = threading.Lock()  # one rollback at a time; a second RPC fails fast


def _mounts():
    try:
        with open("/proc/self/mounts", encoding="utf-8") as f:
            return [line.split() for line in f]
    except OSError:
        return []


def _supported():
    root_btrfs = any(m[1] == "/" and m[2] == "btrfs" for m in _mounts() if len(m) > 2)
    snapdir_mounted = any(m[1] == "/.snapshots" for m in _mounts() if len(m) > 1)
    return root_btrfs and snapdir_mounted


def _warn_free_mib():
    # sourced as shell by snapshot-lib.sh; here a regex is enough
    try:
        match = re.search(r"^POCKNIX_SNAPSHOT_WARN_FREE_MIB=(\d+)", SNAP_CONF.read_text(), re.M)
        return int(match.group(1)) if match else 5120
    except (OSError, ValueError):
        return 5120


def _read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def snapshot_status():
    supported = _supported()
    status = {
        "supported": supported,
        "freeBytes": 0,
        "totalBytes": 0,
        "lowSpace": False,
        "rebootRequired": REBOOT_REQUIRED.exists(),
        "rolledBack": None,
        "snapshots": [],
    }
    if not supported:
        return status
    try:
        stat = os.statvfs(SNAP_DIR)
        status["freeBytes"] = stat.f_bavail * stat.f_frsize
        status["totalBytes"] = stat.f_blocks * stat.f_frsize
    except OSError:
        pass
    status["lowSpace"] = 0 < status["freeBytes"] < _warn_free_mib() * 1024 * 1024
    rollback_info = _read_json(ROLLBACK_INFO)
    if rollback_info:
        status["rolledBack"] = {
            "fromSnapshot": rollback_info.get("from_snapshot", "?"),
            "ts": rollback_info.get("ts", ""),
        }
    snapshots = []
    try:
        entries = sorted(d for d in os.listdir(SNAP_DIR) if ID_RE.match(d))
    except OSError:
        entries = []
    for entry in entries:
        info = _read_json(SNAP_DIR / entry / "info.json")
        if not info:
            continue
        head = info.get("targets_head") or []
        count = info.get("targets_count") or len(head)
        snapshots.append({
            "id": info.get("id", entry),
            "created": info.get("created", ""),
            "ok": bool(info.get("transaction_ok")),
            "kernel": bool(info.get("kernel_in_transaction")),
            "targets": " ".join(head) + (f" (+{count - len(head)} more)" if count > len(head) else ""),
        })
    status["snapshots"] = snapshots  # oldest -> newest; the UI rolls back to the last one
    return status


def start_rollback(snapshot_id):
    if not _supported():
        raise RuntimeError("Snapshots are not supported on this install")
    if not ID_RE.match(snapshot_id or ""):
        raise ValueError(f"Bad snapshot id: {snapshot_id!r}")
    if not (SNAP_DIR / snapshot_id / "snapshot").is_dir():
        raise RuntimeError(f"Snapshot {snapshot_id} not found")
    if _unit_running():
        raise RuntimeError("An update is running — wait for it to finish first")
    if not _rollback_lock.acquire(blocking=False):
        raise RuntimeError("A rollback is already in progress")
    try:
        # Through PID 1 like every privileged op (init namespace + clean env; the CLI
        # stages boot files, then flips the btrfs default subvol — seconds, so --wait).
        proc = run_cmd(
            ["systemd-run", "--quiet", "--collect", "--wait", "--pipe",
             ROLLBACK_CLI, "--to", snapshot_id, "--yes"],
            timeout=240,
        )
    finally:
        _rollback_lock.release()
    if proc is None:
        raise RuntimeError("Rollback failed to spawn")
    if proc.returncode != 0:
        detail = ((proc.stderr or "") + (proc.stdout or "")).strip()[-300:]
        raise RuntimeError(f"Rollback failed (rc={proc.returncode}): {detail}")
    return snapshot_status()


def reboot_system():
    # detached: the RPC returns before the session dies under us
    proc = run_cmd(["systemd-run", "--quiet", "--collect", "/usr/bin/systemctl", "reboot"], timeout=10)
    if proc is None or proc.returncode != 0:
        raise RuntimeError("Could not reboot")
    return True
