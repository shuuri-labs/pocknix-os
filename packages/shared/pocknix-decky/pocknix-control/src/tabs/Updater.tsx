import { ButtonItem, ConfirmModal, Field, PanelSection, PanelSectionRow, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { checkUpdates, rebootSystem, snapshotStatus, startRollback, startUpdate, updateStatus } from "../backend";
import type { SnapshotStatus, UpdateInfo, UpdateStatus } from "../types";

const SHOWN_UPDATES = 8;

const gib = (bytes: number) => (bytes / 1024 ** 3).toFixed(1);

// snapshot metadata stores ISO-8601 UTC; show local DD/MM/YYYY HH:MM
const fmtDate = (iso: string) => {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getDate())}-${p(d.getMonth() + 1)}-${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
};

export function Updater() {
  const [updates, setUpdates] = useState<UpdateInfo[] | null>(null);
  const [checking, setChecking] = useState(false);
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [snap, setSnap] = useState<SnapshotStatus | null>(null);
  const [rollingBack, setRollingBack] = useState(false);
  const [rollbackDone, setRollbackDone] = useState(false);
  const [error, setError] = useState("");
  const [rollbackError, setRollbackError] = useState("");
  const busyRef = useRef(false);
  const running = !!status?.running;
  busyRef.current = checking || running || rollingBack;

  const refreshSnap = () => snapshotStatus().then(setSnap).catch(() => {});

  // Re-attach to an update that survived a QAM close (or a Steam restart).
  useEffect(() => {
    let cancelled = false;
    updateStatus()
      .then((next) => {
        if (!cancelled && (next.running || next.exitCode !== null)) setStatus(next);
      })
      .catch(() => {});
    refreshSnap();
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
        if (!next.running) {
          if (next.exitCode === 0) setUpdates([]);
          refreshSnap(); // a finished transaction changes snapshots + reboot-required
        }
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

  const lastSnapshot = snap?.supported && snap.snapshots.length > 0 ? snap.snapshots[snap.snapshots.length - 1] : null;
  // Already rolled back onto the latest snapshot: another rollback would be a no-op,
  // so hide the button until the next update (which clears the marker + snapshots anew).
  const onLastSnapshot = !!(snap?.rolledBack && lastSnapshot && snap.rolledBack.fromSnapshot === lastSnapshot.id);

  const rollBack = async () => {
    if (busyRef.current || !lastSnapshot) return;
    setRollbackError("");
    setRollingBack(true);
    try {
      setSnap(await startRollback(lastSnapshot.id));
      setRollbackDone(true);
    } catch (err) {
      setRollbackError(String(err));
    } finally {
      setRollingBack(false);
    }
  };
  const confirmRollback = () => {
    if (!lastSnapshot) return;
    showModal(
      <ConfirmModal
        strTitle="Roll Back Last Update"
        strDescription={
          `Restores the system to before the update of ${fmtDate(lastSnapshot.created)}` +
          (lastSnapshot.targets ? ` (${lastSnapshot.targets})` : "") +
          `. Games, saves and settings are kept.` +
          (lastSnapshot.kernel ? " The previous kernel is restored too." : "") +
          ` Reboot after it completes.`
        }
        strOKButtonText="Roll Back"
        onOK={rollBack}
      />
    );
  };
  const reboot = () => rebootSystem().catch((err) => setError(String(err)));

  const finished = !running && status?.exitCode !== null && status?.exitCode !== undefined;
  const summary = updates === null
    ? "Not checked yet"
    : updates.length === 0
      ? "System is up to date"
      : `${updates.length} update${updates.length === 1 ? "" : "s"} available`;

  return (
    <>
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
          <ButtonItem layout="below" disabled={busyRef.current} onClick={check}>
            {checking ? "Checking…" : "Check for Updates"}
          </ButtonItem>
        </PanelSectionRow>
        {!running && updates && updates.length > 0 ? (
          <PanelSectionRow>
            <ButtonItem layout="below" disabled={busyRef.current} onClick={confirmStart}>Install Updates</ButtonItem>
          </PanelSectionRow>
        ) : null}
        {running ? <Field label="Updating…" description="Safe to close this menu. Do not power off." /> : null}
        {finished ? (
          <Field
            label={status!.exitCode === 0 ? "Update complete" : `Update failed (code ${status!.exitCode})`}
            description={status!.exitCode === 0 ? "Restart to finish applying updates." : "See the log below."}
          />
        ) : null}
        {finished && status!.exitCode === 0 ? (
          <PanelSectionRow>
            <ButtonItem layout="below" onClick={reboot}>Restart Now</ButtonItem>
          </PanelSectionRow>
        ) : null}
        {(running || (finished && status!.exitCode !== 0)) && status?.log ? (
          <div className="pocknix-note pocknix-log">{status.log}</div>
        ) : null}
        {error ? <Field label="Error" description={error} /> : null}
      </PanelSection>
      {snap?.supported ? (
        <PanelSection title="ROLLBACK">
          {snap.rolledBack && !rollbackDone ? (
            <Field
              label="System was rolled back"
              description={`Restored from snapshot ${snap.rolledBack.fromSnapshot} (${fmtDate(snap.rolledBack.ts)}).${onLastSnapshot ? " Rollback will be available again after the next update." : ""}`}
            />
          ) : null}
          {rollbackDone ? (
            <>
              <Field label="Rolled back" description="Reboot to finish switching to the restored system." />
              <PanelSectionRow>
                <ButtonItem layout="below" onClick={reboot}>Reboot Now</ButtonItem>
              </PanelSectionRow>
            </>
          ) : onLastSnapshot ? null : lastSnapshot ? (
            <>
              <Field label="Last snapshot" description={`${fmtDate(lastSnapshot.created)}${lastSnapshot.targets ? ` — ${lastSnapshot.targets}` : ""}`} />
              <PanelSectionRow>
                <ButtonItem layout="below" disabled={busyRef.current} onClick={confirmRollback}>
                  {rollingBack ? "Rolling back…" : "Roll Back Last Update"}
                </ButtonItem>
              </PanelSectionRow>
            </>
          ) : (
            <Field label="No snapshots yet" description="A snapshot is taken automatically before every update." />
          )}
          {rollbackError ? <Field label="Rollback error" description={rollbackError} /> : null}
          <Field
            label="Storage"
            description={`${gib(snap.freeBytes)} GB free${snap.lowSpace ? " — LOW: snapshots may be skipped" : ""}`}
          />
        </PanelSection>
      ) : null}
    </>
  );
}
