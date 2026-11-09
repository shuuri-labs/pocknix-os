import { useQuickAccessVisible } from "@decky/api";
import { Field, PanelSection, Tabs } from "@decky/ui";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { getConfig } from "./backend";
import { AddGameSection } from "./components/AddGame";
import { usePatchTweaks } from "./hooks/usePatchTweaks";
import { tabIcons } from "./icons";
import { currentGame } from "./lib/games";
import { styles } from "./styles";
import { StickLights } from "./tabs/StickLights";
import { Games } from "./tabs/Games";
import { Updater } from "./tabs/Updater";
import type { Config } from "./types";

export function Content() {
  const [tab, setTab] = useState("Games");
  const [config, setConfig] = useState<Config | null>(null);
  const [message, setMessage] = useState("Loading");
  const patchSeq = useRef(0);
  const load = useCallback(async () => {
    const seq = patchSeq.current;
    try {
      const next = await getConfig();
      next.game = currentGame();
      // get_config is slow (it re-parses the Steam library): a save made meanwhile is newer than its tweaks.
      const tweaks = (current: Config | null) => (current && patchSeq.current !== seq ? current.tweaks : next.tweaks);
      setConfig((current) => ({ ...next, tweaks: tweaks(current), selectedGame: current ? current.selectedGame : next.game || null }));
    } catch (error) {
      setMessage(String(error));
    }
  }, []);
  // alwaysRender keeps this panel mounted while the QAM is closed, so the library modal's
  // saves only show up if every reopen re-reads them.
  const visible = useQuickAccessVisible();
  useEffect(() => {
    if (visible) load();
  }, [visible, load]);
  const patch = usePatchTweaks(setConfig, load, patchSeq);
  // Track the running game so opening the QAM mid-game edits that game's profile.
  useEffect(() => {
    if (!config) return;
    let cancelled = false;
    const refreshRuntime = () => {
      try {
        const runtimeGame = currentGame();
        if (cancelled) return;
        setConfig((current) => {
          if (!current) return current;
          if ((current.game?.appid || "") === (runtimeGame?.appid || "") && (current.game?.name || "") === (runtimeGame?.name || "")) return current;
          return { ...current, game: runtimeGame };
        });
      } catch (error) {
      }
    };
    const timer = window.setInterval(refreshRuntime, 2000);
    refreshRuntime();
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [!!config]);

  if (!config) return <PanelSection title="Pocknix Control"><Field label={message} /></PanelSection>;

  const tabContent = (content: ReactNode) => (
    <div className="pocknix-control-tab-content">{content}</div>
  );
  const tabs = [
    { id: "Games", title: tabIcons.Games, content: tabContent(<Games config={config} setConfig={setConfig} patch={patch} reload={load} />) },
    ...(config.led.available
      ? [{ id: "StickLights", title: tabIcons.StickLights, content: tabContent(<StickLights config={config} setConfig={setConfig} reload={load} />) }]
      : []),
    { id: "AddGame", title: tabIcons.AddGame, content: tabContent(<AddGameSection />) },
    { id: "Updater", title: tabIcons.Updater, content: tabContent(<Updater />) },
  ];
  return (
    <div className="pocknix-control-tabs">
      <style>{styles}</style>
      <Tabs activeTab={tab} onShowTab={setTab} tabs={tabs} />
    </div>
  );
}
