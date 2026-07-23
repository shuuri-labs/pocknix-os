import { PanelSection } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { setFanMode, setLavdMode } from "../backend";
import { SelectEdit } from "../components/widgets";
import type { Config } from "../types";

const fanOptions = [
  { data: "quiet", label: "Quiet" },
  { data: "moderate", label: "Moderate" },
  { data: "performance", label: "Performance" },
];
const lavdOptions = [
  { data: "autopilot", label: "Autopilot" },
  { data: "performance", label: "Performance" },
];

export function Power({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
}) {
  const applyMode = async (setter: (mode: string) => Promise<Config>, mode: string) => {
    try {
      const next = await setter(mode);
      setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
    } catch (error) {
      reload();
    }
  };
  return (
    <PanelSection title="PERFORMANCE">
      <SelectEdit label="Fan Curve" value={config.fanMode} options={fanOptions} onChange={(mode) => applyMode(setFanMode, mode)} />
      <SelectEdit label="CPU Scheduler" value={config.lavdMode} options={lavdOptions} onChange={(mode) => applyMode(setLavdMode, mode)} />
    </PanelSection>
  );
}
