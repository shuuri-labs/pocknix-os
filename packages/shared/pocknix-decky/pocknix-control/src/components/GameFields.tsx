import { ButtonItem, ConfirmModal, PanelSection, PanelSectionRow, ToggleField, showModal } from "@decky/ui";
import { useEffect, useState } from "react";
import { availableCompatTools, registerForCompatTool, setCompatTool } from "../lib/compat";
import type { CompatPick, CompatTool } from "../lib/compat";
import { EnvVarsField } from "./EnvVars";
import { APPLIES_NEXT_LAUNCH, APPLIES_NOW, timed } from "../lib/applies";
import { SelectEdit } from "./widgets";
import type { Config } from "../types";

// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default.
export const audioLatencyOptions = [
  { data: "", label: "Game default" },
  { data: "60", label: "60 ms" },
  { data: "90", label: "90 ms" },
  { data: "120", label: "120 ms" },
];

export const fanOptions = [
  { data: "quiet", label: "Quiet" },
  { data: "moderate", label: "Moderate" },
  { data: "performance", label: "Performance" },
];
export const lavdOptions = [
  { data: "autopilot", label: "Autopilot" },
  { data: "performance", label: "Performance" },
];

type Patch = (patch: Record<string, any>) => void;
type FieldProps = { values: Record<string, any>; patch: Patch; live: boolean };

export function Note({ text }: { text: string }) {
  return <div style={{ padding: "4px 16px 8px", fontSize: "12px", lineHeight: "16px", opacity: 0.62 }}>{text}</div>;
}

export function GameOnlyToggle({ checked, onChange }: { checked: boolean; onChange: (on: boolean) => void }) {
  return <ToggleField label="Use Per-Game Settings" checked={checked} onChange={onChange} />;
}

export function XaliaToggle({ values, patch, live }: FieldProps) {
  return (
    <PanelSectionRow>
      <ToggleField
        label="Disable Xalia"
        description={timed(
          live,
          APPLIES_NEXT_LAUNCH,
          "Saves CPU in every game. Turn off for a game whose menus only work with a mouse, if you can't tap the screen (e.g. docked).",
        )}
        checked={values.disableXalia !== false}
        onChange={(checked) => patch({ disableXalia: checked })}
      />
    </PanelSectionRow>
  );
}

export function KeepCompressedToggle({ values, patch, live }: FieldProps) {
  return (
    <PanelSectionRow>
      <ToggleField
        label="Keep Images Compressed"
        description={timed(
          live,
          APPLIES_NEXT_LAUNCH,
          "Can raise FPS. ARM Proton and emulators on the built-in Mesas only. Turn off if colours look wrong.",
        )}
        checked={values.keepCompressed === true}
        onChange={(on) => patch({ keepCompressed: on })}
      />
    </PanelSectionRow>
  );
}

export function TouchField({ values, patch, live }: FieldProps) {
  return (
    <PanelSectionRow>
      <ToggleField
        label="Disable Touchscreen"
        description={timed(live, APPLIES_NOW, "Stops stray touches during play.")}
        checked={values.touchDisabled === true}
        onChange={(on) => patch({ touchDisabled: on })}
      />
    </PanelSectionRow>
  );
}

export function PrimeCoreToggle({ primeCore, values, patch, live }: FieldProps & { primeCore?: string }) {
  if (!primeCore) return null;
  return (
    <PanelSectionRow>
      <ToggleField
        label="Fastest Core First"
        description={timed(
          live,
          APPLIES_NEXT_LAUNCH,
          `Gives the game the fastest core (CPU ${primeCore}) as its first one. Can help games that do most of their work on one core.`,
        )}
        checked={values.primeCoreFirst === true}
        onChange={(on) => patch({ primeCoreFirst: on })}
      />
    </PanelSectionRow>
  );
}

const pick = (options: { data: string }[], value: unknown) => {
  const v = String(value ?? "");
  return options.some((option) => option.data === v) ? v : "";
};
const labelOf = (options: { data: string; label: string }[], value: string) => options.find((o) => o.data === value)?.label || value;
const withAllGames = (options: { data: string; label: string }[], current: string) => [
  { data: "", label: `Default (${labelOf(options, current)})` },
  ...options,
];

/** Per-game override ("" = follow Default); the backend retunes a running game on save. */
export function FanField({ config, values, patch, live }: FieldProps & { config: Config }) {
  const options = withAllGames(fanOptions, config.fanMode);
  return (
    <SelectEdit
      label="Fan Curve"
      description={timed(live, APPLIES_NOW)}
      value={pick(options, values.fanMode)}
      options={options}
      onChange={(id) => patch({ fanMode: id })}
    />
  );
}

export function SchedulerField({ config, values, patch, live }: FieldProps & { config: Config }) {
  const options = withAllGames(lavdOptions, config.lavdMode);
  return (
    <SelectEdit
      label="CPU Scheduler"
      description={timed(live, APPLIES_NOW)}
      value={pick(options, values.lavdMode)}
      options={options}
      onChange={(id) => patch({ lavdMode: id })}
    />
  );
}

function ResetGame({ name, onReset }: { name: string; onReset: () => void }) {
  return (
    <PanelSection>
      <PanelSectionRow>
        <ButtonItem
          layout="below"
          onClick={() =>
            showModal(
              <ConfirmModal
                strTitle={`Reset ${name}?`}
                strDescription="Clears this game's own settings so it uses Default again. Proton Version is Steam's setting and stays as it is."
                strOKButtonText="Reset"
                onOK={onReset}
              />,
            )
          }
        >
          Reset This Game
        </ButtonItem>
      </PanelSectionRow>
    </PanelSection>
  );
}

/** Every per-game control, shared by the Games tab and the library context-menu modal. */
export function TweakFields({ config, appid, name, values, patch, live, onReset }: {
  config: Config;
  appid: string;
  name: string;
  values: Record<string, any>;
  patch: Patch;
  /** This game is running, so a change can apply now. */
  live: boolean;
  onReset: () => void;
}) {
  // Proton pick is Steam's own per-game compat setting (see lib/compat.ts) — read live and
  // written straight back to Steam, so it mirrors the game-properties dropdown both ways.
  const [compatTools, setCompatTools] = useState<CompatTool[]>([]);
  const [compat, setCompat] = useState<CompatPick>({ tool: "", label: "" });
  useEffect(() => {
    setCompatTools([]);
    setCompat({ tool: "", label: "" });
    if (!appid) return;
    let mounted = true;
    availableCompatTools(appid).then((tools) => {
      if (mounted) setCompatTools(tools);
    });
    const unregister = registerForCompatTool(appid, (next) => {
      if (mounted) setCompat(next);
    });
    return () => {
      mounted = false;
      unregister();
    };
  }, [appid]);
  const compatOptions = [
    { data: "", label: "Steam default" },
    ...compatTools.map((tool) => ({ data: tool.name, label: tool.label })),
  ];
  const compatValue = compatOptions.some((option) => option.data === compat.tool) ? compat.tool : "";
  const steamChoice = !compatValue && compat.label ? `Steam picks ${compat.label}.` : undefined;

  const presets = config.fexProfiles || {};
  const storedProfile = values.fexProfile as string | undefined;
  const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
  const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
  const storedLatency = String(values.audioLatency ?? "");
  const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
  const mesaOptions = config.mesaVersions?.length ? config.mesaVersions : [{ data: "", label: "System default" }];
  const storedMesa = String(values.mesaVersion ?? "");
  const mesaValue = mesaOptions.some((option) => option.data === storedMesa) ? storedMesa : "";
  const nextLaunch = timed(live, APPLIES_NEXT_LAUNCH);

  return (
    <>
      {live ? null : <Note text="Changes apply when you start the game." />}
      <PanelSection title="PERFORMANCE">
        <FanField config={config} values={values} patch={patch} live={live} />
        <SchedulerField config={config} values={values} patch={patch} live={live} />
      </PanelSection>
      <PanelSection title="GAME TWEAKS">
        <SelectEdit
          label="Proton Version"
          description={timed(live, APPLIES_NEXT_LAUNCH, steamChoice)}
          value={compatValue}
          options={compatOptions}
          onChange={(tool) => {
            setCompat((current) => ({ ...current, tool: String(tool) }));
            setCompatTool(appid, String(tool));
          }}
        />
        <SelectEdit label="FEX Preset" description={nextLaunch} value={fexValue} options={fexOptions} onChange={(id) => patch({ fexProfile: id })} />
        <SelectEdit label="Mesa Version" description={nextLaunch} value={mesaValue} options={mesaOptions} onChange={(id) => patch({ mesaVersion: id })} />
        <KeepCompressedToggle values={values} patch={patch} live={live} />
        <SelectEdit label="Audio Buffer" description={nextLaunch} value={audioValue} options={audioLatencyOptions} onChange={(id) => patch({ audioLatency: id })} />
        <TouchField values={values} patch={patch} live={live} />
        <XaliaToggle values={values} patch={patch} live={live} />
      </PanelSection>
      <PanelSection title="ADVANCED">
        <PrimeCoreToggle primeCore={config.primeCore} values={values} patch={patch} live={live} />
        <EnvVarsField
          own={config.tweaks.games[appid]?.envVars}
          inherited={config.tweaks.global.envVars}
          live={live}
          onChange={(envVars) => patch({ envVars })}
        />
      </PanelSection>
      <ResetGame name={name} onReset={onReset} />
    </>
  );
}

/** The fields that undo a game's own settings, keeping its saved name. */
export function resetFields(config: Config, appid: string): Record<string, any> {
  const own = config.tweaks.games[appid] || {};
  const cleared: Record<string, any> = Object.fromEntries(Object.keys(own).filter((key) => key !== "name").map((key) => [key, null]));
  return { ...cleared, enabled: false };
}
