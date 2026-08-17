import { ModalRoot, ToggleField } from "@decky/ui";
import { useEffect, useState } from "react";
import { getConfig, saveTweaks } from "../backend";
import { fexSteamString, syncFexLaunchOption } from "../lib/launchOptions";
import { clone } from "../lib/util";
import type { Config } from "../types";
import { ConfigSection } from "./ConfigSection";
import { PerfFields, TweakFields } from "./GameFields";

/** Standalone per-game settings, opened from the library context menu. Saves on each change
 *  (no QAM debounce lifecycle here; the modal has an explicit close). */
export function GameSettingsModal({ appid, name, closeModal }: { appid: string; name: string; closeModal?: () => void }) {
  const [config, setConfig] = useState<Config | null>(null);
  useEffect(() => {
    getConfig()
      .then(setConfig)
      .catch(() => closeModal?.());
  }, []);
  if (!config) return <ModalRoot closeModal={closeModal}>Loading…</ModalRoot>;

  const gameSettings = config.tweaks.games[appid] || {};
  const enabled = gameSettings.enabled === true;
  const values = enabled ? { ...config.tweaks.global, ...gameSettings } : config.tweaks.global;
  const update = (mutate: (next: Config) => void) => {
    const next = clone(config);
    mutate(next);
    setConfig(next);
    saveTweaks(next.tweaks).catch(() => {});
  };
  const patch = (fields: Record<string, any>) =>
    update((next) => {
      const existing = next.tweaks.games[appid] || {};
      next.tweaks.games[appid] = { ...existing, enabled: true, name, ...fields };
    });

  return (
    <ModalRoot closeModal={closeModal}>
      <div style={{ fontWeight: 600, marginBottom: "8px" }}>{name || `App ${appid}`}</div>
      <ToggleField
        label="Use Per-Game Settings"
        checked={enabled}
        onChange={(on) => {
          update((next) => {
            next.tweaks.games[appid] = { ...(next.tweaks.games[appid] || {}), enabled: on, name };
          });
          const profile = on ? String(gameSettings.fexProfile ?? config.tweaks.global.fexProfile ?? "") : "";
          syncFexLaunchOption(appid, fexSteamString(profile, config.fexProfiles));
        }}
      />
      {enabled ? (
        <>
          <PerfFields values={values} patch={patch} />
          <TweakFields config={config} appid={appid} values={values} patch={patch} />
          <ConfigSection game={{ appid, name }} reload={() => getConfig().then(setConfig).catch(() => {})} />
        </>
      ) : null}
    </ModalRoot>
  );
}
