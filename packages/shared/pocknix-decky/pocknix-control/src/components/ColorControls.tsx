import { gamepadSliderClasses, PanelSectionRow, SliderField } from "@decky/ui";
import { useEffect, useRef, useState } from "react";

// SliderField has only onChange, so commits are debounced. The pending value lives in
// a ref so the unmount flush always sees the latest edit, not a stale first-render one.
const COMMIT_DELAY = 350;

// Hardware brightness is 0-255; the slider shows percent so it reads like the other two.
const briToPercent = (bri: number) => Math.round((bri / 255) * 100);
const percentToBri = (percent: number) => Math.round((percent / 100) * 255);

interface ColorControlsProps {
  zone: string;
  hsv: [number, number, number];
  brightness: number;
  onCommit: (hsv: [number, number, number], brightness: number) => void;
}

export function ColorControls({ zone, hsv, brightness, onCommit }: ColorControlsProps) {
  const [hue, saturation] = hsv;
  const [localH, setLocalH] = useState(hsv[0]);
  const [localS, setLocalS] = useState(hsv[1]);
  const [localBri, setLocalBri] = useState(brightness);
  const pending = useRef<{ hsv: [number, number, number]; bri: number } | null>(null);
  const onCommitRef = useRef(onCommit);
  onCommitRef.current = onCommit;

  // A commit response landing mid-drag would otherwise snap the slider backwards.
  useEffect(() => { if (!pending.current) setLocalH(hsv[0]); }, [hue]);
  useEffect(() => { if (!pending.current) setLocalS(hsv[1]); }, [saturation]);
  useEffect(() => { if (!pending.current) setLocalBri(brightness); }, [brightness]);

  const schedule = (h: number, s: number, bri: number) => {
    setLocalH(h);
    setLocalS(s);
    setLocalBri(bri);
    pending.current = { hsv: [h, s, 100], bri };
  };

  useEffect(() => {
    if (pending.current === null) return;
    const snapshot = pending.current;
    const timer = window.setTimeout(() => {
      pending.current = null;
      onCommitRef.current(snapshot.hsv, snapshot.bri);
    }, COMMIT_DELAY);
    return () => window.clearTimeout(timer);
  }, [localH, localS, localBri]);

  // QAM unmounts on close; flush any edit still in the debounce window.
  useEffect(
    () => () => {
      if (pending.current !== null) {
        const snapshot = pending.current;
        pending.current = null;
        onCommitRef.current(snapshot.hsv, snapshot.bri);
      }
    },
    [],
  );

  const setHue = (h: number) => schedule(h, localS, localBri);
  const setSaturation = (s: number) => schedule(localH, s, localBri);
  const setBrightness = (b: number) => schedule(localH, localS, b);

  return (
    <>
      <PanelSectionRow>
        <SliderField
          label="Hue"
          value={localH}
          min={0}
          max={359}
          step={1}
          showValue
          validValues="range"
          valueSuffix="°"
          bottomSeparator="thick"
          className={`pocknix-led-${zone}-h`}
          onChange={setHue}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <SliderField
          label="Saturation"
          value={localS}
          min={0}
          max={100}
          step={1}
          showValue
          validValues="range"
          valueSuffix="%"
          bottomSeparator="thick"
          className={`pocknix-led-${zone}-s`}
          onChange={setSaturation}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <SliderField
          label="Brightness"
          value={briToPercent(localBri)}
          min={0}
          max={100}
          step={1}
          showValue
          validValues="range"
          valueSuffix="%"
          bottomSeparator="thick"
          className={`pocknix-led-${zone}-v`}
          onChange={(percent: number) => setBrightness(percentToBri(percent))}
        />
      </PanelSectionRow>
      <style>{`
        .pocknix-led-${zone}-h .${gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right,
            hsl(0,100%,50%), hsl(60,100%,50%), hsl(120,100%,50%),
            hsl(180,100%,50%), hsl(240,100%,50%), hsl(300,100%,50%), hsl(360,100%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
        .pocknix-led-${zone}-s .${gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right, hsl(0,0%,100%), hsl(${localH},100%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
        .pocknix-led-${zone}-v .${gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right, hsl(0,0%,0%), hsl(${localH},${localS}%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
      `}</style>
    </>
  );
}
