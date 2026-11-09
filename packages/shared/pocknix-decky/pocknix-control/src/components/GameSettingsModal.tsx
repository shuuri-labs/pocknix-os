import { ModalRoot } from "@decky/ui";
import { useEffect, useState } from "react";
import { getConfig } from "../backend";
import { usePatchTweaks } from "../hooks/usePatchTweaks";
import type { Config } from "../types";
import { currentGame } from "../lib/games";
import { GameOnlyToggle, TweakFields, resetFields } from "./GameFields";

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
      <GameOnlyToggle checked={enabled} onChange={(on) => patchGame(appid, { enabled: on, name })} />
      {enabled ? (
        <TweakFields
          config={config}
          appid={appid}
          name={name || `App ${appid}`}
          values={values}
          patch={patch}
          live={currentGame()?.appid === appid}
          onReset={() => patchGame(appid, resetFields(config, appid))}
        />
      ) : null}
    </ModalRoot>
  );
}
