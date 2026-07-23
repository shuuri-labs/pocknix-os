import { ButtonItem, ConfirmModal, Field, PanelSection, PanelSectionRow, TextField, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { detectSdcard, formatSdcard } from "../backend";
import type { SdcardInfo } from "../types";

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

export function Storage() {
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
