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
    # Decky's PluginLoader is a PyInstaller bundle: it points LD_LIBRARY_PATH at its own
    # extracted (x86_64) libs. A child that re-resolves shared libraries against them dies —
    # concretely, the FEX-rootfs /bin/sh picked up PyInstaller's older libreadline and failed
    # with "undefined symbol: rl_trim_arg_from_keyseq" (rc=127). PyInstaller preserves the
    # original value in LD_LIBRARY_PATH_ORIG; restore it, else drop the variable.
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
