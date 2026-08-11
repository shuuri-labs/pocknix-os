import { PanelSection, PanelSectionRow, SliderField, ToggleField } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { useEffect, useRef, useState } from "react";
import { setBootPulse, setLed, setLedEnabled, setLedLinked, setLedMode, setLedModeBrightness, setLedSide, setLedSideBrightness, setLedSideMode, setLedTempRate, setLedTempThresholds } from "../backend";
import { ColorControls } from "../components/ColorControls";
import { SelectEdit } from "../components/widgets";
import { hsvToRgb, rgbToHsv } from "../lib/rgb";
import type { Config, LedMode, LedSide, LedSideKey, LedSideMode } from "../types";

// Stored RGB holds the full-value color; the kernel multicolor class scales each
// channel by brightness/max_brightness, so dimming is linear and the color survives.
function commit(side: LedSideKey, hsv: [number, number, number], brightness: number, setConfig: Dispatch<SetStateAction<Config | null>>, reload: () => void) {
  const [r, g, b] = hsvToRgb(hsv[0], hsv[1], 100);
  setLed(side, r, g, b, brightness)
    .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
    .catch(() => reload());
}

function sideHsv(side: LedSide): [number, number, number] {
  return rgbToHsv(side.r, side.g, side.b);
}

const MODE_OPTIONS = [
  { data: "static", label: "Static" },
  { data: "rainbow", label: "Rainbow" },
  { data: "battery", label: "Battery" },
  { data: "temperature", label: "Temperature" },
];

const SIDE_MODE_OPTIONS = [
  { data: "off", label: "Off" },
  { data: "match", label: "Match Rings" },
  { data: "static", label: "Static" },
  { data: "battery", label: "Battery" },
  { data: "temperature", label: "Temperature" },
];

// Debounced single-value slider: commits a byte value after the drag settles, with an
// unmount flush so an edit still in the debounce window isn't lost when the QAM closes.
function useDebouncedByte(value: number, commitFn: (v: number) => void) {
  const [local, setLocal] = useState(value);
  const pending = useRef<number | null>(null);
  const commitRef = useRef(commitFn);
  commitRef.current = commitFn;
  useEffect(() => { if (pending.current === null) setLocal(value); }, [value]);
  useEffect(() => {
    if (pending.current === null) return;
    const snapshot = pending.current;
    const timer = window.setTimeout(() => {
      pending.current = null;
      commitRef.current(snapshot);
    }, 350);
    return () => window.clearTimeout(timer);
  }, [local]);
  useEffect(() => () => {
    if (pending.current !== null) {
      const snapshot = pending.current;
      commitRef.current(snapshot);
    }
  }, []);
  return [local, (v: number) => { setLocal(v); pending.current = v; }] as const;
}

export function Lighting({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
}) {
  const led = config.led;
  const leftHsv = sideHsv(led.left);
  const rightHsv = sideHsv(led.right);
  const sideHsvVal = sideHsv(led.side);

  const commitLeft = (hsv: [number, number, number], brightness: number) => commit("left", hsv, brightness, setConfig, reload);
  const commitRight = (hsv: [number, number, number], brightness: number) => commit("right", hsv, brightness, setConfig, reload);
  const commitBoth = (hsv: [number, number, number], brightness: number) => commit("both", hsv, brightness, setConfig, reload);
  const commitSide = (hsv: [number, number, number], brightness: number) => {
    const [r, g, b] = hsvToRgb(hsv[0], hsv[1], 100);
    setLedSide(r, g, b, brightness)
      .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
      .catch(() => reload());
  };

  const modeOptions = MODE_OPTIONS.filter((o) =>
    o.data === "static"
    || (o.data === "rainbow" && led.rainbowAvailable)
    || (o.data === "battery" && led.batteryAvailable)
    || (o.data === "temperature" && led.tempAvailable)
  );

  const sideModeOptions = SIDE_MODE_OPTIONS.filter((o) =>
    o.data === "off" || o.data === "match" || o.data === "static"
    || (o.data === "battery" && led.batteryAvailable)
    || (o.data === "temperature" && led.tempAvailable)
  );

  return (
    <>
      <PanelSection title="STICK LIGHTS">
        <PanelSectionRow>
          <ToggleField
            label="Enable"
            checked={led.enabled}
            onChange={(value) =>
              setLedEnabled(value)
                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                .catch(() => reload())
            }
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <ToggleField
            label="Boot Pulse"
            description="Pulse the sticks white on boot while Steam loads, then switch to your colors."
            checked={led.bootPulse}
            disabled={!led.enabled}
            onChange={(value) =>
              setBootPulse(value)
                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                .catch(() => reload())
            }
          />
        </PanelSectionRow>
        <SelectEdit
          label="Mode"
          value={led.mode}
          options={modeOptions}
          onChange={(mode: LedMode) =>
            setLedMode(mode)
              .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
              .catch(() => reload())
          }
        />
        {led.mode === "static" && (
          <PanelSectionRow>
            <ToggleField
              label="Link Left & Right"
              description="Match both sticks to the same color."
              checked={led.linked}
              disabled={!led.enabled}
              onChange={(value) =>
                setLedLinked(value)
                  .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                  .catch(() => reload())
              }
            />
          </PanelSectionRow>
        )}
        {led.enabled && (led.mode === "rainbow" || led.mode === "battery" || led.mode === "temperature") && (
          <ModeBrightness config={config} setConfig={setConfig} reload={reload} />
        )}
      </PanelSection>

      {led.enabled && led.mode === "static" && (
        led.linked ? (
          <PanelSection title="BOTH STICKS">
            <ColorControls zone="both" hsv={leftHsv} brightness={led.left.brightness} onCommit={commitBoth} />
          </PanelSection>
        ) : (
          <>
            <PanelSection title="LEFT STICK">
              <ColorControls zone="left" hsv={leftHsv} brightness={led.left.brightness} onCommit={commitLeft} />
            </PanelSection>
            <PanelSection title="RIGHT STICK">
              <ColorControls zone="right" hsv={rightHsv} brightness={led.right.brightness} onCommit={commitRight} />
            </PanelSection>
          </>
        )
      )}

      {led.sidesAvailable && (
        <>
          <PanelSection title="SIDE LIGHTS">
            <SelectEdit
              label="Mode"
              value={led.sideMode}
              options={sideModeOptions}
              onChange={(mode: LedSideMode) =>
                setLedSideMode(mode)
                  .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                  .catch(() => reload())
              }
            />
            {led.enabled && (led.sideMode === "battery" || led.sideMode === "temperature") && (
              <SideBrightness config={config} setConfig={setConfig} reload={reload} />
            )}
          </PanelSection>

          {led.enabled && led.sideMode === "static" && (
            <PanelSection title="SIDE LIGHTS">
              <ColorControls zone="side" hsv={sideHsvVal} brightness={led.side.brightness} onCommit={commitSide} />
            </PanelSection>
          )}
        </>
      )}

      {led.enabled && (led.mode === "temperature" || led.sideMode === "temperature") && (
        <TempThresholds config={config} setConfig={setConfig} reload={reload} />
      )}
    </>
  );
}

const briToPercent = (bri: number) => Math.round((bri / 255) * 100);
const percentToBri = (percent: number) => Math.round((percent / 100) * 255);

function ModeBrightness({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
}) {
  const led = config.led;
  const apply = (v: number) =>
    setLedModeBrightness(v)
      .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
      .catch(() => reload());
  const [local, setLocal] = useDebouncedByte(led.modeBrightness, apply);
  return (
    <PanelSectionRow>
      <SliderField
        label="Brightness"
        value={briToPercent(local)}
        min={0}
        max={100}
        step={1}
        showValue
        validValues="range"
        valueSuffix="%"
        bottomSeparator="thick"
        onChange={(percent: number) => setLocal(percentToBri(percent))}
      />
    </PanelSectionRow>
  );
}

function SideBrightness({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
}) {
  const led = config.led;
  const apply = (v: number) =>
    setLedSideBrightness(v)
      .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
      .catch(() => reload());
  const [local, setLocal] = useDebouncedByte(led.sideBrightness, apply);
  return (
    <PanelSectionRow>
      <SliderField
        label="Side Brightness"
        value={briToPercent(local)}
        min={0}
        max={100}
        step={1}
        showValue
        validValues="range"
        valueSuffix="%"
        bottomSeparator="thick"
        onChange={(percent: number) => setLocal(percentToBri(percent))}
      />
    </PanelSectionRow>
  );
}

const TEMP_RATE_OPTIONS = [
  { data: "slow", label: "Slow (5s)" },
  { data: "normal", label: "Normal (3s)" },
  { data: "fast", label: "Fast (1s)" },
];

function TempThresholds({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
}) {
  const led = config.led;
  // Local state for instant slider response; commit is debounced. The cross-constraint
  // (min < max) is enforced by the backend _sanitize, but locally we clamp the bounds
  // so dragging one slider doesn't yank the other's range mid-drag.
  const [localMin, setLocalMin] = useState(led.tempMin);
  const [localMax, setLocalMax] = useState(led.tempMax);
  useEffect(() => { setLocalMin(led.tempMin); }, [led.tempMin]);
  useEffect(() => { setLocalMax(led.tempMax); }, [led.tempMax]);

  const pending = useRef<{ lo: number; hi: number } | null>(null);
  const applyRef = useRef<(lo: number, hi: number) => void>(() => {});
  applyRef.current = (lo: number, hi: number) =>
    setLedTempThresholds(lo, hi)
      .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
      .catch(() => reload());
  useEffect(() => {
    if (pending.current === null) return;
    const snapshot = pending.current;
    const timer = window.setTimeout(() => {
      pending.current = null;
      applyRef.current(snapshot.lo, snapshot.hi);
    }, 350);
    return () => window.clearTimeout(timer);
  }, [localMin, localMax]);
  useEffect(() => () => {
    if (pending.current !== null) {
      applyRef.current(pending.current.lo, pending.current.hi);
    }
  }, []);

  const setMin = (v: number) => {
    const clamped = Math.min(v, localMax - 1);
    setLocalMin(clamped);
    pending.current = { lo: clamped, hi: localMax };
  };
  const setMax = (v: number) => {
    const clamped = Math.max(v, localMin + 1);
    setLocalMax(clamped);
    pending.current = { lo: localMin, hi: clamped };
  };

  return (
    <PanelSection title="TEMPERATURE">
      <SelectEdit
        label="Update Rate"
        value={led.tempRate}
        options={TEMP_RATE_OPTIONS}
        onChange={(rate: "slow" | "normal" | "fast") =>
          setLedTempRate(rate)
            .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
            .catch(() => reload())
        }
      />
      <PanelSectionRow>
        <SliderField
          label="Min (Blue)"
          value={localMin}
          min={0}
          max={localMax - 1}
          step={1}
          showValue
          validValues="range"
          valueSuffix="°C"
          bottomSeparator="thick"
          onChange={setMin}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <SliderField
          label="Max (Red)"
          value={localMax}
          min={localMin + 1}
          max={100}
          step={1}
          showValue
          validValues="range"
          valueSuffix="°C"
          bottomSeparator="thick"
          onChange={setMax}
        />
      </PanelSectionRow>
    </PanelSection>
  );
}
