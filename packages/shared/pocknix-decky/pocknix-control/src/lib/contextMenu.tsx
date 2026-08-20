import { MenuItem, afterPatch, fakeRenderComponent, findModuleChild, showModal } from "@decky/ui";
import { GameSettingsModal } from "../components/GameSettingsModal";

// Adds "Pocknix Settings" to the library entry context menu (the Start-button menu).
// The menu class is no longer a module export: locate its module by the
// "().LibraryContextMenu" classname marker, take the wrapper member (the one injecting
// `navigator:` via the jsx runtime), and fake-render it — the element's type is the real
// class. Steam UI internals are unversioned, so every step is guarded: if the shape
// changes we lose the menu item, never the plugin.
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
    // Patch the Manage submenu builder rather than the top-level render, so the entry
    // lands under Manage. The builder's return shape is guarded both ways (plain item
    // array vs element with children).
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
