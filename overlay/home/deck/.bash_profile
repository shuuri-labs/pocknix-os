# pocknix-os — boot-to-Steam hook (non-root 'deck' session).
# getty@tty1 autologins 'deck' on the built-in display, which (via PAM/pam_systemd) gives a REAL
# login session: XDG_RUNTIME_DIR=/run/user/1001 + the per-user PipeWire stack (pipewire.socket /
# wireplumber) come up — Steam needs that runtime dir, and PipeWire (audio) ONLY runs for a non-root
# user (ConditionUser=!root), which is why the session user is 'deck', not root. We then exec into
# the gamescope Big-Picture session.
#
# Which session to launch is read from a choice file written by steamos-session-select:
#   $XDG_STATE_HOME/pocknix-session  (i.e. ~/.local/state/pocknix-session)  =  gamescope | plasma
# Missing/unknown => gamescope (game mode stays the default; desktop is opt-in via the switch).
# Steam's "Switch to Desktop" and the Plasma "Return to Game Mode" tile both rewrite this file and
# restart getty@tty1, so the next autologin lands in the chosen session. See docs/plasma-mobile-plan.md.
#
# Guards: only the physical console (tty1), and NOT over SSH ($SSH_CONNECTION set) or other VTs.
# Escape hatch: `touch ~/.no-steam` to get a shell on tty1 instead (for debugging either session).
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${SSH_CONNECTION:-}" ] && [ ! -e "${HOME}/.no-steam" ]; then
  POCKNIX_SESSION="$(cat "${XDG_STATE_HOME:-${HOME}/.local/state}/pocknix-session" 2>/dev/null || echo gamescope)"
  case "${POCKNIX_SESSION}" in
    plasma|desktop) command -v pocknix-desktop >/dev/null 2>&1 && exec pocknix-desktop ;;
  esac
  command -v pocknix-steam >/dev/null 2>&1 && exec pocknix-steam
fi
