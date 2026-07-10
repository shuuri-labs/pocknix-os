import json
import re
import threading
from pathlib import Path

from .system import run_cmd

# The RP6's microSD slot is /dev/mmcblk0; the internal UFS OS disk is sda. The formatter
# re-enforces this (mmcblk-only + refuses the disk backing /), so this constant is a UI
# convenience, not the safety boundary.
SD_DISK = "/dev/mmcblk0"
SD_PART = "/dev/mmcblk0p1"
FORMATTER = "/usr/lib/hwsupport/format-device.sh"

LABEL_RE = re.compile(r"^[A-Za-z0-9_-]{1,16}$")  # ext4 volume labels cap at 16 bytes

_format_lock = threading.Lock()  # one format at a time; a second RPC fails fast


def _init_ns_mountpoint(part):
    # The loader lives in a private mount namespace (pocknix-decky-run), so our own
    # mountinfo misses automounts that happened after loader start; ask for PID 1's view.
    proc = run_cmd(["findmnt", "-N", "1", "-fno", "TARGET", part], timeout=10)
    if proc is None or proc.returncode != 0:
        return ""
    return (proc.stdout or "").strip()


def detect_sdcard():
    absent = {"present": False}
    if not Path(SD_DISK).exists():
        return absent
    # FSTYPE/LABEL come from the udev db on the shared /run tmpfs, so they stay current
    # inside the namespace even though the mount table doesn't.
    proc = run_cmd(["lsblk", "-J", "-b", "-o", "NAME,SIZE,FSTYPE,LABEL", SD_DISK], timeout=10)
    if proc is None or proc.returncode != 0:
        return absent
    try:
        disk = json.loads(proc.stdout)["blockdevices"][0]
    except (ValueError, LookupError):
        return absent
    # A partitioned card carries fs info on p1; a superfloppy carries it on the disk node.
    children = disk.get("children") or []
    fs_node = children[0] if children else disk
    part = f"/dev/{fs_node['name']}" if fs_node.get("name") else SD_PART
    return {
        "present": True,
        "device": SD_DISK,
        "sizeBytes": disk.get("size") or 0,
        "fstype": fs_node.get("fstype") or "",
        "label": fs_node.get("label") or "",
        "mountpoint": _init_ns_mountpoint(part),
    }


def format_sdcard(label):
    label = (label or "").strip() or "SDCARD"
    if not LABEL_RE.match(label):
        raise ValueError("Label must be 1-16 characters: letters, digits, - or _")
    if not Path(SD_DISK).exists():
        raise RuntimeError("No microSD card detected")
    if not _format_lock.acquire(blocking=False):
        raise RuntimeError("A format is already in progress")
    try:
        # Run the formatter through PID 1, not directly: in our private mount namespace its
        # umount would only detach the card locally while the init-namespace mount stayed
        # live under mkfs. systemd-run puts it in the init namespace (and with a clean env,
        # sidestepping the PyInstaller LD_LIBRARY_PATH poisoning entirely).
        proc = run_cmd(
            ["systemd-run", "--quiet", "--collect", "--wait", "--pipe",
             FORMATTER, "--device", SD_DISK, "--label", label, "--force"],
            timeout=600,
        )
    finally:
        _format_lock.release()
    if proc is None:
        raise RuntimeError("Formatter failed to spawn")
    if proc.returncode != 0:
        detail = ((proc.stderr or "") + (proc.stdout or "")).strip()[-300:]
        raise RuntimeError(f"Format failed (rc={proc.returncode}): {detail}")
    return detect_sdcard()
