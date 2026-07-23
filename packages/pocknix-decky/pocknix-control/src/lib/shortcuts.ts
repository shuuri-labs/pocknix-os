// Non-Steam shortcut creation via SteamClient.Apps. The Steam file browser can't open a
// new window under the Plasma Mobile X11 session, so Decky's in-UI file picker plus this
// module replace the stock "Add a Non-Steam Game" flow.

const WINDOWS_EXE = /\.(exe|bat|msi)$/i;

// Constant internal name from proton-cachyos' compatibilitytool.vdf; survives version bumps.
const PROTON_TOOL = "proton-cachyos";

export function isWindowsExe(path: string): boolean {
  return WINDOWS_EXE.test(path);
}

export function defaultShortcutName(path: string): string {
  const base = path.split("/").pop() || path;
  const cleaned = base.replace(/\.[^.]+$/, "").replace(/_+/g, " ").trim();
  return cleaned || base;
}

const quote = (value: string) => `"${value.replace(/"/g, '\\"')}"`;

export async function addShortcut(name: string, path: string, useProton: boolean): Promise<number> {
  const apps = window.SteamClient?.Apps;
  if (!apps?.AddShortcut) throw new Error("Steam shortcut API unavailable");
  const dir = path.slice(0, path.lastIndexOf("/") + 1) || "/";
  const appId = await apps.AddShortcut(name, path, "", "");
  if (typeof appId !== "number" || !appId) throw new Error("Steam refused to create the shortcut");
  apps.SetShortcutName?.(appId, name);
  apps.SetShortcutExe?.(appId, quote(path));
  apps.SetShortcutStartDir?.(appId, quote(dir));
  if (useProton) apps.SpecifyCompatTool?.(appId, PROTON_TOOL);
  return appId;
}
