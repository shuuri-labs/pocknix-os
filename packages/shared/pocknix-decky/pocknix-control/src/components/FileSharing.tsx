import { ButtonItem, ConfirmModal, Field, PanelSection, PanelSectionRow, ToggleField, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { installSamba, setShare, shareStatus } from "../backend";
import type { ShareStatus } from "../types";

// The share is guest-writable and covers the whole home folder, so the trade is spelled out
// rather than buried: same warning the Pocknix Tools menu shows before it flips the switch.
function ShareConfirmModal({ onConfirm, closeModal }: { onConfirm: () => Promise<void>; closeModal?: () => void }) {
  const [running, setRunning] = useState(false);
  const runningRef = useRef(false);
  runningRef.current = running;
  const start = async () => {
    if (runningRef.current) return;
    setRunning(true);
    await onConfirm();
    closeModal?.();
  };
  return (
    <ConfirmModal
      strTitle="Share Files Over The Network"
      strDescription={
        running
          ? "Starting…"
          : "Anyone on the same network can read and write every file in your home folder - games, saves and emulator settings, but also your Steam login and SSH keys. There is no password. Only turn this on at home."
      }
      strOKButtonText={running ? "Starting…" : "Turn On Sharing"}
      bDestructiveWarning={true}
      bOKDisabled={running}
      bCancelDisabled={running}
      bDisableBackgroundDismiss={true}
      onCancel={() => {
        if (!runningRef.current) closeModal?.();
      }}
      onOK={start}
    />
  );
}

export function FileSharing() {
  const [share, setShareState] = useState<ShareStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;

  useEffect(() => {
    let cancelled = false;
    const refresh = async () => {
      if (busyRef.current) return;
      try {
        const next = await shareStatus();
        if (!cancelled && !busyRef.current) setShareState(next);
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

  const run = async (action: () => Promise<ShareStatus>) => {
    if (busyRef.current) return;
    setBusy(true);
    setStatus("");
    try {
      setShareState(await action());
    } catch (error) {
      setStatus(String(error));
    } finally {
      setBusy(false);
    }
  };

  const summary = () => {
    if (status) return status;
    if (!share) return "Checking…";
    if (!share.installed) return "Samba is not installed (7.4 MB download)";
    if (share.on) return "On - open smb://pocknix.local and connect as Guest";
    return "Off - your home folder is not shared";
  };

  return (
    <PanelSection title="FILE SHARING">
      <Field label="Network share" description={summary()} />
      {share && !share.installed ? (
        <PanelSectionRow>
          <ButtonItem layout="below" disabled={busy} onClick={() => run(installSamba)}>
            {busy ? "Installing…" : "Install Samba"}
          </ButtonItem>
        </PanelSectionRow>
      ) : (
        <PanelSectionRow>
          <ToggleField
            label="Share my home folder"
            description="Drag files straight onto the device from another computer"
            checked={!!share?.on}
            disabled={busy || !share?.installed}
            onChange={(on: boolean) => {
              if (busyRef.current) return;
              if (on) showModal(<ShareConfirmModal onConfirm={() => run(() => setShare(true))} />);
              else run(() => setShare(false));
            }}
          />
        </PanelSectionRow>
      )}
    </PanelSection>
  );
}
