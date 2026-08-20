import { definePlugin } from "@decky/api";
import { Content } from "./Content";
import { patchLibraryContextMenu } from "./lib/contextMenu";

export default definePlugin(() => {
  const unpatchContextMenu = patchLibraryContextMenu();
  return {
    name: "Pocknix Control",
    content: <Content />,
    icon: <div style={{ fontWeight: 700 }}>P</div>,
    alwaysRender: true,
    onDismount() {
      unpatchContextMenu();
    },
  };
});
