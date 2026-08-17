// Valve's fex-compat-tool reads STEAM_COMPAT_FEX_CONFIG at the top of the x86 launch chain,
// before our proton shim exists — a game's launch options are the only channel that reaches
// it. ARM Protons ignore the variable (wrapper FEX_APP_CONFIG path).

import type { FexProfile } from "../types";

const FEX_TOKEN = /STEAM_COMPAT_FEX_CONFIG=("[^"]*"|\S*)\s*/g;

/** "" = remove the token: "default"'s string equals Valve's own defaults exactly. */
export function fexSteamString(profileId: string | undefined, profiles: Record<string, FexProfile>): string {
  if (!profileId || profileId === "default") return "";
  return profiles[profileId]?.steam || "";
}

function getLaunchOptions(appid: string): Promise<string | null> {
  return new Promise((resolve) => {
    const apps = window.SteamClient?.Apps;
    if (!apps?.RegisterForAppDetails) return resolve(null);
    let registration: any;
    let timer: number | undefined;
    let done = false;
    const finish = (value: string | null) => {
      if (done) return;
      done = true;
      if (timer !== undefined) window.clearTimeout(timer);
      // Steam may call back before RegisterForAppDetails returns; unregister on a microtask.
      Promise.resolve().then(() => registration?.unregister?.());
      resolve(value);
    };
    timer = window.setTimeout(() => finish(null), 3000);
    try {
      registration = apps.RegisterForAppDetails(Number(appid), (details: any) => {
        finish(String(details?.strLaunchOptions ?? ""));
      });
    } catch (error) {
      finish(null);
    }
  });
}

/** Rewrites only our token, preserving the user's options; bails rather than clobber
 *  when the current value can't be read. */
export async function syncFexLaunchOption(appid: string, steam: string): Promise<void> {
  const apps = window.SteamClient?.Apps;
  if (!apps?.SetAppLaunchOptions) return;
  const current = await getLaunchOptions(appid);
  if (current === null) return;
  const stripped = current.replace(FEX_TOKEN, "").trim();
  let next: string;
  if (steam) {
    const rest = stripped.includes("%command%") ? stripped : ["%command%", stripped].filter(Boolean).join(" ");
    next = `STEAM_COMPAT_FEX_CONFIG=${steam} ${rest}`;
  } else {
    next = stripped === "%command%" ? "" : stripped;
  }
  if (next !== current.trim()) apps.SetAppLaunchOptions(Number(appid), next);
}
