# One answer to "which binary is <emulator>" for the wrappers, pocknix-play and the seeder:
# a build dropped into ~/Emulation/emulators/<name>/ wins over the packaged one.
EMU_DROP="${HOME}/Emulation/emulators"
# Steam starts games with no PATH at all. bash falls back to its built-in search, but an AppImage
# runtime then finds neither fusermount3 nor bash and exits (RPCS3's does).
export PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
EMU_NAMES="armsx2 eden ryujinx rpcs3 vita3k xemu dolphin cemu azahar ppsspp"

# Heavy emulators pin to the board's game cores: scx_lavd otherwise parks the critical thread
# on a little core (chop + audio crackle). Unlike the game pin, a board without the key still
# pins, to the cores cores.sh guesses from capacity.
. /usr/lib/pocknix/cores.sh
big_cores() { pocknix_big_cores guess; }

emu_path_names() {  # $1 name -> the binary names a normal install would put on PATH
  case "$1" in
    ryujinx) echo "Ryujinx Ryujinx.Ava ryujinx" ;;
    eden)    echo "eden Eden" ;;
    armsx2)  echo "armsx2 ARMSX2" ;;
    rpcs3)   echo "rpcs3" ;;
    vita3k)  echo "Vita3K vita3k" ;;
    xemu)    echo "xemu" ;;
    *)       echo "" ;;
  esac
}

emu_path() {  # $1 name -> prints the executable, or returns 1
  local d="${EMU_DROP}/$1" f n=0 pick=""
  if [ -d "${d}" ]; then
    for f in "${d}"/*; do [ -f "${f}" ] || continue; n=$((n + 1)); pick="${f}"; done
    if [ "${n}" -eq 1 ]; then
      # browser downloads arrive without the x bit; the file is the user's own
      [ -x "${pick}" ] || chmod u+x "${pick}" 2>/dev/null
      printf '%s\n' "${pick}"; return 0
    fi
    [ "${n}" -gt 1 ] && echo "pocknix: ${d} holds ${n} files, expected exactly one; using the packaged build" >&2
  fi
  case "$1" in
    armsx2)  f=/opt/pocknix/emulators/armsx2/ARMSX2.AppImage ;;
    eden)    f=/opt/pocknix/emulators/eden/Eden.AppImage ;;   # pre-retirement installs only
    rpcs3)   f=/opt/pocknix/emulators/rpcs3/rpcs3.AppImage ;;
    vita3k)  f=/opt/pocknix/emulators/vita3k/Vita3K.AppImage ;;
    xemu)    f=/opt/pocknix/emulators/xemu/xemu.AppImage ;;
    dolphin) f="$(command -v dolphin-emu 2>/dev/null)" ;;
    cemu)    f="$(command -v Cemu 2>/dev/null)" ;;
    azahar)  f="$(command -v azahar 2>/dev/null)" ;;
    ppsspp)  f="$(command -v PPSSPPSDL 2>/dev/null || command -v ppsspp 2>/dev/null)" ;;
    *)       f="" ;;
  esac
  [ -n "${f}" ] && [ -x "${f}" ] && { printf '%s\n' "${f}"; return 0; }
  # Our staticpath rule shadows ES-DE's own systempath lookup, so a build the user installed
  # normally (Ryujinx from the AUR, say) is only found if we look too.
  for f in $(emu_path_names "$1"); do
    f="$(command -v "${f}" 2>/dev/null)" && [ -x "${f}" ] && { printf '%s\n' "${f}"; return 0; }
  done
  return 1
}

emu_missing() {  # $1 name: the user-facing "not installed" exit
  echo "pocknix: $1 is not installed. Drop its AppImage into ${EMU_DROP}/$1/ (see ~/Emulation/README.txt)." >&2
  exit 1
}
