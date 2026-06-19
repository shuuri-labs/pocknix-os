# pocknix-os — boot-to-Steam hook.
# The getty@tty1 autologin override logs root in on the built-in display, which (via PAM /
# pam_systemd) gives a REAL login session: XDG_RUNTIME_DIR=/run/user/0 + the per-user PipeWire
# stack (pipewire.socket / wireplumber, enabled --global) come up here — Steam needs that runtime
# dir + audio. We then exec into the gamescope Big-Picture session.
#
# Guards: only the physical console (tty1), and NOT over SSH ($SSH_CONNECTION set) or other VTs —
# so `ssh root@device` and Ctrl-Alt-F2 still get a normal dev shell. Escape hatch: to boot to a
# shell on tty1 instead (e.g. for debugging the session), `touch /root/.no-steam`.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${SSH_CONNECTION:-}" ] && [ ! -e /root/.no-steam ] \
   && command -v pocknix-steam >/dev/null 2>&1; then
  exec pocknix-steam
fi
