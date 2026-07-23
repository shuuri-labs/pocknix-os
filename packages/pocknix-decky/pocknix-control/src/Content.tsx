import { Field, PanelSection, Tabs } from "@decky/ui";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { getConfig, saveTweaks } from "./backend";
import { useDebouncedSave } from "./hooks/useDebouncedSave";
import { tabIcons } from "./icons";
import { currentGame } from "./lib/games";
import { styles } from "./styles";
import { Games } from "./tabs/Games";
import { Power } from "./tabs/Power";
import { Storage } from "./tabs/Storage";
import { Updater } from "./tabs/Updater";
import type { Config } from "./types";

export function Content() {
  const [tab, setTab] = useState("Games");
  const [config, setConfig] = useState<Config | null>(null);
  const [message, setMessage] = useState("Loading");
  const savedTweaksSnapshot = useRef("");
  const load = useCallback(async () => {
    try {
      const next = await getConfig();
      next.game = currentGame();
      next.selectedGame = next.game || null;
      savedTweaksSnapshot.current = JSON.stringify(next.tweaks);
      setConfig(next);
    } catch (error) {
      setMessage(String(error));
    }
  }, []);
  useEffect(() => {
    load();
  }, [load]);
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
  useDebouncedSave({ config, field: "tweaks", snapshot: savedTweaksSnapshot, save: saveTweaks, setConfig, onError: load });

  if (!config) return <PanelSection title="Pocknix Control"><Field label={message} /></PanelSection>;

  const tabContent = (content: ReactNode) => (
    <div className="pocknix-control-tab-content">{content}</div>
  );
  return (
    <div className="pocknix-control-tabs">
      <style>{styles}</style>
      <Tabs
        activeTab={tab}
        onShowTab={setTab}
        tabs={[
          { id: "Games", title: tabIcons.Games, content: tabContent(<Games config={config} setConfig={setConfig} />) },
          { id: "Power", title: tabIcons.Power, content: tabContent(<Power config={config} setConfig={setConfig} reload={load} />) },
          { id: "Storage", title: tabIcons.Storage, content: tabContent(<Storage />) },
          { id: "Updater", title: tabIcons.Updater, content: tabContent(<Updater />) },
        ]}
      />
    </div>
  );
}
