import { MenuItem, afterPatch, fakeRenderComponent, findModuleChild, showModal } from "@decky/ui";
import { GameSettingsModal } from "../components/GameSettingsModal";

// LibraryContextMenu is not a module export, so it is reached by classname marker ->
// `navigator:` wrapper -> fake-render, whose element type is the real class.
// Steam UI internals are unversioned: every step is guarded so a shape change costs the
// menu item, never the plugin.
export function patchLibraryContextMenu(): () => void {
  try {
    const menuModule = findModuleChild((mod: any) => {
      if (typeof mod !== "object" || !mod) return undefined;
      for (const prop in mod) {
        try {
          if (mod[prop]?.toString?.()?.includes("().LibraryContextMenu")) return mod;
        } catch (error) {}
      }
      return undefined;
    });
    if (!menuModule) return () => {};
    const wrapper = Object.values(menuModule).find((member: any) => {
      try {
        return typeof member === "function" && member?.toString?.()?.includes("navigator:");
      } catch (error) {
        return false;
      }
    });
    if (!wrapper) return () => {};
    const LibraryContextMenu = fakeRenderComponent(wrapper as any)?.type;
    if (!LibraryContextMenu?.prototype?.BuildManageSubmenu) return () => {};
    // The builder returns either a plain item array or an element with children.
    const patch = afterPatch(LibraryContextMenu.prototype, "BuildManageSubmenu", function (this: any, _args: any[], ret: any) {
      try {
        const overview = this.props?.overview;
        const appid = overview?.appid;
        if (!appid) return ret;
        const children = Array.isArray(ret) ? ret : ret?.props?.children;
        if (!Array.isArray(children)) return ret;
        if (children.some((child: any) => child?.key === "pocknix-settings")) return ret;
        children.push(
          <MenuItem
            key="pocknix-settings"
            onSelected={() =>
              showModal(<GameSettingsModal appid={String(appid)} name={String(overview?.display_name ?? "")} />)
            }
          >
            Pocknix Settings
          </MenuItem>,
        );
      } catch (error) {}
      return ret;
    });
    return () => patch.unpatch();
  } catch (error) {
    return () => {};
  }
}
