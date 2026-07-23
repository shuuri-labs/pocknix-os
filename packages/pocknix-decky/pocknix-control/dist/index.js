const manifest = {"name":"Pocknix Control"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const call = api.call;
const toaster = api.toaster;
const openFilePicker = api.openFilePicker;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

const getConfig = () => call("get_config");
const setFanMode = (mode) => call("set_fan_mode", mode);
const setLavdMode = (mode) => call("set_lavd_mode", mode);
const saveTweaks = (data) => call("save_tweaks", data);
const detectSdcard = () => call("detect_sdcard");
const formatSdcard = (label) => call("format_sdcard", label);

function useDebouncedSave(options) {
    const { config, field, snapshot, save, setConfig, onError, delay = 900 } = options;
    const value = config ? config[field] : undefined;
    // Latest unsaved edit; written by the debounce timer or the unmount flush below.
    const pending = SP_REACT.useRef(null);
    const flush = SP_REACT.useCallback(async () => {
        const entry = pending.current;
        if (!entry)
            return;
        pending.current = null;
        try {
            const next = await save(entry.value);
            snapshot.current = JSON.stringify(next[field]);
            setConfig((stored) => {
                if (!stored)
                    return next;
                if (JSON.stringify(stored[field]) !== entry.serialized)
                    return stored;
                return { ...stored, [field]: next[field] };
            });
        }
        catch (error) {
            onError?.(error);
        }
    }, [save, field, snapshot, setConfig, onError]);
    const flushRef = SP_REACT.useRef(flush);
    flushRef.current = flush;
    SP_REACT.useEffect(() => {
        if (!config || !snapshot.current)
            return;
        const current = JSON.stringify(value);
        if (current === snapshot.current) {
            pending.current = null;
            return;
        }
        pending.current = { value, serialized: current };
        const timer = window.setTimeout(() => flushRef.current(), delay);
        return () => window.clearTimeout(timer);
    }, [value]);
    // QAM panels unmount the moment the menu closes. The cleanup above clears the only
    // pending timer, so without this unmount flush any edit made <delay ms before closing
    // was silently dropped (how the first on-device Audio Buffer edit got lost, 2026-07-05).
    SP_REACT.useEffect(() => () => void flushRef.current(), []);
}

function Icon({ path }) {
    return (SP_JSX.jsx("svg", { style: { display: "block" }, width: "20", height: "20", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: "2", strokeLinecap: "round", strokeLinejoin: "round", children: path }));
}
const tabIcons = {
    Games: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("line", { x1: "6", x2: "10", y1: "11", y2: "11" }), SP_JSX.jsx("line", { x1: "8", x2: "8", y1: "9", y2: "13" }), SP_JSX.jsx("line", { x1: "15", x2: "15.01", y1: "12", y2: "12" }), SP_JSX.jsx("line", { x1: "18", x2: "18.01", y1: "10", y2: "10" }), SP_JSX.jsx("path", { d: "M17.32 5H6.68a4 4 0 0 0-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 0 1 9.828 16h4.344a2 2 0 0 1 1.414.586L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.545-.604-6.584-.685-7.258-.007-.05-.011-.1-.017-.151A4 4 0 0 0 17.32 5z" })] }) })),
    Power: (SP_JSX.jsx(Icon, { path: SP_JSX.jsx(SP_JSX.Fragment, { children: SP_JSX.jsx("path", { d: "M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z" }) }) })),
    Storage: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("line", { x1: "22", x2: "2", y1: "12", y2: "12" }), SP_JSX.jsx("path", { d: "M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z" }), SP_JSX.jsx("line", { x1: "6", x2: "6.01", y1: "16", y2: "16" }), SP_JSX.jsx("line", { x1: "10", x2: "10.01", y1: "16", y2: "16" })] }) })),
};

function gameDisplayName(game) {
    if (!game?.appid)
        return "";
    return game.name || `App ${game.appid}`;
}
// The backend lists every appmanifest in steamapps, which includes tools (Proton, Steam Linux
// Runtime, Steamworks Common Redistributables, …). Steam's own appStore overview knows the type
// (app_type 1 = game, 4 = tool); fall back to name patterns when the overview isn't available.
const NON_GAME_NAME = /^(Proton[ 0-9]|Proton (Hotfix|EasyAntiCheat|BattlEye)|Steam Linux Runtime|Steamworks Common)/i;
function isGame(appid, name) {
    try {
        const overview = window.appStore?.GetAppOverviewByAppID?.(Number(appid));
        if (typeof overview?.app_type === "number")
            return overview.app_type !== 4;
    }
    catch (error) {
    }
    return !NON_GAME_NAME.test(name);
}
function availableGames(config) {
    const games = new Map();
    for (const game of config.installedGames || []) {
        if (game?.appid && isGame(String(game.appid), game.name || "")) {
            games.set(String(game.appid), { appid: String(game.appid), name: game.name || `App ${game.appid}` });
        }
    }
    // Games with saved tweaks stay listed even if the type lookup would hide them —
    // existing per-game config must remain reachable.
    for (const [appid, game] of Object.entries(config.tweaks?.games || {})) {
        if (game && typeof game === "object")
            games.set(String(appid), { appid: String(appid), name: game.name || games.get(String(appid))?.name || `App ${appid}` });
    }
    return Array.from(games.values()).sort((a, b) => gameDisplayName(a).localeCompare(gameDisplayName(b)));
}
function editTargetOptions(config) {
    return [
        { data: "", label: "Default" },
        ...availableGames(config).map((game) => ({ data: game.appid, label: gameDisplayName(game) })),
    ];
}
function currentGame() {
    const running = DFL.Router?.MainRunningApp || window.Router?.MainRunningApp;
    const appid = running?.appid;
    if (!appid)
        return null;
    const id = String(appid);
    let name = running?.display_name || running?.displayName || "";
    try {
        const details = window.appDetailsStore?.GetAppDetails?.(Number(id));
        name = details?.strDisplayName || details?.strName || details?.name || name;
    }
    catch (error) {
    }
    return { appid: id, name: name || `App ${id}` };
}

const styles = `
      .pocknix-control-tabs {
        height: 95%;
        width: 316px;
        position: fixed;
        margin-top: -12px;
        margin-left: -8px;
        overflow: hidden;
      }
      .pocknix-control-tabs > div > div:first-child::before {
        background: #0D141C;
        box-shadow: none;
        backdrop-filter: none;
      }
      .pocknix-control-tabs [role="tabpanel"] {
        padding-left: 0 !important;
        padding-right: 0 !important;
      }
      .pocknix-control-tabs .pocknix-control-tab-content {
        padding-bottom: 24px;
      }
      .pocknix-control-tabs .pocknix-note {
        box-sizing: border-box;
        width: 100%;
        padding: 8px 16px 8px;
        font-size: 12px;
        line-height: 16px;
        opacity: 0.62;
        text-align: left;
        justify-content: flex-start;
        align-self: stretch;
      }
    `;

// Non-Steam shortcut creation via SteamClient.Apps. The Steam file browser can't open a
// new window under the Plasma Mobile X11 session, so Decky's in-UI file picker plus this
// module replace the stock "Add a Non-Steam Game" flow.
const WINDOWS_EXE = /\.(exe|bat|msi)$/i;
// Constant internal name from proton-cachyos' compatibilitytool.vdf; survives version bumps.
const PROTON_TOOL = "proton-cachyos";
function isWindowsExe(path) {
    return WINDOWS_EXE.test(path);
}
function defaultShortcutName(path) {
    const base = path.split("/").pop() || path;
    const cleaned = base.replace(/\.[^.]+$/, "").replace(/_+/g, " ").trim();
    return cleaned || base;
}
const quote = (value) => `"${value.replace(/"/g, '\\"')}"`;
async function addShortcut(name, path, useProton) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.AddShortcut)
        throw new Error("Steam shortcut API unavailable");
    const dir = path.slice(0, path.lastIndexOf("/") + 1) || "/";
    const appId = await apps.AddShortcut(name, path, "", "");
    if (typeof appId !== "number" || !appId)
        throw new Error("Steam refused to create the shortcut");
    apps.SetShortcutName?.(appId, name);
    apps.SetShortcutExe?.(appId, quote(path));
    apps.SetShortcutStartDir?.(appId, quote(dir));
    if (useProton)
        apps.SpecifyCompatTool?.(appId, PROTON_TOOL);
    return appId;
}

function AddGameModal({ path, closeModal }) {
    const [name, setName] = SP_REACT.useState(defaultShortcutName(path));
    const [proton, setProton] = SP_REACT.useState(isWindowsExe(path));
    const [busy, setBusy] = SP_REACT.useState(false);
    const submit = async () => {
        if (busy || !name.trim())
            return;
        setBusy(true);
        try {
            await addShortcut(name.trim(), path, proton);
            toaster.toast({ title: "Added to library", body: name.trim() });
            closeModal?.();
        }
        catch (error) {
            toaster.toast({ title: "Could not add game", body: String(error) });
            setBusy(false);
        }
    };
    return (SP_JSX.jsxs(DFL.ConfirmModal, { strTitle: "Add Non-Steam Game", strDescription: path, strOKButtonText: busy ? "Adding…" : "Add to Library", bOKDisabled: busy || !name.trim(), onCancel: () => closeModal?.(), onOK: submit, children: [SP_JSX.jsx(DFL.TextField, { label: "Name", value: name, disabled: busy, onChange: (event) => setName(event.target.value) }), SP_JSX.jsx(DFL.ToggleField, { label: "Launch with Proton", description: "Needed for Windows games (.exe)", checked: proton, disabled: busy, onChange: setProton })] }));
}
function AddGameSection() {
    const pick = async () => {
        try {
            // 0 = FileSelectionType.FILE (const enum in @decky/api typings, no runtime export).
            const result = await openFilePicker(0, "/home/deck", true, true);
            if (result?.path)
                DFL.showModal(SP_JSX.jsx(AddGameModal, { path: result.path }));
        }
        catch (error) {
            // Picker closed without a selection.
        }
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: "LIBRARY", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: pick, children: "Add Non-Steam Game" }) }), SP_JSX.jsx("div", { className: "pocknix-note", children: "Pick an executable to add it to your Steam library" })] }));
}

function SelectEdit({ label, value, options, onChange }) {
    const rgOptions = options.map((option) => (typeof option === "string" ? { data: option, label: option } : option));
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: label === undefined ? (SP_JSX.jsx(DFL.Dropdown, { selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) : (SP_JSX.jsx(DFL.DropdownItem, { label: label, selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) }));
}

function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}

// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default. 60 measured ~10x fewer underruns.
const audioLatencyOptions = [
    { data: "", label: "Game default" },
    { data: "60", label: "60 ms" },
    { data: "90", label: "90 ms" },
    { data: "120", label: "120 ms" },
];
function Games({ config, setConfig }) {
    const runtimeGame = config.game;
    const games = availableGames(config);
    const game = config.selectedGame || runtimeGame || null;
    const tweaks = config.tweaks;
    const gameSettings = game?.appid ? tweaks.games[game.appid] || {} : {};
    const editingDefault = !game?.appid;
    const perGameEnabled = !!(game?.appid && gameSettings.enabled === true);
    const values = editingDefault || !perGameEnabled ? tweaks.global : { ...tweaks.global, ...gameSettings };
    const patchSettings = (patch) => {
        setConfig((current) => {
            if (!current)
                return current;
            const next = clone(current);
            if (editingDefault) {
                Object.assign(next.tweaks.global, patch);
            }
            else if (perGameEnabled) {
                const existing = next.tweaks.games[game.appid] || {};
                next.tweaks.games[game.appid] = { ...existing, enabled: true, name: game.name || "", ...patch };
            }
            return next;
        });
    };
    const setPerGameEnabled = (enabled) => {
        if (!game?.appid)
            return;
        setConfig((current) => {
            if (!current)
                return current;
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
    const setSelectedGame = (appid) => {
        const id = String(appid);
        if (!id) {
            setConfig((current) => (current ? { ...current, selectedGame: { appid: "", name: "Default" } } : current));
            return;
        }
        const saved = games.find((candidate) => candidate.appid === id);
        setConfig((current) => (current ? { ...current, selectedGame: saved || null } : current));
    };
    const presets = config.fexProfiles || {};
    const storedProfile = values.fexProfile;
    const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
    const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
    const storedLatency = String(values.audioLatency ?? "");
    const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "GAME TWEAKS", children: [SP_JSX.jsx(SelectEdit, { label: "Game", value: game?.appid || "", options: editTargetOptions(config), onChange: setSelectedGame }), SP_JSX.jsx("div", { className: "pocknix-note", children: "Changes apply on next game launch" }), !editingDefault ? SP_JSX.jsx(DFL.ToggleField, { label: "Use Per-Game Settings", checked: perGameEnabled, onChange: setPerGameEnabled }) : null, editingDefault || perGameEnabled ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: "FEX Preset", value: fexValue, options: fexOptions, onChange: (id) => patchSettings({ fexProfile: id }) }), SP_JSX.jsx(SelectEdit, { label: "Audio Buffer", value: audioValue, options: audioLatencyOptions, onChange: (id) => patchSettings({ audioLatency: id }) })] })) : null] }), SP_JSX.jsx(AddGameSection, {})] }));
}

const fanOptions = [
    { data: "quiet", label: "Quiet" },
    { data: "moderate", label: "Moderate" },
    { data: "performance", label: "Performance" },
];
const lavdOptions = [
    { data: "autopilot", label: "Autopilot" },
    { data: "performance", label: "Performance" },
];
function Power({ config, setConfig, reload }) {
    const applyMode = async (setter, mode) => {
        try {
            const next = await setter(mode);
            setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
        }
        catch (error) {
            reload();
        }
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: "PERFORMANCE", children: [SP_JSX.jsx(SelectEdit, { label: "Fan Curve", value: config.fanMode, options: fanOptions, onChange: (mode) => applyMode(setFanMode, mode) }), SP_JSX.jsx(SelectEdit, { label: "CPU Scheduler", value: config.lavdMode, options: lavdOptions, onChange: (mode) => applyMode(setLavdMode, mode) })] }));
}

function cardSummary(card) {
    if (!card)
        return "Checking…";
    if (!card.present)
        return "No SD card detected";
    const size = card.sizeBytes ? `${(card.sizeBytes / 1e9).toFixed(1)} GB` : "";
    const state = card.fstype === "ext4" ? (card.mountpoint ? "mounted" : "") : "not formatted for Steam";
    return [card.label || "unlabeled", size, card.fstype || "no filesystem", state].filter(Boolean).join(" · ");
}
// showModal injects closeModal into this wrapper. We deliberately do NOT forward it to
// ConfirmModal: its internal OK handler would close the dialog immediately, and we want
// it held open (with the confirm button greyed out) until the format finishes.
function FormatConfirmModal({ summary, onConfirm, closeModal }) {
    const [text, setText] = SP_REACT.useState("");
    const [running, setRunning] = SP_REACT.useState(false);
    const armedRef = SP_REACT.useRef(false);
    const runningRef = SP_REACT.useRef(false);
    armedRef.current = text.trim().toLowerCase() === "format";
    runningRef.current = running;
    const start = async () => {
        if (!armedRef.current || runningRef.current)
            return;
        setRunning(true);
        await onConfirm();
        closeModal?.();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: "Format SD Card", strDescription: running
            ? "Formatting… This can take a minute. Do not remove the card."
            : `This erases ALL data on the card (${summary}) and formats it for Steam. Type "format" and press Enter to confirm.`, strOKButtonText: running ? "Formatting…" : "Erase and Format", bDestructiveWarning: true, bOKDisabled: !armedRef.current || running, bCancelDisabled: running, bDisableBackgroundDismiss: true, bHideCloseIcon: true, onCancel: () => {
            if (!runningRef.current)
                closeModal?.();
        }, onOK: start, children: !running ? (SP_JSX.jsx(DFL.TextField, { value: text, focusOnMount: true, onChange: (event) => setText(event.target.value), onKeyDown: (event) => {
                if (event.key === "Enter")
                    start();
            } })) : null }));
}
function Storage() {
    const [card, setCard] = SP_REACT.useState(null);
    const [label, setLabel] = SP_REACT.useState("SDCARD");
    const [busy, setBusy] = SP_REACT.useState(false);
    const [status, setStatus] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    busyRef.current = busy;
    SP_REACT.useEffect(() => {
        let cancelled = false;
        const refresh = async () => {
            if (busyRef.current)
                return;
            try {
                const next = await detectSdcard();
                if (!cancelled && !busyRef.current)
                    setCard(next);
            }
            catch (error) {
                if (!cancelled)
                    setStatus(String(error));
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
        if (busyRef.current)
            return;
        setBusy(true);
        setStatus("");
        try {
            const next = await formatSdcard(label);
            setCard(next);
        }
        catch (error) {
            setStatus(String(error));
        }
        finally {
            setBusy(false);
        }
    };
    const confirmFormat = () => DFL.showModal(SP_JSX.jsx(FormatConfirmModal, { summary: cardSummary(card), onConfirm: runFormat }));
    return (SP_JSX.jsxs(DFL.PanelSection, { title: "SD CARD", children: [SP_JSX.jsx(DFL.Field, { label: "Card", description: cardSummary(card) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.TextField, { label: "Label", value: label, disabled: busy, onChange: (event) => setLabel(event.target.value.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 16)) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: !card?.present || busy, onClick: confirmFormat, children: busy ? "Formatting…" : "Format SD Card" }) }), status ? SP_JSX.jsx(DFL.Field, { label: "", description: status }) : null] }));
}

function Content() {
    const [tab, setTab] = SP_REACT.useState("Games");
    const [config, setConfig] = SP_REACT.useState(null);
    const [message, setMessage] = SP_REACT.useState("Loading");
    const savedTweaksSnapshot = SP_REACT.useRef("");
    const load = SP_REACT.useCallback(async () => {
        try {
            const next = await getConfig();
            next.game = currentGame();
            next.selectedGame = next.game || null;
            savedTweaksSnapshot.current = JSON.stringify(next.tweaks);
            setConfig(next);
        }
        catch (error) {
            setMessage(String(error));
        }
    }, []);
    SP_REACT.useEffect(() => {
        load();
    }, [load]);
    // Track the running game so opening the QAM mid-game edits that game's profile.
    SP_REACT.useEffect(() => {
        if (!config)
            return;
        let cancelled = false;
        const refreshRuntime = () => {
            try {
                const runtimeGame = currentGame();
                if (cancelled)
                    return;
                setConfig((current) => {
                    if (!current)
                        return current;
                    if ((current.game?.appid || "") === (runtimeGame?.appid || "") && (current.game?.name || "") === (runtimeGame?.name || ""))
                        return current;
                    return { ...current, game: runtimeGame };
                });
            }
            catch (error) {
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
    if (!config)
        return SP_JSX.jsx(DFL.PanelSection, { title: "Pocknix Control", children: SP_JSX.jsx(DFL.Field, { label: message }) });
    const tabContent = (content) => (SP_JSX.jsx("div", { className: "pocknix-control-tab-content", children: content }));
    return (SP_JSX.jsxs("div", { className: "pocknix-control-tabs", children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsx(DFL.Tabs, { activeTab: tab, onShowTab: setTab, tabs: [
                    { id: "Games", title: tabIcons.Games, content: tabContent(SP_JSX.jsx(Games, { config: config, setConfig: setConfig })) },
                    { id: "Power", title: tabIcons.Power, content: tabContent(SP_JSX.jsx(Power, { config: config, setConfig: setConfig, reload: load })) },
                    { id: "Storage", title: tabIcons.Storage, content: tabContent(SP_JSX.jsx(Storage, {})) },
                ] })] }));
}

var index = definePlugin(() => ({
    name: "Pocknix Control",
    content: SP_JSX.jsx(Content, {}),
    icon: SP_JSX.jsx("div", { style: { fontWeight: 700 }, children: "P" }),
    alwaysRender: true,
}));

export { index as default };
//# sourceMappingURL=index.js.map
