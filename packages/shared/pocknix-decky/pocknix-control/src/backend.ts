import { call } from "@decky/api";
import type { Config, ConfigExportResult, ConfigImportResult, ConfigPreview, LedConfig, LedSideKey, SdcardInfo, SnapshotStatus, Tweaks, UpdateInfo, UpdateStatus } from "./types";

export const getConfig = () => call<[], Config>("get_config");
export const setFanMode = (mode: string) => call<[string], Config>("set_fan_mode", mode);
export const setLavdMode = (mode: string) => call<[string], Config>("set_lavd_mode", mode);
export const saveTweaks = (data: Tweaks) => call<[Tweaks], Config>("save_tweaks", data);
export const exportConfig = (appid: string, name: string, basename: string, allowOverwrite: boolean) =>
  call<[string, string, string, boolean], ConfigExportResult>("export_config", appid, name, basename, allowOverwrite);
export const configDir = () => call<[], string>("config_dir");
export const readConfig = (path: string) => call<[string], ConfigPreview>("read_config", path);
export const applyConfig = (path: string, sourceAppid: string, targetAppid: string, targetName: string) =>
  call<[string, string, string, string], ConfigImportResult>("apply_config", path, sourceAppid, targetAppid, targetName);
export const setLed = (side: LedSideKey, r: number, g: number, b: number, brightness: number) =>
  call<[LedSideKey, number, number, number, number], LedConfig>("set_led", side, r, g, b, brightness);
export const setLedLinked = (linked: boolean) => call<[boolean], LedConfig>("set_led_linked", linked);
export const setLedEnabled = (enabled: boolean) => call<[boolean], LedConfig>("set_led_enabled", enabled);
export const setLedSides = (sides: boolean) => call<[boolean], LedConfig>("set_led_sides", sides);
export const detectSdcard = () => call<[], SdcardInfo>("detect_sdcard");
export const formatSdcard = (label: string) => call<[string], SdcardInfo>("format_sdcard", label);
export const checkUpdates = () => call<[], UpdateInfo[]>("check_updates");
export const startUpdate = () => call<[], UpdateStatus>("start_update");
export const updateStatus = () => call<[], UpdateStatus>("update_status");
export const snapshotStatus = () => call<[], SnapshotStatus>("snapshot_status");
export const startRollback = (id: string) => call<[string], SnapshotStatus>("start_rollback", id);
export const rebootSystem = () => call<[], boolean>("reboot_system");
