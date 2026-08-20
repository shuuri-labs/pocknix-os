import re
import threading
from pathlib import Path

from .system import run_cmd

# The upgrade runs as a detached transient unit under PID 1 so the loader or Steam dying
# mid-update cannot kill the pacman transaction; the QAM re-attaches to the log on reopen.
UNIT = "pocknix-qam-update"
# Lives in /run so a reboot clears the finished/failed state together with the log.
LOG = Path("/run/pocknix-update.log")
EXIT_MARK = "POCKNIX_UPDATE_EXIT:"

# checkupdates(8) trick without pacman-contrib: refresh a THROWAWAY sync db copy and query
# against it, so the real db is never -Sy'd without -u (partial-upgrade setup).
CHECK_DB = Path("/run/pocknix-check-db")

VER_RE = re.compile(r"^(\S+)\s+(\S+)$")

# Serialization must live here, not in the frontend: its 'checking' state dies with the QAM
# panel, so close-mid-check then retap raced pacman on the throwaway db ("unable to lock database").
_check_lock = threading.Lock()


def _pacman(args, timeout):
    # Never call pacman in-process: this python is an x86_64 FEX guest, so a bare "pacman"
    # resolves into the FEX rootfs overlay - a foreign pacman on a stock pacman.conf (no
    # [pocknix] repo, so pins vanish) whose download sandbox also dies under emulation.
    return run_cmd(
        ["systemd-run", "--quiet", "--collect", "--wait", "--pipe", "/usr/bin/pacman", *args],
        timeout=timeout,
    )


def _unit_running():
    proc = run_cmd(["systemctl", "is-active", f"{UNIT}.service"], timeout=5)
    if proc is None:
        return False
    return (proc.stdout or "").strip() in ("active", "activating", "deactivating")


def check_updates():
    if _unit_running():
        raise RuntimeError("An update is already running")
    if not _check_lock.acquire(blocking=False):
        raise RuntimeError("Already checking for updates — give it a moment and try again")
    try:
        return _check_updates_locked()
    finally:
        _check_lock.release()


def _check_updates_locked():
    (CHECK_DB / "sync").mkdir(parents=True, exist_ok=True)
    local = CHECK_DB / "local"
    if not local.exists():
        local.symlink_to("/var/lib/pacman/local")
    # _check_lock serializes every real user of this throwaway db, so a db.lck here
    # is a leftover from a killed check — without this, checking stays broken until reboot
    (CHECK_DB / "db.lck").unlink(missing_ok=True)
    proc = _pacman(["-Sy", "--dbpath", str(CHECK_DB), "--logfile", "/dev/null"], timeout=180)
    if proc is None or proc.returncode != 0:
        detail = ((proc.stderr if proc else "") or "").strip()[-200:]
        raise RuntimeError(f"Could not refresh package databases: {detail or 'timed out (slow mirror or no network?)'}")
    # -Sup resolves like the real -Syu (repo order, IgnorePkg, replaces); -Qu would report any
    # repo's newer version and so falsely list packages held back by [pocknix] priority.
    proc = _pacman(["-Sup", "--dbpath", str(CHECK_DB), "--print-format", "%n %v"], timeout=60)
    if proc is None or proc.returncode != 0:
        detail = ((proc.stderr if proc else "") or "").strip()[-200:]
        raise RuntimeError(f"Could not resolve upgrades: {detail}")
    targets = {}
    for line in (proc.stdout or "").splitlines():
        line = line.strip()
        if not line or line.startswith("::"):
            continue
        match = VER_RE.match(line)
        if match:
            targets[match.group(1)] = match.group(2)
    if not targets:
        return []
    current = {}
    proc = _pacman(["-Q"], timeout=30)
    if proc and proc.returncode == 0:
        for line in (proc.stdout or "").splitlines():
            match = VER_RE.match(line.strip())
            if match:
                current[match.group(1)] = match.group(2)
    return [
        {"name": name, "current": current.get(name, "new"), "latest": latest}
        for name, latest in sorted(targets.items())
    ]


def start_update():
    if _unit_running():
        raise RuntimeError("An update is already running")
    LOG.unlink(missing_ok=True)
    # --noprogressbar keeps the log line-oriented; the exit marker is how status() learns
    # the result after --collect has reaped the unit.
    script = f'pacman -Syu --noconfirm --noprogressbar; echo "{EXIT_MARK}$?"'
    proc = run_cmd(
        ["systemd-run", "--quiet", "--collect", "--unit", UNIT,
         "--property", f"StandardOutput=append:{LOG}",
         "--property", "StandardError=inherit",
         "/bin/sh", "-c", script],
        timeout=15,
    )
    if proc is None or proc.returncode != 0:
        detail = ((proc.stderr if proc else "") or "").strip()[-200:]
        raise RuntimeError(f"Could not start the update: {detail}")
    return update_status()


def update_status():
    try:
        lines = [line for line in LOG.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]
    except OSError:
        lines = []
    exit_code = None
    if lines and lines[-1].startswith(EXIT_MARK):
        try:
            exit_code = int(lines[-1][len(EXIT_MARK):])
        except ValueError:
            exit_code = -1
        lines = lines[:-1]
    return {
        "running": _unit_running(),
        "log": "\n".join(lines[-6:]),
        "exitCode": exit_code,
    }
