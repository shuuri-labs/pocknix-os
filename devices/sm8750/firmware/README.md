# Firmware overrides — AYN Odin 3 (SM8750)

Blobs here are applied to the image rootfs **after** the ROCKNIX firmware
(`install_firmware()` in `scripts/build-image.sh`), so they win over whatever
the ROCKNIX extra-firmware tree ships. Paths are relative to `/usr/lib/firmware/`.

## `qcom/sm8750/ayn/odin3/adsp.mbn` + `qcom/sm8750/ayn/odin3/adsp_dtb.mbn`

The AYN Odin 3 ADSP **charger** firmware. The device DTS
(`kernel/sm8750/dts/qcom/cq8725s-ayn-odin3.dts`) sets
`firmware-name = "qcom/sm8750/ayn/odin3/adsp.mbn"`, so the kernel loads these
paths.

`adsp_dtb.mbn` carries the **battery-authentication config**
(`batt_auth_cfg`, `batt-auth-public-key`, `batt-unauth-charging-action`,
`en-batt-auth`). The blob Pocknix used to get (from the ROCKNIX overlay / ALARM)
lacks it, so the ADSP charger firmware could not authenticate the battery, fell
into **TEST MODE (state 9)** and the battery never charged under Linux.

These two files are the ones ArmadaOS ships at
`qcom/sm8750/ayn/odin3/` (its DTS uses the board-namespaced path). Copied here
so the current DTS picks them up and they win over the extra-firmware copies.

| file | size | md5 |
|---|---|---|
| `adsp.mbn` | 21907848 | `6cfcbbb80b956ddad76950c038ea1a3e` |
| `adsp_dtb.mbn` | 167736 | `d88d7ecbba78ecacb13adcc7bcbe131d` |

Verified on-device: `battery status=Charging`, `qcom-battmgr-usb online=1`,
`ucsi 3A`, and the charger firmware ulog no longer reports "Test mode".
See `pocknix-odin3-support/BATTERY-ISSUE.md` and
`pocknix-odin3-support/kernel/build-config/FIX-CARGA-BATERIA.md`.

## Full Odin 3 firmware set (ROCKNIX extra-firmware, `SM8750/`)

The image gets the rest of the Odin 3 blobs from **ROCKNIX/extra-firmware**
(branch `master`, pinned commit `30c56e2f34af37fe372166b739d6ab277f5155b5`),
downloaded by `make sync` into `vendor/rocknix-extra-firmware/` (gitignored)
and rsynced into `/usr/lib/firmware/` by `install_firmware()` for `SOC=sm8750`.
Upstream linux-firmware has NONE of these.

| path (under `/usr/lib/firmware/`) | purpose |
|---|---|
| `ath12k/WCN7860/hw2.0/` (amss.bin, board-2.bin, m3.bin, aux_ucode.bin, bdwlan.elf, qdss.cfg, regdb.bin) | WiFi — ath12k WCN7860 hw2.0, the Odin 3's chip (linux-firmware only ships WCN7850) |
| `qcom/sm8750/ayn/odin3/adsp.mbn` + `adsp_dtb.mbn` | ADSP (audio + charger firmware) |
| `qcom/sm8750/ayn/odin3/cdsp.mbn` + `cdsp_dtb.mbn` | CDSP (compute DSP) |
| `qcom/sm8750/ayn/odin3/aw883xx_acf.bin` | AW88261 speaker-amp calibration |
| `qcom/sm8750/SM8750-AYN-tplg.bin` | ASoC DSP topology (without it no sound card is created) |
| `qcom/sm8750/ayn/odin3/*.jsn` (adspr, adsps, adspua, adspuo, cdspr, battmgr) | ADSP/CDSP service configs |

The override blobs above are applied **after** this tree, so the verified
battery-auth ADSP firmware always wins.
