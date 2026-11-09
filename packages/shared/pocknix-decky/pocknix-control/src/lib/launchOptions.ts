// Every Steam game and every non-Steam shortcut (emulator tiles, ROM managers, a Windows .exe on
// Proton) launches through pocknix-game-launch, which applies the per-game tweaks at launch
// time, so a settings change never has to touch launch options. Pocknix's own settings apps
// (launch=plain tiles) are the exception: they never take game tweaks.

import type { GameRef, PlainTile } from "../types";

// Bare name: Steam runs launch options through a shell with the system PATH (/usr/bin).
const LAUNCHER = "pocknix-game-launch";
const COMMAND = "%command%";
// Written by Pocknix Control before the launcher existed; the launcher exports it itself now.
const FEX_TOKEN = /STEAM_COMPAT_FEX_CONFIG=("[^"]*"|\S*)\s*/g;

interface ShortcutDetails {
  exe: string;
  launchOptions: string;
}

function getDetails(appid: string): Promise<ShortcutDetails | null> {
  return new Promise((resolve) => {
    const apps = window.SteamClient?.Apps;
    if (!apps?.RegisterForAppDetails) return resolve(null);
    let registration: any;
    let timer: number | undefined;
    let done = false;
    const finish = (value: ShortcutDetails | null) => {
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
        finish({ exe: String(details?.strShortcutExe ?? "").replace(/^"|"$/g, ""), launchOptions: String(details?.strLaunchOptions ?? "") });
      });
    } catch (error) {
      finish(null);
    }
  });
}

/** null = already wrapped. Keeps the user's own options around %command%. */
export function wrapLaunchOptions(current: string): string | null {
  const stripped = current.replace(FEX_TOKEN, "").trim();
  if (stripped.includes(LAUNCHER)) return stripped === current.trim() ? null : stripped;
  if (stripped.includes(COMMAND)) return stripped.replace(COMMAND, `${LAUNCHER} ${COMMAND}`);
  // Without %command% Steam appends bare options as arguments, so they stay after it.
  return [`${LAUNCHER} ${COMMAND}`, stripped].filter(Boolean).join(" ");
}

/** Bails rather than clobber when the current value can't be read. */
export async function ensureLaunchWrapper(appid: string): Promise<boolean> {
  const apps = window.SteamClient?.Apps;
  if (!apps?.SetAppLaunchOptions) return false;
  const details = await getDetails(appid);
  if (details === null) return false;
  const next = wrapLaunchOptions(details.launchOptions);
  if (next !== null) apps.SetAppLaunchOptions(Number(appid), next);
  return true;
}

export async function wrapShortcuts(appids: string[]): Promise<void> {
  for (const appid of appids) await ensureLaunchWrapper(appid);
}

/** pocknix-tiles finds a tile by exe + launch options, so an older sweep's wrapper hid it. Only an
 *  exact wrapper + manifest args match is undone; anything else on the tile is the user's. */
export async function unwrapPlainTiles(tiles: PlainTile[], shortcuts: GameRef[]): Promise<void> {
  const apps = window.SteamClient?.Apps;
  if (!apps?.SetAppLaunchOptions) return;
  for (const shortcut of shortcuts) {
    const details = await getDetails(shortcut.appid);
    if (!details) continue;
    const tile = tiles.find((t) => t.name === shortcut.name && t.exe === details.exe);
    if (tile && details.launchOptions.trim() === `${LAUNCHER} ${COMMAND} ${tile.args}`.trim()) {
      apps.SetAppLaunchOptions(Number(shortcut.appid), tile.args);
    }
  }
}

export async function wrapAllGames(appids: string[]): Promise<void> {
  let next = 0;
  const worker = async () => {
    while (next < appids.length) await ensureLaunchWrapper(appids[next++]);
  };
  await Promise.all(Array.from({ length: Math.min(8, appids.length) }, worker));
}

/** New installs get wrapped once their download queues; returns the unregister. */
export function registerDownloadWrapper(isGame: (appid: string) => boolean): () => void {
  const downloads = window.SteamClient?.Downloads;
  if (!downloads?.RegisterForDownloadItems) return () => {};
  const pending = new Set<string>();
  let timer: number | undefined;
  const flush = () => {
    timer = undefined;
    const ids = Array.from(pending);
    pending.clear();
    wrapAllGames(ids.filter(isGame));
  };
  // Each queue item is { item_data: [{ appid, ... }] }: the appids live in item_data.
  const handle = downloads.RegisterForDownloadItems((_paused: boolean, items: any[]) => {
    if (!Array.isArray(items)) return;
    for (const item of items) {
      for (const entry of Object.values(item?.item_data || {}) as any[]) {
        const appid = String(entry?.appid ?? "");
        if (appid && appid !== "0") pending.add(appid);
      }
    }
    if (timer === undefined) timer = window.setTimeout(flush, 1500);
  });
  return () => {
    if (timer !== undefined) window.clearTimeout(timer);
    try {
      handle?.unregister?.();
    } catch (error) {
    }
  };
}
