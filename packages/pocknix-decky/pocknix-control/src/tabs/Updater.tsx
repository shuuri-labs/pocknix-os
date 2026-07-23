import { ButtonItem, ConfirmModal, Field, PanelSection, PanelSectionRow, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { checkUpdates, startUpdate, updateStatus } from "../backend";
import type { UpdateInfo, UpdateStatus } from "../types";

const SHOWN_UPDATES = 8;

export function Updater() {
  const [updates, setUpdates] = useState<UpdateInfo[] | null>(null);
  const [checking, setChecking] = useState(false);
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [error, setError] = useState("");
  const busyRef = useRef(false);
  const running = !!status?.running;
  busyRef.current = checking || running;

  // Re-attach to an update that survived a QAM close (or a Steam restart).
  useEffect(() => {
    let cancelled = false;
    updateStatus()
      .then((next) => {
        if (!cancelled && (next.running || next.exitCode !== null)) setStatus(next);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!running) return;
    const timer = window.setInterval(async () => {
      try {
        const next = await updateStatus();
        setStatus(next);
        if (!next.running && next.exitCode === 0) setUpdates([]);
      } catch (err) {
        setError(String(err));
      }
    }, 2000);
    return () => window.clearInterval(timer);
  }, [running]);

  const check = async () => {
    if (busyRef.current) return;
    setChecking(true);
    setError("");
    try {
      setUpdates(await checkUpdates());
    } catch (err) {
      setError(String(err));
    } finally {
      setChecking(false);
    }
  };

  const start = async () => {
    if (busyRef.current) return;
    setError("");
    try {
      setStatus(await startUpdate());
    } catch (err) {
      setError(String(err));
    }
  };
  const confirmStart = () =>
    showModal(
      <ConfirmModal
        strTitle="Install Updates"
        strDescription="Downloads and installs all available system updates. Keep the device powered; a running game may stutter. Restart after it finishes."
        strOKButtonText="Install"
        onOK={start}
      />
    );

  const finished = !running && status?.exitCode !== null && status?.exitCode !== undefined;
  const summary = updates === null
    ? "Not checked yet"
    : updates.length === 0
      ? "System is up to date"
      : `${updates.length} update${updates.length === 1 ? "" : "s"} available`;

  return (
    <PanelSection title="SYSTEM UPDATES">
      {!running ? <Field label="Status" description={summary} /> : null}
      {!running && updates && updates.length > 0 ? (
        <div className="pocknix-note">
          {updates.slice(0, SHOWN_UPDATES).map((update) => (
            <div key={update.name}>{`${update.name} ${update.current} → ${update.latest}`}</div>
          ))}
          {updates.length > SHOWN_UPDATES ? <div>{`… and ${updates.length - SHOWN_UPDATES} more`}</div> : null}
        </div>
      ) : null}
      <PanelSectionRow>
        <ButtonItem layout="below" disabled={checking || running} onClick={check}>
          {checking ? "Checking…" : "Check for Updates"}
        </ButtonItem>
      </PanelSectionRow>
      {!running && updates && updates.length > 0 ? (
        <PanelSectionRow>
          <ButtonItem layout="below" onClick={confirmStart}>Install Updates</ButtonItem>
        </PanelSectionRow>
      ) : null}
      {running ? <Field label="Updating…" description="Safe to close this menu. Do not power off." /> : null}
      {finished ? (
        <Field
          label={status!.exitCode === 0 ? "Update complete" : `Update failed (code ${status!.exitCode})`}
          description={status!.exitCode === 0 ? "Restart to finish applying updates." : "See the log below."}
        />
      ) : null}
      {(running || (finished && status!.exitCode !== 0)) && status?.log ? (
        <div className="pocknix-note pocknix-log">{status.log}</div>
      ) : null}
      {error ? <Field label="Error" description={error} /> : null}
    </PanelSection>
  );
}
