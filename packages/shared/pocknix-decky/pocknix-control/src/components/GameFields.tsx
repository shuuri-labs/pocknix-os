import { PanelSection, PanelSectionRow, ToggleField } from "@decky/ui";
import { useEffect, useState } from "react";
import { availableCompatTools, registerForCompatTool, setCompatTool } from "../lib/compat";
import type { CompatTool } from "../lib/compat";
import { EnvVarsField } from "./EnvVars";
import { APPLIES_NEXT_LAUNCH, APPLIES_NOW } from "../lib/applies";
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
const globalChoice = { data: "", label: "Use global" };

export function XaliaToggle({ values, patch }: {
  values: Record<string, any>;
  patch: (patch: Record<string, any>) => void;
}) {
  return (
    <PanelSectionRow>
      <ToggleField
        label="Disable Xalia"
        description={`${APPLIES_NEXT_LAUNCH}. Saves CPU in every game. Xalia lets a controller work menus and launchers built for a mouse, so turn this off when docked without a mouse or touchscreen.`}
        checked={values.disableXalia !== false}
        onChange={(checked) => patch({ disableXalia: checked })}
      />
    </PanelSectionRow>
  );
}

export function TouchField({ values, patch }: { values: Record<string, any>; patch: (patch: Record<string, any>) => void }) {
  return (
    <PanelSectionRow>
      <ToggleField
        label="Disable Touchscreen"
        description={`${APPLIES_NOW}. Stops stray touches while the game runs.`}
        checked={values.touchDisabled === true}
        onChange={(on) => patch({ touchDisabled: on })}
      />
    </PanelSectionRow>
  );
}

export function PrimeCoreToggle({ primeCore, values, patch }: {
  primeCore?: string;
  values: Record<string, any>;
  patch: (patch: Record<string, any>) => void;
}) {
  if (!primeCore) return null;
  return (
    <PanelSectionRow>
      <ToggleField
        label="Fastest Core First"
        description={`${APPLIES_NEXT_LAUNCH}. Gives the game the fastest core (CPU ${primeCore}) as its first one. Can help games that do most of their work on one core.`}
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
const perGameFan = [globalChoice, ...fanOptions];
const perGameLavd = [globalChoice, ...lavdOptions];

/** Per-game override ("" = follow the global mode); the backend retunes a running game on save. */
export function FanField({ values, patch }: { values: Record<string, any>; patch: (patch: Record<string, any>) => void }) {
  return <SelectEdit label="Fan Curve" description={APPLIES_NOW} value={pick(perGameFan, values.fanMode)} options={perGameFan} onChange={(id) => patch({ fanMode: id })} />;
}

export function SchedulerField({ values, patch }: { values: Record<string, any>; patch: (patch: Record<string, any>) => void }) {
  return (
    <SelectEdit
      label="CPU Scheduler"
      description={APPLIES_NOW}
      value={pick(perGameLavd, values.lavdMode)}
      options={perGameLavd}
      onChange={(id) => patch({ lavdMode: id })}
    />
  );
}

/** Every per-game control, shared by the Games tab and the library context-menu modal. */
export function TweakFields({ config, appid, values, patch }: {
  config: Config;
  appid: string;
  values: Record<string, any>;
  patch: (patch: Record<string, any>) => void;
}) {
  // Proton pick is Steam's own per-game compat setting (see lib/compat.ts) — read live and
  // written straight back to Steam, so it mirrors the game-properties dropdown both ways.
  const [compatTools, setCompatTools] = useState<CompatTool[]>([]);
  const [currentTool, setCurrentTool] = useState("");
  useEffect(() => {
    setCompatTools([]);
    setCurrentTool("");
    if (!appid) return;
    let live = true;
    availableCompatTools(appid).then((tools) => {
      if (live) setCompatTools(tools);
    });
    const unregister = registerForCompatTool(appid, (tool) => {
      if (live) setCurrentTool(tool);
    });
    return () => {
      live = false;
      unregister();
    };
  }, [appid]);
  const compatOptions = [
    { data: "", label: "Steam default" },
    ...compatTools.map((tool) => ({ data: tool.name, label: tool.label })),
  ];
  const compatValue = compatOptions.some((option) => option.data === currentTool) ? currentTool : "";

  const presets = config.fexProfiles || {};
  const storedProfile = values.fexProfile as string | undefined;
  const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
  const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
  const storedLatency = String(values.audioLatency ?? "");
  const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
  const mesaOptions = config.mesaVersions?.length ? config.mesaVersions : [{ data: "", label: "System default" }];
  const storedMesa = String(values.mesaVersion ?? "");
  const mesaValue = mesaOptions.some((option) => option.data === storedMesa) ? storedMesa : "";

  return (
    <>
      <PanelSection title="PERFORMANCE">
        <FanField values={values} patch={patch} />
        <SchedulerField values={values} patch={patch} />
      </PanelSection>
      <PanelSection title="GAME TWEAKS">
        <SelectEdit
          label="Proton Version"
          description={APPLIES_NEXT_LAUNCH}
          value={compatValue}
          options={compatOptions}
          onChange={(name) => {
            setCurrentTool(String(name));
            setCompatTool(appid, String(name));
          }}
        />
        <SelectEdit label="FEX Preset" description={APPLIES_NEXT_LAUNCH} value={fexValue} options={fexOptions} onChange={(id) => patch({ fexProfile: id })} />
        <SelectEdit label="Mesa Version" description={APPLIES_NEXT_LAUNCH} value={mesaValue} options={mesaOptions} onChange={(id) => patch({ mesaVersion: id })} />
        <SelectEdit label="Audio Buffer" description={APPLIES_NEXT_LAUNCH} value={audioValue} options={audioLatencyOptions} onChange={(id) => patch({ audioLatency: id })} />
        <TouchField values={values} patch={patch} />
        <XaliaToggle values={values} patch={patch} />
      </PanelSection>
      <PanelSection title="ADVANCED">
        <PrimeCoreToggle primeCore={config.primeCore} values={values} patch={patch} />
        <EnvVarsField
          own={config.tweaks.games[appid]?.envVars}
          inherited={config.tweaks.global.envVars}
          onChange={(envVars) => patch({ envVars })}
        />
      </PanelSection>
    </>
  );
}
