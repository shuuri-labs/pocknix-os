// Drives the same state as Steam's own per-game compatibility dropdown (SpecifyCompatTool +
// app details), so never store a shadow copy: the two UIs stay in sync by construction.
import { findModule, findModuleExport } from "@decky/ui";
import { Component, createElement } from "react";
import type { ReactNode } from "react";
import { ensureLaunchWrapper } from "./launchOptions";

export interface CompatTool {
  name: string;
  label: string;
}

interface SteamCompatTools {
  tools?: Array<{ name?: string; display_name?: string; is_incompatible?: boolean }>;
}
interface SteamCompatQuery {
  status?: string;
  data?: SteamCompatTools | null;
  error?: unknown;
}
type SteamCompatHook = (appid: number) => [SteamCompatQuery, (tool: string) => void];

// Steam's tool list is only reachable via its react-query hook, which throws outside Steam's
// QueryClient; a throwaway root under Steam's provider works from any tree.
const steam = {
  hook: null as SteamCompatHook | null,
  provider: null as any,
  client: null as any,
  createRoot: null as any,
};
function findSteam(): boolean {
  steam.hook ||= findModuleExport((e: any) => typeof e === "function" && e.toString().includes("Failed to fetch available compat tools"));
  steam.provider ||= findModuleExport((e: any) => {
    if (typeof e !== "function") return false;
    const src = e.toString();
    return src.length < 400 && /\.mount\(\)/.test(src) && /unmount\(\)/.test(src) && /children/.test(src);
  });
  steam.client ||= findModuleExport((e: any) => e && typeof e === "object" && typeof e.getQueryCache === "function" && typeof e.invalidateQueries === "function");
  steam.createRoot ||= findModule((m: any) => typeof m?.createRoot === "function")?.createRoot;
  return !!(steam.hook && steam.provider && steam.client && steam.createRoot);
}

class ProbeBoundary extends Component<{ onError: (e: unknown) => void; children?: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch(error: unknown) {
    this.props.onError(error);
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

function steamCompatTools(appid: string): Promise<CompatTool[]> {
  return new Promise((resolve) => {
    let root: any = null;
    const finish = (tools: CompatTool[]) => {
      clearTimeout(timer);
      resolve(tools);
      setTimeout(() => root?.unmount(), 0);
    };
    const timer = setTimeout(() => finish([]), 10000);
    const Probe = () => {
      const [query] = steam.hook!(Number(appid));
      if (query.status === "success") finish(fromSteam(query.data));
      else if (query.status === "error") finish([]);
      return null;
    };
    try {
      root = steam.createRoot(document.createElement("div"));
      root.render(
        createElement(ProbeBoundary, { onError: () => finish([]) },
          createElement(steam.provider, { client: steam.client }, createElement(Probe))),
      );
    } catch {
      finish([]);
    }
  });
}

function fromSteam(data: SteamCompatTools | null | undefined): CompatTool[] {
  return (data?.tools ?? [])
    .filter((tool) => !tool.is_incompatible)
    .map((tool) => ({ name: String(tool.name ?? ""), label: String(tool.display_name || tool.name || "") }))
    .filter((tool) => tool.name);
}

export async function availableCompatTools(appid: string): Promise<CompatTool[]> {
  const apps = window.SteamClient?.Apps;
  try {
    if (apps?.GetAvailableCompatTools) {
      const tools = await apps.GetAvailableCompatTools(Number(appid));
      if (!Array.isArray(tools)) return [];
      return tools
        .map((tool: any) => ({
          name: String(tool?.strToolName ?? ""),
          label: String(tool?.strDisplayName ?? tool?.strToolName ?? ""),
        }))
        .filter((tool) => tool.name);
    }
    return findSteam() ? await steamCompatTools(appid) : [];
  } catch {
    return [];
  }
}

export interface CompatPick {
  /** "" when Steam chooses the tool itself. */
  tool: string;
  /** The tool the game will actually run with, picked or not. */
  label: string;
}

// Steam reports its own choice in the same fields as a user's pick; only the priority tells them
// apart, and a pick made in Properties (or by SpecifyCompatTool) is saved at 250.
const USER_PICK_PRIORITY = 250;

/** Live view of the game's tool; fires again when it changes anywhere (incl. Steam's UI). */
export function registerForCompatTool(appid: string, onChange: (pick: CompatPick) => void): () => void {
  const apps = window.SteamClient?.Apps;
  if (!apps?.RegisterForAppDetails) return () => {};
  const registration = apps.RegisterForAppDetails(Number(appid), (details: any) => {
    const tool = String(details?.strCompatToolName ?? "");
    const label = String(details?.strCompatToolDisplayName || tool);
    onChange({ tool: Number(details?.nCompatToolPriority) >= USER_PICK_PRIORITY ? tool : "", label });
  });
  return () => registration?.unregister?.();
}

export function setCompatTool(appid: string, tool: string): void {
  window.SteamClient?.Apps?.SpecifyCompatTool?.(Number(appid), tool);
  // A shortcut picked up after the load-time sweep still gets the launcher.
  if (tool && Number(appid) >= 0x80000000) ensureLaunchWrapper(appid);
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
