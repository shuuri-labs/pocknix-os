import os
import subprocess
import tempfile


def atomically_write(path, text, mode=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def _clean_env():
    # PyInstaller points LD_LIBRARY_PATH at the bundle's own extracted x86_64 libs, so any
    # child re-resolving against them dies on symbol mismatches. It stashes the real value in
    # LD_LIBRARY_PATH_ORIG.
    env = os.environ.copy()
    orig = env.pop("LD_LIBRARY_PATH_ORIG", None)
    if orig:
        env["LD_LIBRARY_PATH"] = orig
    else:
        env.pop("LD_LIBRARY_PATH", None)
    return env


def run_cmd(cmd, timeout=5, capture=True):
    try:
        return subprocess.run(
            cmd,
            check=False,
            text=True,
            stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=timeout,
            env=_clean_env(),
        )
    except (OSError, subprocess.SubprocessError):
        return None
