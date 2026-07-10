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

export function availableGames(config: Config): GameRef[] {
  const games = new Map<string, GameRef>();
  for (const game of config.installedGames || []) {
    if (game?.appid && isGame(String(game.appid), game.name || "")) {
      games.set(String(game.appid), { appid: String(game.appid), name: game.name || `App ${game.appid}` });
    }
  }
  // Games with saved tweaks stay listed even if the type lookup would hide them —
  // existing per-game config must remain reachable.
  for (const [appid, game] of Object.entries(config.tweaks?.games || {})) {
    if (game && typeof game === "object") games.set(String(appid), { appid: String(appid), name: game.name || games.get(String(appid))?.name || `App ${appid}` });
  }
  return Array.from(games.values()).sort((a, b) => gameDisplayName(a).localeCompare(gameDisplayName(b)));
}

export function editTargetOptions(config: Config): DropdownChoice[] {
  return [
    { data: "", label: "Default" },
    ...availableGames(config).map((game) => ({ data: game.appid, label: gameDisplayName(game) })),
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
