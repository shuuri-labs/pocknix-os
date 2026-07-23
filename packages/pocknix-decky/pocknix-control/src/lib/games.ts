import { Router } from "@decky/ui";
import type { Config, DropdownChoice, GameRef } from "../types";

export function gameDisplayName(game: GameRef | null | undefined): string {
  if (!game?.appid) return "";
  return game.name || `App ${game.appid}`;
}

// The backend lists every appmanifest in steamapps, which includes tools (Proton, Steam Linux
// Runtime, Steamworks Common Redistributables, …). Steam's own appStore overview knows the type
// (app_type 1 = game, 4 = tool); fall back to name patterns when the overview isn't available.
const NON_GAME_NAME = /^(Proton[ 0-9]|Proton (Hotfix|EasyAntiCheat|BattlEye)|Steam Linux Runtime|Steamworks Common)/i;

function isGame(appid: string, name: string): boolean {
  try {
    const overview: any = window.appStore?.GetAppOverviewByAppID?.(Number(appid));
    if (typeof overview?.app_type === "number") return overview.app_type !== 4;
  } catch (error) {
  }
  return !NON_GAME_NAME.test(name);
}

// Non-Steam shortcuts have no appmanifest, so the backend scan can't see them; Steam's
// deckDesktopApps collection holds their appids (unsigned; force with >>> in case a build
// hands out the signed-int32 form) and appStore resolves the names.
export function nonSteamShortcuts(): GameRef[] {
  try {
    const ids = window.collectionStore?.deckDesktopApps?.apps;
    if (!ids?.values) return [];
    const shortcuts: GameRef[] = [];
    for (const id of Array.from(ids.values() as Iterable<any>)) {
      const appid = String(Number(id) >>> 0);
      if (!appid || appid === "0") continue;
      let name = "";
      try {
        name = window.appStore?.GetAppOverviewByAppID?.(Number(appid))?.display_name || "";
      } catch (error) {
      }
      shortcuts.push({ appid, name: name || `App ${appid}`, nonSteam: true });
    }
    return shortcuts;
  } catch (error) {
    return [];
  }
}

export function availableGames(config: Config): GameRef[] {
  const games = new Map<string, GameRef>();
  for (const game of config.installedGames || []) {
    if (game?.appid && isGame(String(game.appid), game.name || "")) {
      games.set(String(game.appid), { appid: String(game.appid), name: game.name || `App ${game.appid}` });
    }
  }
  for (const shortcut of nonSteamShortcuts()) {
    games.set(shortcut.appid, shortcut);
  }
  // Games with saved tweaks stay listed even if the lookups above miss them —
  // existing per-game config must remain reachable. Shortcut appids sit above 2^31.
  for (const [appid, game] of Object.entries(config.tweaks?.games || {})) {
    if (game && typeof game === "object" && !games.has(String(appid))) {
      games.set(String(appid), { appid: String(appid), name: game.name || `App ${appid}`, nonSteam: Number(appid) >= 0x80000000 });
    }
  }
  return Array.from(games.values()).sort(
    (a, b) => (a.nonSteam ? 1 : 0) - (b.nonSteam ? 1 : 0) || gameDisplayName(a).localeCompare(gameDisplayName(b))
  );
}

export function editTargetOptions(config: Config): DropdownChoice[] {
  return [
    { data: "", label: "Default" },
    ...availableGames(config).map((game) => ({
      data: game.appid,
      label: game.nonSteam ? `${gameDisplayName(game)} · non-Steam` : gameDisplayName(game),
    })),
  ];
}

export function currentGame(): GameRef | null {
  const running = (Router as any)?.MainRunningApp || window.Router?.MainRunningApp;
  const appid = running?.appid;
  if (!appid) return null;
  const id = String(appid);
  let name = running?.display_name || running?.displayName || "";
  try {
    const details: any = window.appDetailsStore?.GetAppDetails?.(Number(id));
    name = details?.strDisplayName || details?.strName || details?.name || name;
  } catch (error) {
  }
  return { appid: id, name: name || `App ${id}` };
}
