# /usr/lib/pocknix/cores.sh: the one reading of a board's core split, sourced by the game pin
# (pocknix-steam-env, pocknix-game-launch), the emulator pin (emu-resolve.sh), irq placement
# (pocknix-rt-ladder) and Pocknix Control.
# POSIX sh; every function runs in a subshell, so sourcing leaks no variables.

# POCKNIX_BIG_CORES as a comma list ("3-7" -> "3,4,5,6,7"); empty if unset or malformed (a wrong
# pin is worse than none). With "guess", no key = every core above the lowest capacity.
pocknix_big_cores() (
  spec="$(for f in /usr/lib/pocknix/device.conf /etc/pocknix/device.conf; do
    [ -r "${f}" ] && . "${f}"
  done; printf '%s' "${POCKNIX_BIG_CORES:-}")"
  list="$(printf '%s\n' "${spec}" | tr -d ' \t' | awk -F, '
    NF { for (i = 1; i <= NF; i++) {
      if ($i !~ /^[0-9]+(-[0-9]+)?$/) { bad = 1; exit }
      n = split($i, b, "-"); hi = (n == 2) ? b[2] : b[1]
      for (c = b[1] + 0; c <= hi + 0; c++) { l = l s c; s = "," }
    } }
    END { if (!bad) print l }')"
  if [ -z "${list}" ] && [ "${1:-}" = guess ]; then
    list="$(for c in /sys/devices/system/cpu/cpu[0-9]*; do
      echo "${c##*cpu} $(cat "${c}/cpu_capacity" 2>/dev/null)"
    done | sort -k2n | awk 'NR == 1 { min = $2 } { a = a t $1; t = "," }
      $2 != min { l = l s $1; s = "," } END { print (l != "" ? l : a) }')"
  fi
  printf '%s' "${list}"
)

# The big core whose cpu_capacity tops every other big core; empty when none stands out.
pocknix_prime_core() (
  for c in $(pocknix_big_cores | tr , ' '); do
    echo "${c} $(cat "/sys/devices/system/cpu/cpu${c}/cpu_capacity" 2>/dev/null)"
  done | sort -k2nr | awk 'NR == 1 { top = $1; cap = $2 } NR == 2 && $2 == cap { top = "" }
    END { if (cap != "") print top }'
)

# The cores games are not pinned to, which take irq and helper work.
pocknix_small_cores() (
  big="$(pocknix_big_cores guess)"
  for c in /sys/devices/system/cpu/cpu[0-9]*; do echo "${c##*cpu}"; done | sort -n |
    awk -v big="${big}" 'BEGIN { n = split(big, b, ","); for (i = 1; i <= n; i++) p[b[i]] = 1 }
      !($1 in p) { l = l s $1; s = "," } END { print l }'
)

# Comma list -> affinity mask ("3,4,5,6,7" -> "0xf8").
pocknix_cores_mask() (
  printf '%s\n' "$1" | awk -F, 'NF { m = 0; for (i = 1; i <= NF; i++) m += 2 ^ $i; printf "0x%x", m }'
)
