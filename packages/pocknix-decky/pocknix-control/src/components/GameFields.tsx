import { ButtonItem, ConfirmModal, PanelSectionRow, TextField, showModal } from "@decky/ui";
import { useEffect, useState } from "react";
import { availableCompatTools, registerForCompatTool, setCompatTool } from "../lib/compat";
import type { CompatTool } from "../lib/compat";
import { SelectEdit } from "./widgets";
import type { Config } from "../types";

// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default. 60 measured ~10x fewer underruns.
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
// The proton wrapper resolves "big" against the board's POCKNIX_BIG_CORES mask.
export const cpuPinOptions = [
  { data: "", label: "All cores" },
  { data: "big", label: "Big cores only" },
];
const globalChoice = { data: "", label: "Use global" };

export function EnvVarsModal({ initial, onSave, closeModal }: { initial: string; onSave: (value: string) => void; closeModal?: () => void }) {
  const [value, setValue] = useState(initial);
  return (
    <ConfirmModal
      strTitle="Environment Variables"
      strDescription={'Space-separated KEY=VALUE pairs; quote values with spaces, e.g. DXVK_CONFIG="dxgi.customDeviceDesc = GTX 480". Steam launch options win over these.'}
      strOKButtonText="Save"
      onCancel={() => closeModal?.()}
      onOK={() => {
        onSave(value.trim());
        closeModal?.();
      }}
    >
      <TextField label="Variables" value={value} onChange={(event) => setValue(event.target.value)} />
    </ConfirmModal>
  );
}

export function EnvVarsButton({ value, onSave }: { value: string; onSave: (next: string) => void }) {
  return (
    <PanelSectionRow>
      <ButtonItem
        layout="below"
        description={value ? value : "None set"}
        onClick={() => showModal(<EnvVarsModal initial={value} onSave={onSave} />)}
      >
        Environment Variables
      </ButtonItem>
    </PanelSectionRow>
  );
}

/** Per-game fan/scheduler overrides ("" = follow the global mode). */
export function PerfFields({ values, patch }: {
  values: Record<string, any>;
  patch: (patch: Record<string, any>) => void;
}) {
  const perGameFan = [globalChoice, ...fanOptions];
  const perGameLavd = [globalChoice, ...lavdOptions];
  const fanValue = perGameFan.some((option) => option.data === String(values.fanMode ?? "")) ? String(values.fanMode ?? "") : "";
  const lavdValue = perGameLavd.some((option) => option.data === String(values.lavdMode ?? "")) ? String(values.lavdMode ?? "") : "";
  const pinValue = cpuPinOptions.some((option) => option.data === String(values.cpuPin ?? "")) ? String(values.cpuPin ?? "") : "";
  return (
    <>
      <SelectEdit label="CPU Scheduler" value={lavdValue} options={perGameLavd} onChange={(id) => patch({ lavdMode: id })} />
      <SelectEdit label="CPU Cores" value={pinValue} options={cpuPinOptions} onChange={(id) => patch({ cpuPin: id })} />
      <SelectEdit label="Fan Curve" value={fanValue} options={perGameFan} onChange={(id) => patch({ fanMode: id })} />
    </>
  );
}

/** The per-game tweak controls, shared by the Games tab and the library context-menu modal. */
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
  const mesaOptions = [{ data: "", label: "System default" }, ...(config.mesaVersions || [])];
  const storedMesa = String(values.mesaVersion ?? "");
  const mesaValue = mesaOptions.some((option) => option.data === storedMesa) ? storedMesa : "";

  return (
    <>
      <SelectEdit
        label="Proton Version"
        value={compatValue}
        options={compatOptions}
        onChange={(name) => {
          setCurrentTool(String(name));
          setCompatTool(appid, String(name));
        }}
      />
      <SelectEdit label="FEX Preset" value={fexValue} options={fexOptions} onChange={(id) => patch({ fexProfile: id })} />
      <SelectEdit label="Audio Buffer" value={audioValue} options={audioLatencyOptions} onChange={(id) => patch({ audioLatency: id })} />
      <SelectEdit label="Mesa Version (ARM Proton only)" value={mesaValue} options={mesaOptions} onChange={(id) => patch({ mesaVersion: id })} />
      <EnvVarsButton value={String(values.envVars ?? "")} onSave={(next) => patch({ envVars: next })} />
    </>
  );
}
