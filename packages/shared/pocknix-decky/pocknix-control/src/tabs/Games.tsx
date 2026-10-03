import { PanelSection, ToggleField } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { ConfigSection } from "../components/ConfigSection";
import { EnvVarsButton, PerfFields, TouchField, TweakFields, XaliaToggle, audioLatencyOptions } from "../components/GameFields";
import { SelectEdit } from "../components/widgets";
import { availableGames, editTargetOptions } from "../lib/games";
import { fexSteamString, syncFexLaunchOption } from "../lib/launchOptions";
import { clone } from "../lib/util";
import type { Config } from "../types";

export function Games({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
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
  const patchSettings = (patch: Record<string, any>) => {
    setConfig((current) => {
      if (!current) return current;
      const next = clone(current);
      if (editingDefault) {
        Object.assign(next.tweaks.global, patch);
      } else if (perGameEnabled) {
        const existing = next.tweaks.games[game!.appid] || {};
        next.tweaks.games[game!.appid] = { ...existing, enabled: true, name: game!.name || "", ...patch };
      }
      return next;
    });
  };
  const setPerGameEnabled = (enabled: boolean) => {
    if (!game?.appid) return;
    setConfig((current) => {
      if (!current) return current;
      const next = clone(current);
      next.tweaks.games[game.appid] = {
        ...(next.tweaks.games[game.appid] || {}),
        enabled,
        name: game.name || "",
      };
      return next;
    });
    // Token policy mirrors the wrapper's merge: enabled = own-or-global profile, disabled = none.
    const stored = tweaks.games[game.appid] || {};
    const profile = enabled ? String(stored.fexProfile ?? tweaks.global.fexProfile ?? "") : "";
    syncFexLaunchOption(game.appid, fexSteamString(profile, config.fexProfiles));
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
      {showFields && !editingDefault ? (
        <PanelSection title="PERFORMANCE">
          <PerfFields values={values} patch={patchSettings} />
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
                onChange={(id) => {
                  patchSettings({ fexProfile: id });
                  // Enabled games without their own profile inherit this pick; resync their tokens.
                  for (const [appid, entry] of Object.entries(tweaks.games)) {
                    if (entry?.enabled === true && !entry.fexProfile) {
                      syncFexLaunchOption(appid, fexSteamString(String(id), presets));
                    }
                  }
                }}
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
