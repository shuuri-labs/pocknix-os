import { PanelSection, ToggleField } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { setFanMode, setLavdMode } from "../backend";
import { ConfigSection } from "../components/ConfigSection";
import { EnvVarsButton, PerfFields, TouchField, TweakFields, XaliaToggle, audioLatencyOptions, fanOptions, lavdOptions } from "../components/GameFields";
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

  // Default target: FEX/audio/env edit tweaks.global; fan + scheduler are the LIVE system
  // modes, applied immediately through the backend.
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

  const showFields = editingDefault || perGameEnabled;
  return (
    <>
      <PanelSection title="PERFORMANCE & GAME TWEAKS">
        <SelectEdit label="Game" value={game?.appid || ""} options={editTargetOptions(config)} onChange={setSelectedGame} />
        {!editingDefault ? <ToggleField label="Use Per-Game Settings" checked={perGameEnabled} onChange={setPerGameEnabled} /> : null}
      </PanelSection>
      {showFields ? (
        <PanelSection title="PERFORMANCE">
          {editingDefault ? (
            <>
              <SelectEdit label="CPU Scheduler" value={config.lavdMode} options={lavdOptions} onChange={(mode) => applyMode(setLavdMode, mode)} />
              <SelectEdit label="Fan Curve" value={config.fanMode} options={fanOptions} onChange={(mode) => applyMode(setFanMode, mode)} />
            </>
          ) : (
            <PerfFields values={values} patch={patchSettings} />
          )}
        </PanelSection>
      ) : null}
      {showFields ? (
        <PanelSection title="GAME TWEAKS">
          <div className="pocknix-note">Changes apply on next game launch</div>
          {editingDefault ? (
            <>
              <SelectEdit
                label="FEX Preset"
                value={fexValue}
                options={fexOptions}
                onChange={(id) => patchSettings({ fexProfile: id })}
              />
              <SelectEdit label="Audio Buffer" value={audioValue} options={audioLatencyOptions} onChange={(id) => patchSettings({ audioLatency: id })} />
              <XaliaToggle values={values} patch={patchSettings} />
              <TouchField values={values} patch={patchSettings} />
              <EnvVarsButton value={String(values.envVars ?? "")} onSave={(next) => patchSettings({ envVars: next })} />
            </>
          ) : (
            <TweakFields config={config} appid={game!.appid} values={values} patch={patchSettings} />
          )}
        </PanelSection>
      ) : null}
      {!editingDefault && perGameEnabled ? (
        <ConfigSection game={{ appid: game!.appid, name: game!.name || "" }} reload={reload} />
      ) : null}
    </>
  );
}
