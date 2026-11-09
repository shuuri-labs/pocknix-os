import { definePlugin } from "@decky/api";
import { Content } from "./Content";
import { getConfig } from "./backend";
import { installedSteamGames, isGame, nonSteamShortcuts, plainTileShortcuts } from "./lib/games";
import { registerDownloadWrapper, unwrapPlainTiles, wrapAllGames, wrapShortcuts } from "./lib/launchOptions";
import { patchLibraryContextMenu } from "./lib/contextMenu";
import { registerTouchLifetime } from "./lib/touch";

export default definePlugin(() => {
  const unpatchContextMenu = patchLibraryContextMenu();
  const unregisterTouch = registerTouchLifetime();
  const unregisterDownloads = registerDownloadWrapper((appid) => isGame(appid));
  getConfig()
    .then(async (config) => {
      await wrapAllGames(installedSteamGames(config));
      await wrapShortcuts(nonSteamShortcuts().map((shortcut) => shortcut.appid));
      await unwrapPlainTiles(config.plainTiles || [], plainTileShortcuts());
    })
    .catch(() => {});
  return {
    name: "Pocknix Control",
    content: <Content />,
    icon: <div style={{ fontWeight: 700 }}>P</div>,
    alwaysRender: true,
    onDismount() {
      unpatchContextMenu();
      unregisterTouch();
      unregisterDownloads();
    },
  };
});
