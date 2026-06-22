# pocknix-os — boot-to-Steam hook (non-root 'deck' session).
# getty@tty1 autologins 'deck' on the built-in display, which (via PAM/pam_systemd) gives a REAL
# login session: XDG_RUNTIME_DIR=/run/user/1001 + the per-user PipeWire stack (pipewire.socket /
# wireplumber) come up — Steam needs that runtime dir, and PipeWire (audio) ONLY runs for a non-root
# user (ConditionUser=!root), which is why the session user is 'deck', not root. We then exec into
# the gamescope Big-Picture session.
#
# Guards: only the physical console (tty1), and NOT over SSH ($SSH_CONNECTION set) or other VTs.
# Escape hatch: `touch ~/.no-steam` to get a shell on tty1 instead (for debugging the session).
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${SSH_CONNECTION:-}" ] && [ ! -e "${HOME}/.no-steam" ] \
   && command -v pocknix-steam >/dev/null 2>&1; then
  exec pocknix-steam
fi
