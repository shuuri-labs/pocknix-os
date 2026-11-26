# hexagonrpc patches

What this package carries and why, one entry per patch. How each patch works is in its header.

## Base

upstream `da7a3742` (0.5.0, 2026)

Last rebased: 2026-11 (initial).

## Carried

- **0001** ADSP sensor_pd fails initialization when `/persist/sensors/sensors_list.txt` and
  `/persist/sensors/registry/sns_reg_version` are hidden below `/persist/sensors/registry/registry`.
  Applies: `hexagonrpcd/rpcd_builder.c`. Drop: if upstream exposes `/persist/sensors` directly.

## Not taken

None.

## Retired numbers

None.
