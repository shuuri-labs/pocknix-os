import { call } from "@decky/api";
import type { Config, SdcardInfo, Tweaks } from "./types";

export const getConfig = () => call<[], Config>("get_config");
export const setFanMode = (mode: string) => call<[string], Config>("set_fan_mode", mode);
export const setLavdMode = (mode: string) => call<[string], Config>("set_lavd_mode", mode);
export const saveTweaks = (data: Tweaks) => call<[Tweaks], Config>("save_tweaks", data);
export const detectSdcard = () => call<[], SdcardInfo>("detect_sdcard");
export const formatSdcard = (label: string) => call<[string], SdcardInfo>("format_sdcard", label);
