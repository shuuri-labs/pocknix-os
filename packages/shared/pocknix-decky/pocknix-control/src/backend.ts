import { call } from "@decky/api";
import type { CalibrationStatus, Config, ConfigExportResult, ConfigImportResult, ConfigPreview, LedConfig, LedSideKey, ShareStatus, SnapshotStatus, Tweaks, UpdateInfo, UpdateStatus } from "./types";

export const getConfig = () => call<[], Config>("get_config");
export const setFanMode = (mode: string) => call<[string], Config>("set_fan_mode", mode);
export const setLavdMode = (mode: string) => call<[string], Config>("set_lavd_mode", mode);
export const gameLifetime = (appid: string, running: boolean) => call<[string, boolean], void>("game_lifetime", appid, running);
export const patchTweaks = (appid: string, fields: Record<string, any>) =>
  call<[string, Record<string, any>], Tweaks>("patch_tweaks", appid, fields);
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
export const shareStatus = () => call<[], ShareStatus>("share_status");
export const setShare = (on: boolean) => call<[boolean], ShareStatus>("set_share", on);
export const installSamba = () => call<[], ShareStatus>("install_samba");
export const checkUpdates = () => call<[], UpdateInfo[]>("check_updates");
export const startUpdate = () => call<[], UpdateStatus>("start_update");
export const updateStatus = () => call<[], UpdateStatus>("update_status");
export const snapshotStatus = () => call<[], SnapshotStatus>("snapshot_status");
export const startRollback = (id: string) => call<[string], SnapshotStatus>("start_rollback", id);
export const rebootSystem = () => call<[], boolean>("reboot_system");
export const calibrationStatus = () => call<[], CalibrationStatus>("calibration_status");
export const calibrationStart = () => call<[], CalibrationStatus>("calibration_start");
export const calibrationCancel = () => call<[], CalibrationStatus>("calibration_cancel");
export const calibrationSave = () => call<[], CalibrationStatus>("calibration_save");
export const calibrationReset = () => call<[], CalibrationStatus>("calibration_reset");
