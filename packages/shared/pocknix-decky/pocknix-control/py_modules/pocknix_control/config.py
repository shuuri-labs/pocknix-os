from .led import led_config
from .modes import fan_mode, lavd_mode
from .steam import installed_games
from .system import run_cmd
from .turnip import mesa_versions
from .tweaks import fex_profile_labels, load_fex_contract, load_tweaks


def prime_core():
    # "" hides Fastest Core First: no standout core, or a pocknix-bsp-common without the lookup.
    proc = run_cmd(["/bin/sh", "-c", ". /usr/lib/pocknix/cores.sh && pocknix_prime_core"])
    out = (proc.stdout or "").strip() if proc and proc.returncode == 0 else ""
    return out if out.isdigit() else ""


def build_config():
    fex_contract = load_fex_contract()
    return {
        "fanMode": fan_mode(),
        "lavdMode": lavd_mode(),
        "tweaks": load_tweaks(),
        "fexProfiles": fex_profile_labels(fex_contract),
        "mesaVersions": mesa_versions(),
        "installedGames": installed_games(),
        "led": led_config(),
        "primeCore": prime_core(),
    }
