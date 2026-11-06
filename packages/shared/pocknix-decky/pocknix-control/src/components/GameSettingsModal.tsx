import { ModalRoot, ToggleField } from "@decky/ui";
import { useEffect, useState } from "react";
import { getConfig } from "../backend";
import { usePatchTweaks } from "../hooks/usePatchTweaks";
import type { Config } from "../types";
import { ConfigSection } from "./ConfigSection";
import { PerfFields, TweakFields } from "./GameFields";

/** Standalone per-game settings, opened from the library context menu. */
export function GameSettingsModal({ appid, name, closeModal }: { appid: string; name: string; closeModal?: () => void }) {
  const [config, setConfig] = useState<Config | null>(null);
  const reload = () => getConfig().then(setConfig).catch(() => {});
  const patchGame = usePatchTweaks(setConfig, reload);
  useEffect(() => {
    getConfig()
      .then(setConfig)
      .catch(() => closeModal?.());
  }, []);
  if (!config) return <ModalRoot closeModal={closeModal}>Loading…</ModalRoot>;

  const gameSettings = config.tweaks.games[appid] || {};
  const enabled = gameSettings.enabled === true;
  const values = enabled ? { ...config.tweaks.global, ...gameSettings } : config.tweaks.global;
  const patch = (fields: Record<string, any>) => patchGame(appid, { ...fields, enabled: true, name });

  return (
    <ModalRoot closeModal={closeModal}>
      <div style={{ fontWeight: 600, marginBottom: "8px" }}>{name || `App ${appid}`}</div>
      <ToggleField
        label="Use Per-Game Settings"
        checked={enabled}
        onChange={(on) => patchGame(appid, { enabled: on, name })}
      />
      {enabled ? (
        <>
          <PerfFields values={values} patch={patch} />
          <TweakFields config={config} appid={appid} values={values} patch={patch} />
          <ConfigSection game={{ appid, name }} reload={reload} />
        </>
      ) : null}
    </ModalRoot>
  );
}
