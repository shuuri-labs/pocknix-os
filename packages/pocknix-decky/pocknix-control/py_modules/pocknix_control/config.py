from .modes import fan_mode, lavd_mode
from .steam import installed_games
from .tweaks import fex_profile_labels, load_fex_contract, load_tweaks


def build_config():
    fex_contract = load_fex_contract()
    return {
        "fanMode": fan_mode(),
        "lavdMode": lavd_mode(),
        "tweaks": load_tweaks(),
        "fexProfiles": fex_profile_labels(fex_contract),
        "installedGames": installed_games(),
    }
