import { gameLifetime } from "../backend";
import { currentGame, isPlainTile } from "./games";

// Reports every Steam game start/stop to the backend, which owns the touchscreen tweak (touch.py).
// Shortcut appids are unsigned above 2^31, hence the >>> 0.
export function registerTouchLifetime(): () => void {
  const report = (appid: string, running: boolean) => gameLifetime(appid, running).catch(() => {});
  // A plugin reload mid-game misses the start notification.
  const running = currentGame();
  if (running) report(running.appid, true);
  try {
    const handle = window.SteamClient?.GameSessions?.RegisterForAppLifetimeNotifications?.((update: any) => {
      const appid = String(Number(update?.unAppID) >>> 0);
      // Default's Disable Touchscreen must not lock the touch UI of Pocknix Tools or the Store.
      if (!isPlainTile(appid)) report(appid, !!update?.bRunning);
    });
    return () => handle?.unregister?.();
  } catch (error) {
    return () => {};
  }
}
