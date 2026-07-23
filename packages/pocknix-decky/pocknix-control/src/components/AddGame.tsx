import { openFilePicker, toaster } from "@decky/api";
import { ButtonItem, ConfirmModal, PanelSection, PanelSectionRow, TextField, ToggleField, showModal } from "@decky/ui";
import { useState } from "react";
import { addShortcut, defaultShortcutName, isWindowsExe } from "../lib/shortcuts";

function AddGameModal({ path, closeModal }: { path: string; closeModal?: () => void }) {
  const [name, setName] = useState(defaultShortcutName(path));
  const [proton, setProton] = useState(isWindowsExe(path));
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    if (busy || !name.trim()) return;
    setBusy(true);
    try {
      await addShortcut(name.trim(), path, proton);
      toaster.toast({ title: "Added to library", body: name.trim() });
      closeModal?.();
    } catch (error) {
      toaster.toast({ title: "Could not add game", body: String(error) });
      setBusy(false);
    }
  };
  return (
    <ConfirmModal
      strTitle="Add Non-Steam Game"
      strDescription={path}
      strOKButtonText={busy ? "Adding…" : "Add to Library"}
      bOKDisabled={busy || !name.trim()}
      onCancel={() => closeModal?.()}
      onOK={submit}
    >
      <TextField label="Name" value={name} disabled={busy} onChange={(event) => setName(event.target.value)} />
      <ToggleField
        label="Launch with Proton"
        description="Needed for Windows games (.exe)"
        checked={proton}
        disabled={busy}
        onChange={setProton}
      />
    </ConfirmModal>
  );
}

export function AddGameSection() {
  const pick = async () => {
    try {
      // 0 = FileSelectionType.FILE (const enum in @decky/api typings, no runtime export).
      const result = await openFilePicker(0, "/home/deck", true, true);
      if (result?.path) showModal(<AddGameModal path={result.path} />);
    } catch (error) {
      // Picker closed without a selection.
    }
  };
  return (
    <PanelSection title="LIBRARY">
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={pick}>Add Non-Steam Game</ButtonItem>
      </PanelSectionRow>
      <div className="pocknix-note">Pick an executable to add it to your Steam library</div>
    </PanelSection>
  );
}
