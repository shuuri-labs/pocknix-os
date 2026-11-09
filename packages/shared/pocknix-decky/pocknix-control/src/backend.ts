import { call } from "@decky/api";
import { rememberPlainTiles } from "./lib/games";
import type { Config, LedConfig, LedSideKey, SnapshotStatus, Tweaks, UpdateInfo, UpdateStatus } from "./types";

export const getConfig = () => call<[], Config>("get_config").then(rememberPlainTiles);
export const setFanMode = (mode: string) => call<[string], Config>("set_fan_mode", mode);
export const setLavdMode = (mode: string) => call<[string], Config>("set_lavd_mode", mode);
export const gameLifetime = (appid: string, running: boolean) => call<[string, boolean], void>("game_lifetime", appid, running);
export const patchTweaks = (appid: string, fields: Record<string, any>) =>
  call<[string, Record<string, any>], Tweaks>("patch_tweaks", appid, fields);
export const setLed = (side: LedSideKey, r: number, g: number, b: number, brightness: number) =>
  call<[LedSideKey, number, number, number, number], LedConfig>("set_led", side, r, g, b, brightness);
export const setLedLinked = (linked: boolean) => call<[boolean], LedConfig>("set_led_linked", linked);
export const setLedEnabled = (enabled: boolean) => call<[boolean], LedConfig>("set_led_enabled", enabled);
export const setLedSides = (sides: boolean) => call<[boolean], LedConfig>("set_led_sides", sides);
export const checkUpdates = () => call<[], UpdateInfo[]>("check_updates");
export const startUpdate = () => call<[], UpdateStatus>("start_update");
export const updateStatus = () => call<[], UpdateStatus>("update_status");
export const bootloaderStatus = () => call<[], { needsOpenAbl: boolean }>("bootloader_status");
export const snapshotStatus = () => call<[], SnapshotStatus>("snapshot_status");
export const startRollback = (id: string) => call<[string], SnapshotStatus>("start_rollback", id);
export const rebootSystem = () => call<[], boolean>("reboot_system");
