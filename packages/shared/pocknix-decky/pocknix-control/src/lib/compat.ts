// Drives the same state as Steam's own per-game compatibility dropdown (SpecifyCompatTool +
// app details), so never store a shadow copy: the two UIs stay in sync by construction.

export interface CompatTool {
  name: string;
  label: string;
}

export async function availableCompatTools(appid: string): Promise<CompatTool[]> {
  const apps = window.SteamClient?.Apps;
  if (!apps?.GetAvailableCompatTools) return [];
  try {
    const tools = await apps.GetAvailableCompatTools(Number(appid));
    if (!Array.isArray(tools)) return [];
    return tools
      .map((tool: any) => ({
        name: String(tool?.strToolName ?? ""),
        label: String(tool?.strDisplayName ?? tool?.strToolName ?? ""),
      }))
      .filter((tool) => tool.name);
  } catch {
    return [];
  }
}

/** Live view of the game's current tool; fires again when it changes anywhere (incl. Steam's UI). */
export function registerForCompatTool(appid: string, onChange: (tool: string) => void): () => void {
  const apps = window.SteamClient?.Apps;
  if (!apps?.RegisterForAppDetails) return () => {};
  const registration = apps.RegisterForAppDetails(Number(appid), (details: any) => {
    onChange(String(details?.strCompatToolName ?? ""));
  });
  return () => registration?.unregister?.();
}

export function setCompatTool(appid: string, tool: string): void {
  window.SteamClient?.Apps?.SpecifyCompatTool?.(Number(appid), tool);
}

/** Resolve an imported Proton pick against this device's tools. Unknown ARM-named tools
 *  fall back to the cachy ARM Proton; unknown x86-named ones to a Proton 11. */
export function resolveCompatTool(wanted: string, tools: CompatTool[]): { tool: string; fallback: boolean } {
  if (!wanted) return { tool: "", fallback: false };
  if (tools.some((tool) => tool.name === wanted)) return { tool: wanted, fallback: false };
  const haystack = (tool: CompatTool) => `${tool.name} ${tool.label}`;
  const isArm = /arm/i.test(wanted);
  const fallback = isArm
    ? tools.find((tool) => /cachy/i.test(haystack(tool)) && !/x86/i.test(haystack(tool)))
    : tools.find((tool) => /(^|\D)11(\D|$)/.test(haystack(tool)) && !/arm|cachy/i.test(haystack(tool)));
  return { tool: fallback?.name || "", fallback: true };
}
