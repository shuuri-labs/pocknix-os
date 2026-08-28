import threading
from pathlib import Path

from .system import run_cmd

# The toggle itself lives in pocknix-tools, so the desktop menu and this plugin drive one
# implementation rather than two that can disagree.
SHARE = "/usr/bin/pocknix-share"

# Status is read straight off the filesystem, the way snapshots.py reads its own: this is
# polled every few seconds while the panel is open, and the alternative is spawning a
# transient unit per poll. `systemctl enable` creates exactly this symlink, and smb.service
# declares PIDFile=/run/smbd.pid, so both are load-bearing rather than incidental.
SMBD = Path("/usr/bin/smbd")
ENABLED_LINK = Path("/etc/systemd/system/multi-user.target.wants/smb.service")
SMBD_PID = Path("/run/smbd.pid")

# Installing samba is a network operation behind a user tap; one at a time.
_install_lock = threading.Lock()


def _host(args, timeout):
    # Everything that must run natively goes through systemd-run, for the reason updates.py
    # documents: this python is an x86_64 FEX guest. /usr/bin/bash and /usr/bin/systemctl are
    # SHADOWED by the FEX rootfs while pocknix-share, smbpasswd and pdbedit are not, so a
    # direct call would run an aarch64 shell script under an x86 bash and then exec native
    # binaries out of it. systemd-run hands the whole thing to PID 1 and sidesteps that.
    return run_cmd(
        ["systemd-run", "--quiet", "--collect", "--wait", "--pipe", *args],
        timeout=timeout,
    )


def share_status():
    return {
        "installed": SMBD.exists(),
        "on": ENABLED_LINK.exists(),
        "active": SMBD_PID.exists(),
    }


def set_share(on):
    # The plugin already runs as root ("flags": ["root"]), so no pkexec here — unlike Pocknix
    # Tools, which needs 55-pocknix-share.rules.
    proc = _host([SHARE, "on" if on else "off"], timeout=90)
    if proc is None or proc.returncode != 0:
        detail = ((proc.stderr if proc else "") or "").strip()[-200:]
        raise RuntimeError(f"Could not turn file sharing {'on' if on else 'off'}: {detail or 'no detail'}")
    return share_status()


def install_samba():
    if not _install_lock.acquire(blocking=False):
        raise RuntimeError("An install is already running")
    try:
        proc = _host(["/usr/bin/pacman", "-S", "--needed", "--noconfirm", "samba"], timeout=600)
        if proc is None or proc.returncode != 0:
            detail = ((proc.stderr if proc else "") or "").strip()[-200:]
            raise RuntimeError(f"Could not install Samba: {detail or 'timed out (slow mirror or no network?)'}")
        return share_status()
    finally:
        _install_lock.release()
