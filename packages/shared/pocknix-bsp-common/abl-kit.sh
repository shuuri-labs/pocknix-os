# abl-kit.sh - sourced: the OpenABL kit for the running SoC. pocknix-openabl's per-SoC tree wins
# over a pocknix-bootloader-<soc> flat kit. SRCROOT reads another root's kit (the SD image build).
ABL_KIT_NEW="${SRCROOT:-}/usr/share/pocknix/openabl"
ABL_KIT_OLD="${SRCROOT:-}/usr/share/pocknix/bootloader/openabl"
# The SoC-neutral kit files; /flash/openabl gets them flat beside the elf and flash_abl.sh.
ABL_KIT_FILES=(README backup_abl.sh restore_backup_abl.sh version)

# $1 = a SoC instead of the device tree's (the image build only). Returns 1 when no kit matches;
# never guesses: a wrong-chip ABL does not boot and needs EDL to recover.
abl_kit_resolve() {
  ABL_SOC="" ABL_ELF="" ABL_FLASH_SH="" ABL_KIT="" ABL_SOCS_SEEN=""
  local -a socs=()
  local s
  if [ -n "${1:-}" ]; then
    ABL_SOCS_SEEN="${1^^}"
    [[ "${ABL_SOCS_SEEN}" =~ ^SM[0-9]{4}$ ]] || return 1
    socs=("${ABL_SOCS_SEEN}")
  else
    # Exact entries only: boards also list qcom,qcs<n> and qcom,<soc>-mtp.
    mapfile -t socs < <(tr '\0' '\n' 2>/dev/null < /sys/firmware/devicetree/base/compatible \
                        | sed -n 's/^qcom,\(sm[0-9]\{4\}\)$/\1/p' | tr '[:lower:]' '[:upper:]')
    ABL_SOCS_SEEN="${socs[*]}"
  fi
  for s in "${socs[@]}"; do
    if [ -f "${ABL_KIT_NEW}/${s}/abl_signed-${s}.elf" ]; then
      ABL_KIT="${ABL_KIT_NEW}" ABL_ELF="${ABL_KIT_NEW}/${s}/abl_signed-${s}.elf" ABL_FLASH_SH="${ABL_KIT_NEW}/${s}/flash_abl.sh"
    elif [ -f "${ABL_KIT_OLD}/abl_signed-${s}.elf" ]; then
      ABL_KIT="${ABL_KIT_OLD}" ABL_ELF="${ABL_KIT_OLD}/abl_signed-${s}.elf" ABL_FLASH_SH="${ABL_KIT_OLD}/flash_abl.sh"
    else
      continue
    fi
    ABL_SOC="${s}"
    return 0
  done
  return 1
}
