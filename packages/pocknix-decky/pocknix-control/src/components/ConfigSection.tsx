import { openFilePicker, toaster } from "@decky/api";
import { ButtonItem, ConfirmModal, PanelSection, PanelSectionRow, TextField, showModal } from "@decky/ui";
import { useState } from "react";
import { applyConfig, configDir, exportConfig, getConfig, readConfig } from "../backend";
import { availableCompatTools, resolveCompatTool, setCompatTool } from "../lib/compat";
import { fexSteamString, syncFexLaunchOption } from "../lib/launchOptions";
import { SelectEdit } from "./widgets";
import type { ConfigPreview } from "../types";

function ExportNameModal({ game, base, onDone, closeModal }: {
  game: { appid: string; name: string };
  base: string;
  onDone: (path: string) => void;
  closeModal?: () => void;
}) {
  const [value, setValue] = useState(base);
  const [busy, setBusy] = useState(false);
  const overwriting = value.trim() === base;
  const submit = async () => {
    if (busy || !value.trim()) return;
    setBusy(true);
    try {
      const result = await exportConfig(game.appid, game.name, value.trim(), true);
      onDone(result.path);
    } catch (error) {
      toaster.toast({ title: "Export failed", body: String(error) });
    }
    closeModal?.();
  };
  return (
    <ConfirmModal
      strTitle="Config Already Exists"
      strDescription={`${base}.pocknix.json exists. Change the name to save a new config (e.g. ${base}-2 or ${base}-fast), or keep it to overwrite.`}
      strOKButtonText={busy ? "Saving…" : overwriting ? "Overwrite" : "Save New"}
      bOKDisabled={busy || !value.trim()}
      onCancel={() => closeModal?.()}
      onOK={submit}
    >
      <TextField label="Name" value={value} disabled={busy} onChange={(event) => setValue(event.target.value)} />
    </ConfirmModal>
  );
}

function ImportModal({ path, preview, game, onDone, closeModal }: {
  path: string;
  preview: ConfigPreview;
  game: { appid: string; name: string };
  onDone: () => void;
  closeModal?: () => void;
}) {
  const profiles = preview.games;
  const [source, setSource] = useState(profiles[0]?.appid || "");
  const [busy, setBusy] = useState(false);
  const from = [preview.device, preview.exported].filter(Boolean).join(", ");
  const profileOptions = profiles.map((profile) => ({ data: profile.appid, label: profile.name || profile.appid }));
  const submit = async () => {
    if (busy || !source) return;
    setBusy(true);
    try {
      const result = await applyConfig(path, source, game.appid, game.name);
      try {
        const cfg = await getConfig();
        const profile = result.enabled ? String(result.fexProfile || cfg.tweaks.global.fexProfile || "") : "";
        await syncFexLaunchOption(game.appid, fexSteamString(profile, cfg.fexProfiles));
      } catch (error) {
      }
      if (result.protonTool) {
        const tools = await availableCompatTools(game.appid);
        const resolved = resolveCompatTool(result.protonTool, tools);
        if (resolved.tool) {
          setCompatTool(game.appid, resolved.tool);
          if (resolved.fallback) {
            toaster.toast({ title: "Proton fallback", body: `${result.protonTool} not available, using ${resolved.tool}` });
          }
        } else {
          toaster.toast({ title: "Proton pick skipped", body: `${result.protonTool} not available here` });
        }
      }
      toaster.toast({ title: "Config applied", body: game.name || game.appid });
    } catch (error) {
      toaster.toast({ title: "Import failed", body: String(error) });
    }
    closeModal?.();
    onDone();
  };
  return (
    <ConfirmModal
      strTitle="Import Game Config"
      strDescription={(from ? `Exported from ${from}. ` : "") + `Settings for ${game.name || game.appid} will be overwritten.`}
      strOKButtonText={busy ? "Applying…" : "Apply"}
      bOKDisabled={busy || !source}
      onCancel={() => closeModal?.()}
      onOK={submit}
    >
      {profiles.length > 1 ? (
        <SelectEdit label="Profile" value={source} options={profileOptions} onChange={(id) => setSource(String(id))} />
      ) : (
        <div className="pocknix-note">Profile: {profiles[0]?.name || profiles[0]?.appid}</div>
      )}
    </ConfirmModal>
  );
}

/** Per-game config export/import; rendered only when a game's per-game settings are enabled. */
export function ConfigSection({ game, reload }: {
  game: { appid: string; name: string };
  reload: () => void;
}) {
  const doExport = async () => {
    try {
      const result = await exportConfig(game.appid, game.name || "", "", false);
      if (result.exists) {
        showModal(
          <ExportNameModal
            game={{ appid: game.appid, name: game.name || "" }}
            base={result.base}
            onDone={(path) => toaster.toast({ title: "Game config exported", body: path })}
          />,
        );
        return;
      }
      toaster.toast({ title: "Game config exported", body: result.path });
    } catch (error) {
      toaster.toast({ title: "Export failed", body: String(error) });
    }
  };
  const doImport = async () => {
    let path = "";
    try {
      const dir = await configDir().catch(() => "/home/deck");
      // 0 = FileSelectionType.FILE (same const-enum note as AddGame).
      const picked = await openFilePicker(0, dir, true, true);
      path = picked?.path || "";
    } catch (error) {
      return; // picker closed without a selection
    }
    if (!path) return;
    try {
      const preview = await readConfig(path);
      showModal(<ImportModal path={path} preview={preview} game={game} onDone={reload} />);
    } catch (error) {
      toaster.toast({ title: "Import failed", body: String(error) });
    }
  };
  return (
    <PanelSection title="CONFIG">
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={doExport}>Export Game Config</ButtonItem>
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={doImport}>Import Game Config</ButtonItem>
      </PanelSectionRow>
      <div className="pocknix-note">Per-game tweaks and Proton pick; fan settings and defaults stay local</div>
    </PanelSection>
  );
}
