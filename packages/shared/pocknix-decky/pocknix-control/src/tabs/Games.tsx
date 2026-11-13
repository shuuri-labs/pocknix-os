import { PanelSection } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { setFanMode, setLavdMode } from "../backend";
import { GameOnlyToggle, KeepCompressedToggle, Note, PrimeCoreToggle, TouchField, TweakFields, XaliaToggle, audioLatencyOptions, fanOptions, lavdOptions, resetFields } from "../components/GameFields";
import { APPLIES_NEXT_LAUNCH, APPLIES_NOW, timed } from "../lib/applies";
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
  // Default reaches whatever is running; a game's own settings only reach that game.
  const live = !!runtimeGame?.appid && (editingDefault || runtimeGame.appid === game?.appid);
  const nextLaunch = timed(live, APPLIES_NEXT_LAUNCH);

  return (
    <>
      <PanelSection title="PERFORMANCE & GAME TWEAKS">
        <SelectEdit label="Game" value={game?.appid || ""} options={editTargetOptions(config)} onChange={setSelectedGame} />
        {!editingDefault ? <GameOnlyToggle checked={perGameEnabled} onChange={setPerGameEnabled} /> : null}
      </PanelSection>
      {editingDefault ? (
        <>
          {live ? null : <Note text="Changes apply to every game you start." />}
          <PanelSection title="PERFORMANCE">
            <SelectEdit
              label="Fan Curve"
              description={live ? APPLIES_NOW : "Outside games too."}
              value={config.fanMode}
              options={fanOptions}
              onChange={(mode) => applyMode(setFanMode, mode)}
            />
            <SelectEdit
              label="CPU Scheduler"
              description={live ? APPLIES_NOW : "Outside games too."}
              value={config.lavdMode}
              options={lavdOptions}
              onChange={(mode) => applyMode(setLavdMode, mode)}
            />
          </PanelSection>
          <PanelSection title="GAME TWEAKS">
            <SelectEdit label="FEX Preset" description={nextLaunch} value={fexValue} options={fexOptions} onChange={(id) => patchSettings({ fexProfile: id })} />
            <KeepCompressedToggle values={values} patch={patchSettings} live={live} />
            <SelectEdit
              label="Audio Buffer"
              description={nextLaunch}
              value={audioValue}
              options={audioLatencyOptions}
              onChange={(id) => patchSettings({ audioLatency: id })}
            />
            <TouchField values={values} patch={patchSettings} live={live} />
            <XaliaToggle values={values} patch={patchSettings} live={live} />
          </PanelSection>
          {config.primeCore || parseEnvVars(tweaks.global.envVars).length ? (
            <PanelSection title="ADVANCED">
              <PrimeCoreToggle primeCore={config.primeCore} values={values} patch={patchSettings} live={live} />
              <EnvVarsField own={tweaks.global.envVars} canAdd={false} live={live} onChange={(envVars) => patchSettings({ envVars })} />
            </PanelSection>
          ) : null}
        </>
      ) : perGameEnabled ? (
        <TweakFields
          config={config}
          appid={game!.appid}
          name={game!.name || `App ${game!.appid}`}
          values={values}
          patch={patchSettings}
          live={live}
          onReset={() => patch(game!.appid, resetFields(config, game!.appid))}
        />
      ) : null}
    </>
  );
}
