import { ButtonItem, ConfirmModal, Field, PanelSection, PanelSectionRow, TextField, ToggleField, showModal } from "@decky/ui";
import { useCallback, useEffect, useRef, useState } from "react";
import type { Dispatch, SetStateAction } from "react";
import { detectSdcard, formatSdcard, getConfig, saveTweaks, setFanMode, setLavdMode } from "./backend";
import { SelectEdit } from "./components/widgets";
import { useDebouncedSave } from "./hooks/useDebouncedSave";
import { availableGames, currentGame, editTargetOptions } from "./lib/games";
import { clone } from "./lib/util";
import type { Config, SdcardInfo } from "./types";

const fanOptions = [
  { data: "quiet", label: "Quiet" },
  { data: "moderate", label: "Moderate" },
  { data: "performance", label: "Performance" },
];
const lavdOptions = [
  { data: "autopilot", label: "Autopilot" },
  { data: "performance", label: "Performance" },
];
// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default. 60 measured ~10x fewer underruns.
const audioLatencyOptions = [
  { data: "", label: "Game default" },
  { data: "60", label: "60 ms" },
  { data: "90", label: "90 ms" },
  { data: "120", label: "120 ms" },
];

export function Content() {
  const [config, setConfig] = useState<Config | null>(null);
  const [message, setMessage] = useState("Loading");
  const savedTweaksSnapshot = useRef("");
  const load = useCallback(async () => {
    try {
      const next = await getConfig();
      next.game = currentGame();
      next.selectedGame = next.game || null;
      savedTweaksSnapshot.current = JSON.stringify(next.tweaks);
      setConfig(next);
    } catch (error) {
      setMessage(String(error));
    }
  }, []);
  useEffect(() => {
    load();
  }, [load]);
  // Track the running game so opening the QAM mid-game edits that game's profile.
  useEffect(() => {
    if (!config) return;
    let cancelled = false;
    const refreshRuntime = () => {
      try {
        const runtimeGame = currentGame();
        if (cancelled) return;
        setConfig((current) => {
          if (!current) return current;
          if ((current.game?.appid || "") === (runtimeGame?.appid || "") && (current.game?.name || "") === (runtimeGame?.name || "")) return current;
          return { ...current, game: runtimeGame };
        });
      } catch (error) {
      }
    };
    const timer = window.setInterval(refreshRuntime, 2000);
    refreshRuntime();
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [!!config]);
  useDebouncedSave({ config, field: "tweaks", snapshot: savedTweaksSnapshot, save: saveTweaks, setConfig, onError: load });

  if (!config) return <PanelSection title="Pocknix Control"><Field label={message} /></PanelSection>;

  const applyMode = async (setter: (mode: string) => Promise<Config>, mode: string) => {
    try {
      const next = await setter(mode);
      setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
    } catch (error) {
      setMessage(String(error));
      load();
    }
  };

  return (
    <>
      <PanelSection title="PERFORMANCE">
        <SelectEdit label="Fan Curve" value={config.fanMode} options={fanOptions} onChange={(mode) => applyMode(setFanMode, mode)} />
        <SelectEdit label="CPU Scheduler" value={config.lavdMode} options={lavdOptions} onChange={(mode) => applyMode(setLavdMode, mode)} />
      </PanelSection>
      <FexSection config={config} setConfig={setConfig} />
      <SdcardSection />
    </>
  );
}

function cardSummary(card: SdcardInfo | null) {
  if (!card) return "Checking…";
  if (!card.present) return "No SD card detected";
  const size = card.sizeBytes ? `${(card.sizeBytes / 1e9).toFixed(1)} GB` : "";
  const state = card.fstype === "ext4" ? (card.mountpoint ? "mounted" : "") : "not formatted for Steam";
  return [card.label || "unlabeled", size, card.fstype || "no filesystem", state].filter(Boolean).join(" · ");
}

// showModal injects closeModal into this wrapper. We deliberately do NOT forward it to
// ConfirmModal: its internal OK handler would close the dialog immediately, and we want
// it held open (with the confirm button greyed out) until the format finishes.
function FormatConfirmModal({ summary, onConfirm, closeModal }: { summary: string; onConfirm: () => Promise<void>; closeModal?: () => void }) {
  const [text, setText] = useState("");
  const [running, setRunning] = useState(false);
  const armedRef = useRef(false);
  const runningRef = useRef(false);
  armedRef.current = text.trim().toLowerCase() === "format";
  runningRef.current = running;
  const start = async () => {
    if (!armedRef.current || runningRef.current) return;
    setRunning(true);
    await onConfirm();
    closeModal?.();
  };
  return (
    <ConfirmModal
      strTitle="Format SD Card"
      strDescription={
        running
          ? "Formatting… This can take a minute. Do not remove the card."
          : `This erases ALL data on the card (${summary}) and formats it for Steam. Type "format" and press Enter to confirm.`
      }
      strOKButtonText={running ? "Formatting…" : "Erase and Format"}
      bDestructiveWarning={true}
      bOKDisabled={!armedRef.current || running}
      bCancelDisabled={running}
      bDisableBackgroundDismiss={true}
      bHideCloseIcon={true}
      onCancel={() => {
        if (!runningRef.current) closeModal?.();
      }}
      onOK={start}
    >
      {!running ? (
        <TextField
          value={text}
          focusOnMount={true}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") start();
          }}
        />
      ) : null}
    </ConfirmModal>
  );
}

function SdcardSection() {
  const [card, setCard] = useState<SdcardInfo | null>(null);
  const [label, setLabel] = useState("SDCARD");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;

  useEffect(() => {
    let cancelled = false;
    const refresh = async () => {
      if (busyRef.current) return;
      try {
        const next = await detectSdcard();
        if (!cancelled && !busyRef.current) setCard(next);
      } catch (error) {
        if (!cancelled) setStatus(String(error));
      }
    };
    refresh();
    const timer = window.setInterval(refresh, 5000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, []);

  const runFormat = async () => {
    if (busyRef.current) return;
    setBusy(true);
    setStatus("");
    try {
      const next = await formatSdcard(label);
      setCard(next);
    } catch (error) {
      setStatus(String(error));
    } finally {
      setBusy(false);
    }
  };
  const confirmFormat = () => showModal(<FormatConfirmModal summary={cardSummary(card)} onConfirm={runFormat} />);

  return (
    <PanelSection title="SD CARD">
      <Field label="Card" description={cardSummary(card)} />
      <PanelSectionRow>
        <TextField
          label="Label"
          value={label}
          disabled={busy}
          onChange={(event) => setLabel(event.target.value.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 16))}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem layout="below" disabled={!card?.present || busy} onClick={confirmFormat}>
          {busy ? "Formatting…" : "Format SD Card"}
        </ButtonItem>
      </PanelSectionRow>
      {status ? <Field label="" description={status} /> : null}
    </PanelSection>
  );
}

function FexSection({ config, setConfig }: { config: Config; setConfig: Dispatch<SetStateAction<Config | null>> }) {
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

  return (
    <PanelSection title="GAME TWEAKS">
      <SelectEdit label="Game" value={game?.appid || ""} options={editTargetOptions(config)} onChange={setSelectedGame} />
      <Field label="" description="Changes apply on next game launch" />
      {!editingDefault ? <ToggleField label="Use Per-Game Settings" checked={perGameEnabled} onChange={setPerGameEnabled} /> : null}
      {editingDefault || perGameEnabled ? (
        <>
          <SelectEdit label="FEX Preset" value={fexValue} options={fexOptions} onChange={(id) => patchSettings({ fexProfile: id })} />
          <SelectEdit label="Audio Buffer" value={audioValue} options={audioLatencyOptions} onChange={(id) => patchSettings({ audioLatency: id })} />
        </>
      ) : null}
    </PanelSection>
  );
}
