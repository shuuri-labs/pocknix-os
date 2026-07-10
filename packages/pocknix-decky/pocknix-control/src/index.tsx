import { definePlugin } from "@decky/api";
import { Content } from "./Content";

export default definePlugin(() => ({
  name: "Pocknix Control",
  content: <Content />,
  icon: <div style={{ fontWeight: 700 }}>P</div>,
  alwaysRender: true,
}));
