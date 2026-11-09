import { PanelSection, ToggleField } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { setFanMode, setLavdMode } from "../backend";
import { PrimeCoreToggle, TouchField, TweakFields, XaliaToggle, audioLatencyOptions, fanOptions, lavdOptions } from "../components/GameFields";
import { APPLIES_NEXT_LAUNCH, APPLIES_NOW } from "../lib/applies";
import { parseEnvVars } from "../lib/envVars";
import { EnvVarsField } from "../components/EnvVars";
import { SelectEdit } from "../components/widgets";
import { availableGames, editTargetOptions } from "../lib/games";
import type { Config } from "../types";

export function Games({ config, setConfig, patch, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  patch: (appid: string, fields: Record<string, any>) => void;
  reload: () => void;
}) {
  const runtimeGame = config.game;
  const games = availableGames(config);
  const game = config.selectedGame || runtimeGame || null;
  const tweaks = config.tweaks;
  const gameSettings = game?.appid ? tweaks.games[game.appid] || {} : {};
  const editingDefault = !game?.appid;
  const perGameEnabled = !!(game?.appid && gameSettings.enabled === true);
  const values = editingDefault || !perGameEnabled ? tweaks.global : { ...tweaks.global, ...gameSettings };
  const patchSettings = (fields: Record<string, any>) => {
    if (editingDefault) patch("", fields);
    else if (perGameEnabled) patch(game!.appid, { ...fields, enabled: true, name: game!.name || "" });
  };
  const setPerGameEnabled = (enabled: boolean) => {
    if (game?.appid) patch(game.appid, { enabled, name: game.name || "" });
  };
  // "" is the explicit Default target, not "nothing selected"; store a sentinel
  // so it doesn't fall back to the running game in the selectedGame derivation.
  const setSelectedGame = (appid: any) => {
    const id = String(appid);
    if (!id) {
      setConfig((current) => (current ? { ...current, selectedGame: { appid: "", name: "Default" } } : current));
      return;
    }
    const saved = games.find((candidate) => candidate.appid === id);
    setConfig((current) => (current ? { ...current, selectedGame: saved || null } : current));
  };

  // Default's fan and scheduler are the system modes, not tweaks.global.
  const applyMode = async (setter: (mode: string) => Promise<Config>, mode: string) => {
    try {
      const next = await setter(mode);
      setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
    } catch (error) {
      reload();
    }
  };
  const presets = config.fexProfiles || {};
  const storedProfile = values.fexProfile as string | undefined;
  const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
  const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
  const storedLatency = String(values.audioLatency ?? "");
  const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";

  return (
    <>
      <PanelSection title="PERFORMANCE & GAME TWEAKS">
        <SelectEdit label="Game" value={game?.appid || ""} options={editTargetOptions(config)} onChange={setSelectedGame} />
        {!editingDefault ? <ToggleField label="Use Per-Game Settings" checked={perGameEnabled} onChange={setPerGameEnabled} /> : null}
      </PanelSection>
      {editingDefault ? (
        <>
          <PanelSection title="PERFORMANCE">
            <SelectEdit label="Fan Curve" description={APPLIES_NOW} value={config.fanMode} options={fanOptions} onChange={(mode) => applyMode(setFanMode, mode)} />
            <SelectEdit label="CPU Scheduler" description={APPLIES_NOW} value={config.lavdMode} options={lavdOptions} onChange={(mode) => applyMode(setLavdMode, mode)} />
          </PanelSection>
          <PanelSection title="GAME TWEAKS">
            <SelectEdit label="FEX Preset" description={APPLIES_NEXT_LAUNCH} value={fexValue} options={fexOptions} onChange={(id) => patchSettings({ fexProfile: id })} />
            <SelectEdit
              label="Audio Buffer"
              description={APPLIES_NEXT_LAUNCH}
              value={audioValue}
              options={audioLatencyOptions}
              onChange={(id) => patchSettings({ audioLatency: id })}
            />
            <TouchField values={values} patch={patchSettings} />
            <XaliaToggle values={values} patch={patchSettings} />
          </PanelSection>
          {config.primeCore || parseEnvVars(tweaks.global.envVars).length ? (
            <PanelSection title="ADVANCED">
              <PrimeCoreToggle primeCore={config.primeCore} values={values} patch={patchSettings} />
              <EnvVarsField own={tweaks.global.envVars} canAdd={false} onChange={(envVars) => patchSettings({ envVars })} />
            </PanelSection>
          ) : null}
        </>
      ) : perGameEnabled ? (
        <TweakFields config={config} appid={game!.appid} values={values} patch={patchSettings} />
      ) : null}
    </>
  );
}
