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
const exportConfig = (appid, name, basename, allowOverwrite) => call("export_config", appid, name, basename, allowOverwrite);
const configDir = () => call("config_dir");
const readConfig = (path) => call("read_config", path);
const applyConfig = (path, sourceAppid, targetAppid, targetName) => call("apply_config", path, sourceAppid, targetAppid, targetName);
const setLed = (side, r, g, b, brightness) => call("set_led", side, r, g, b, brightness);
const setLedLinked = (linked) => call("set_led_linked", linked);
const setLedEnabled = (enabled) => call("set_led_enabled", enabled);
const setLedSides = (sides) => call("set_led_sides", sides);
const setBootPulse = (enabled) => call("set_boot_pulse", enabled);
const detectSdcard = () => call("detect_sdcard");
const formatSdcard = (label) => call("format_sdcard", label);
const checkUpdates = () => call("check_updates");
const startUpdate = () => call("start_update");
const updateStatus = () => call("update_status");
const snapshotStatus = () => call("snapshot_status");
const startRollback = (id) => call("start_rollback", id);
const rebootSystem = () => call("reboot_system");

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
    Library: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("rect", { width: "18", height: "18", x: "3", y: "3", rx: "2" }), SP_JSX.jsx("path", { d: "M8 12h8" }), SP_JSX.jsx("path", { d: "M12 8v8" })] }) })),
    Updater: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("path", { d: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" }), SP_JSX.jsx("polyline", { points: "7 10 12 15 17 10" }), SP_JSX.jsx("line", { x1: "12", x2: "12", y1: "15", y2: "3" })] }) })),
    Storage: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("line", { x1: "22", x2: "2", y1: "12", y2: "12" }), SP_JSX.jsx("path", { d: "M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z" }), SP_JSX.jsx("line", { x1: "6", x2: "6.01", y1: "16", y2: "16" }), SP_JSX.jsx("line", { x1: "10", x2: "10.01", y1: "16", y2: "16" })] }) })),
    Lighting: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("path", { d: "M9 18h6" }), SP_JSX.jsx("path", { d: "M10 22h4" }), SP_JSX.jsx("path", { d: "M15.09 14c.18-.98.65-1.74 1.41-2.5A4.65 4.65 0 0 0 18 8 6 6 0 0 0 6 8c0 1 .23 2.23 1.5 3.5A4.61 4.61 0 0 1 8.91 14" })] }) })),
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
// Non-Steam shortcuts have no appmanifest, so the backend scan can't see them; Steam's
// deckDesktopApps collection holds their appids (unsigned; force with >>> in case a build
// hands out the signed-int32 form) and appStore resolves the names.
function nonSteamShortcuts() {
    try {
        const ids = window.collectionStore?.deckDesktopApps?.apps;
        if (!ids?.values)
            return [];
        const shortcuts = [];
        for (const id of Array.from(ids.values())) {
            const appid = String(Number(id) >>> 0);
            if (!appid || appid === "0")
                continue;
            let name = "";
            try {
                name = window.appStore?.GetAppOverviewByAppID?.(Number(appid))?.display_name || "";
            }
            catch (error) {
            }
            shortcuts.push({ appid, name: name || `App ${appid}`, nonSteam: true });
        }
        return shortcuts;
    }
    catch (error) {
        return [];
    }
}
function availableGames(config) {
    const games = new Map();
    for (const game of config.installedGames || []) {
        if (game?.appid && isGame(String(game.appid), game.name || "")) {
            games.set(String(game.appid), { appid: String(game.appid), name: game.name || `App ${game.appid}` });
        }
    }
    for (const shortcut of nonSteamShortcuts()) {
        games.set(shortcut.appid, shortcut);
    }
    // Games with saved tweaks stay listed even if the lookups above miss them —
    // existing per-game config must remain reachable. Shortcut appids sit above 2^31.
    for (const [appid, game] of Object.entries(config.tweaks?.games || {})) {
        if (game && typeof game === "object" && !games.has(String(appid))) {
            games.set(String(appid), { appid: String(appid), name: game.name || `App ${appid}`, nonSteam: Number(appid) >= 0x80000000 });
        }
    }
    return Array.from(games.values()).sort((a, b) => (a.nonSteam ? 1 : 0) - (b.nonSteam ? 1 : 0) || gameDisplayName(a).localeCompare(gameDisplayName(b)));
}
function editTargetOptions(config) {
    return [
        { data: "", label: "Default" },
        ...availableGames(config).map((game) => ({
            data: game.appid,
            label: game.nonSteam ? `${gameDisplayName(game)} · non-Steam` : gameDisplayName(game),
        })),
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
      .pocknix-control-tabs .pocknix-log {
        font-family: monospace;
        font-size: 10px;
        line-height: 14px;
        word-break: break-all;
        white-space: pre-wrap;
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

// Per-game Proton selection via SteamClient.Apps. This drives the SAME state as Steam's own
// per-game compatibility dropdown (SpecifyCompatTool + app details), so the two UIs stay in
// sync by construction — we never store a shadow copy.
async function availableCompatTools(appid) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.GetAvailableCompatTools)
        return [];
    try {
        const tools = await apps.GetAvailableCompatTools(Number(appid));
        if (!Array.isArray(tools))
            return [];
        return tools
            .map((tool) => ({
            name: String(tool?.strToolName ?? ""),
            label: String(tool?.strDisplayName ?? tool?.strToolName ?? ""),
        }))
            .filter((tool) => tool.name);
    }
    catch {
        return [];
    }
}
/** Live view of the game's current tool; fires again when it changes anywhere (incl. Steam's UI). */
function registerForCompatTool(appid, onChange) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.RegisterForAppDetails)
        return () => { };
    const registration = apps.RegisterForAppDetails(Number(appid), (details) => {
        onChange(String(details?.strCompatToolName ?? ""));
    });
    return () => registration?.unregister?.();
}
function setCompatTool(appid, tool) {
    window.SteamClient?.Apps?.SpecifyCompatTool?.(Number(appid), tool);
}
/** Resolve an imported Proton pick against this device's tools. Unknown ARM-named tools
 *  fall back to the cachy ARM Proton; unknown x86-named ones to a Proton 11. */
function resolveCompatTool(wanted, tools) {
    if (!wanted)
        return { tool: "", fallback: false };
    if (tools.some((tool) => tool.name === wanted))
        return { tool: wanted, fallback: false };
    const haystack = (tool) => `${tool.name} ${tool.label}`;
    const isArm = /arm/i.test(wanted);
    const fallback = isArm
        ? tools.find((tool) => /cachy/i.test(haystack(tool)) && !/x86/i.test(haystack(tool)))
        : tools.find((tool) => /(^|\D)11(\D|$)/.test(haystack(tool)) && !/arm|cachy/i.test(haystack(tool)));
    return { tool: fallback?.name || "", fallback: true };
}

function SelectEdit({ label, value, options, onChange }) {
    const rgOptions = options.map((option) => (typeof option === "string" ? { data: option, label: option } : option));
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: label === undefined ? (SP_JSX.jsx(DFL.Dropdown, { selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) : (SP_JSX.jsx(DFL.DropdownItem, { label: label, selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) }));
}

function ExportNameModal({ game, base, onDone, closeModal }) {
    const [value, setValue] = SP_REACT.useState(base);
    const [busy, setBusy] = SP_REACT.useState(false);
    const overwriting = value.trim() === base;
    const submit = async () => {
        if (busy || !value.trim())
            return;
        setBusy(true);
        try {
            const result = await exportConfig(game.appid, game.name, value.trim(), true);
            onDone(result.path);
        }
        catch (error) {
            toaster.toast({ title: "Export failed", body: String(error) });
        }
        closeModal?.();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: "Config Already Exists", strDescription: `${base}.pocknix.json exists. Change the name to save a new config (e.g. ${base}-2 or ${base}-fast), or keep it to overwrite.`, strOKButtonText: busy ? "Saving…" : overwriting ? "Overwrite" : "Save New", bOKDisabled: busy || !value.trim(), onCancel: () => closeModal?.(), onOK: submit, children: SP_JSX.jsx(DFL.TextField, { label: "Name", value: value, disabled: busy, onChange: (event) => setValue(event.target.value) }) }));
}
function ImportModal({ path, preview, game, onDone, closeModal }) {
    const profiles = preview.games;
    const [source, setSource] = SP_REACT.useState(profiles[0]?.appid || "");
    const [busy, setBusy] = SP_REACT.useState(false);
    const from = [preview.device, preview.exported].filter(Boolean).join(", ");
    const profileOptions = profiles.map((profile) => ({ data: profile.appid, label: profile.name || profile.appid }));
    const submit = async () => {
        if (busy || !source)
            return;
        setBusy(true);
        try {
            const result = await applyConfig(path, source, game.appid, game.name);
            if (result.protonTool) {
                const tools = await availableCompatTools(game.appid);
                const resolved = resolveCompatTool(result.protonTool, tools);
                if (resolved.tool) {
                    setCompatTool(game.appid, resolved.tool);
                    if (resolved.fallback) {
                        toaster.toast({ title: "Proton fallback", body: `${result.protonTool} not available, using ${resolved.tool}` });
                    }
                }
                else {
                    toaster.toast({ title: "Proton pick skipped", body: `${result.protonTool} not available here` });
                }
            }
            toaster.toast({ title: "Config applied", body: game.name || game.appid });
        }
        catch (error) {
            toaster.toast({ title: "Import failed", body: String(error) });
        }
        closeModal?.();
        onDone();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: "Import Game Config", strDescription: (from ? `Exported from ${from}. ` : "") + `Settings for ${game.name || game.appid} will be overwritten.`, strOKButtonText: busy ? "Applying…" : "Apply", bOKDisabled: busy || !source, onCancel: () => closeModal?.(), onOK: submit, children: profiles.length > 1 ? (SP_JSX.jsx(SelectEdit, { label: "Profile", value: source, options: profileOptions, onChange: (id) => setSource(String(id)) })) : (SP_JSX.jsxs("div", { className: "pocknix-note", children: ["Profile: ", profiles[0]?.name || profiles[0]?.appid] })) }));
}
/** Per-game config export/import; rendered only when a game's per-game settings are enabled. */
function ConfigSection({ game, reload }) {
    const doExport = async () => {
        try {
            const result = await exportConfig(game.appid, game.name || "", "", false);
            if (result.exists) {
                DFL.showModal(SP_JSX.jsx(ExportNameModal, { game: { appid: game.appid, name: game.name || "" }, base: result.base, onDone: (path) => toaster.toast({ title: "Game config exported", body: path }) }));
                return;
            }
            toaster.toast({ title: "Game config exported", body: result.path });
        }
        catch (error) {
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
        }
        catch (error) {
            return; // picker closed without a selection
        }
        if (!path)
            return;
        try {
            const preview = await readConfig(path);
            DFL.showModal(SP_JSX.jsx(ImportModal, { path: path, preview: preview, game: game, onDone: reload }));
        }
        catch (error) {
            toaster.toast({ title: "Import failed", body: String(error) });
        }
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: "CONFIG", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: doExport, children: "Export Game Config" }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: doImport, children: "Import Game Config" }) }), SP_JSX.jsx("div", { className: "pocknix-note", children: "Per-game tweaks and Proton pick; fan settings and defaults stay local" })] }));
}

// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default. 60 measured ~10x fewer underruns.
const audioLatencyOptions = [
    { data: "", label: "Game default" },
    { data: "60", label: "60 ms" },
    { data: "90", label: "90 ms" },
    { data: "120", label: "120 ms" },
];
const fanOptions = [
    { data: "quiet", label: "Quiet" },
    { data: "moderate", label: "Moderate" },
    { data: "performance", label: "Performance" },
];
const lavdOptions = [
    { data: "autopilot", label: "Autopilot" },
    { data: "performance", label: "Performance" },
];
const globalChoice = { data: "", label: "Use global" };
function EnvVarsModal({ initial, onSave, closeModal }) {
    const [value, setValue] = SP_REACT.useState(initial);
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: "Environment Variables", strDescription: 'Space-separated KEY=VALUE pairs; quote values with spaces, e.g. DXVK_CONFIG="dxgi.customDeviceDesc = GTX 480". Steam launch options win over these.', strOKButtonText: "Save", onCancel: () => closeModal?.(), onOK: () => {
            onSave(value.trim());
            closeModal?.();
        }, children: SP_JSX.jsx(DFL.TextField, { label: "Variables", value: value, onChange: (event) => setValue(event.target.value) }) }));
}
function EnvVarsButton({ value, onSave }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", description: value ? value : "None set", onClick: () => DFL.showModal(SP_JSX.jsx(EnvVarsModal, { initial: value, onSave: onSave })), children: "Environment Variables" }) }));
}
/** Per-game fan/scheduler overrides ("" = follow the global mode). */
function PerfFields({ values, patch }) {
    const perGameFan = [globalChoice, ...fanOptions];
    const perGameLavd = [globalChoice, ...lavdOptions];
    const fanValue = perGameFan.some((option) => option.data === String(values.fanMode ?? "")) ? String(values.fanMode ?? "") : "";
    const lavdValue = perGameLavd.some((option) => option.data === String(values.lavdMode ?? "")) ? String(values.lavdMode ?? "") : "";
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: "CPU Scheduler", value: lavdValue, options: perGameLavd, onChange: (id) => patch({ lavdMode: id }) }), SP_JSX.jsx(SelectEdit, { label: "Fan Curve", value: fanValue, options: perGameFan, onChange: (id) => patch({ fanMode: id }) })] }));
}
/** The per-game tweak controls, shared by the Games tab and the library context-menu modal. */
function TweakFields({ config, appid, values, patch }) {
    // Proton pick is Steam's own per-game compat setting (see lib/compat.ts) — read live and
    // written straight back to Steam, so it mirrors the game-properties dropdown both ways.
    const [compatTools, setCompatTools] = SP_REACT.useState([]);
    const [currentTool, setCurrentTool] = SP_REACT.useState("");
    SP_REACT.useEffect(() => {
        setCompatTools([]);
        setCurrentTool("");
        if (!appid)
            return;
        let live = true;
        availableCompatTools(appid).then((tools) => {
            if (live)
                setCompatTools(tools);
        });
        const unregister = registerForCompatTool(appid, (tool) => {
            if (live)
                setCurrentTool(tool);
        });
        return () => {
            live = false;
            unregister();
        };
    }, [appid]);
    const compatOptions = [
        { data: "", label: "Steam default" },
        ...compatTools.map((tool) => ({ data: tool.name, label: tool.label })),
    ];
    const compatValue = compatOptions.some((option) => option.data === currentTool) ? currentTool : "";
    const presets = config.fexProfiles || {};
    const storedProfile = values.fexProfile;
    const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
    const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
    const storedLatency = String(values.audioLatency ?? "");
    const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
    const mesaOptions = [{ data: "", label: "System default" }, ...(config.mesaVersions || [])];
    const storedMesa = String(values.mesaVersion ?? "");
    const mesaValue = mesaOptions.some((option) => option.data === storedMesa) ? storedMesa : "";
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: "Proton Version", value: compatValue, options: compatOptions, onChange: (name) => {
                    setCurrentTool(String(name));
                    setCompatTool(appid, String(name));
                } }), SP_JSX.jsx(SelectEdit, { label: "FEX Preset", value: fexValue, options: fexOptions, onChange: (id) => patch({ fexProfile: id }) }), SP_JSX.jsx(SelectEdit, { label: "Audio Buffer", value: audioValue, options: audioLatencyOptions, onChange: (id) => patch({ audioLatency: id }) }), SP_JSX.jsx(SelectEdit, { label: "Mesa Version", value: mesaValue, options: mesaOptions, onChange: (id) => patch({ mesaVersion: id }) }), SP_JSX.jsx(EnvVarsButton, { value: String(values.envVars ?? ""), onSave: (next) => patch({ envVars: next }) })] }));
}

function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}

function Games({ config, setConfig, reload }) {
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
    // Default target: FEX/audio/env edit tweaks.global; fan + scheduler are the LIVE system
    // modes, applied immediately through the backend.
    const applyMode = async (setter, mode) => {
        try {
            const next = await setter(mode);
            setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
        }
        catch (error) {
            reload();
        }
    };
    const presets = config.fexProfiles || {};
    const storedProfile = values.fexProfile;
    const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
    const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
    const storedLatency = String(values.audioLatency ?? "");
    const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
    const showFields = editingDefault || perGameEnabled;
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "PERFORMANCE & GAME TWEAKS", children: [SP_JSX.jsx(SelectEdit, { label: "Game", value: game?.appid || "", options: editTargetOptions(config), onChange: setSelectedGame }), !editingDefault ? SP_JSX.jsx(DFL.ToggleField, { label: "Use Per-Game Settings", checked: perGameEnabled, onChange: setPerGameEnabled }) : null] }), showFields ? (SP_JSX.jsx(DFL.PanelSection, { title: "PERFORMANCE", children: editingDefault ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: "CPU Scheduler", value: config.lavdMode, options: lavdOptions, onChange: (mode) => applyMode(setLavdMode, mode) }), SP_JSX.jsx(SelectEdit, { label: "Fan Curve", value: config.fanMode, options: fanOptions, onChange: (mode) => applyMode(setFanMode, mode) })] })) : (SP_JSX.jsx(PerfFields, { values: values, patch: patchSettings })) })) : null, showFields ? (SP_JSX.jsxs(DFL.PanelSection, { title: "GAME TWEAKS", children: [SP_JSX.jsx("div", { className: "pocknix-note", children: "Changes apply on next game launch" }), editingDefault ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: "FEX Preset", value: fexValue, options: fexOptions, onChange: (id) => patchSettings({ fexProfile: id }) }), SP_JSX.jsx(SelectEdit, { label: "Audio Buffer", value: audioValue, options: audioLatencyOptions, onChange: (id) => patchSettings({ audioLatency: id }) }), SP_JSX.jsx(EnvVarsButton, { value: String(values.envVars ?? ""), onSave: (next) => patchSettings({ envVars: next }) })] })) : (SP_JSX.jsx(TweakFields, { config: config, appid: game.appid, values: values, patch: patchSettings }))] })) : null, !editingDefault && perGameEnabled ? (SP_JSX.jsx(ConfigSection, { game: { appid: game.appid, name: game.name || "" }, reload: reload })) : null] }));
}

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

function Library() {
    return SP_JSX.jsx(AddGameSection, {});
}

// SliderField has only onChange, so commits are debounced. The pending value lives in
// a ref so the unmount flush always sees the latest edit, not a stale first-render one.
const COMMIT_DELAY = 350;
// Hardware brightness is 0-255; the slider shows percent so it reads like the other two.
const briToPercent = (bri) => Math.round((bri / 255) * 100);
const percentToBri = (percent) => Math.round((percent / 100) * 255);
function ColorControls({ zone, hsv, brightness, onCommit }) {
    const [hue, saturation] = hsv;
    const [localH, setLocalH] = SP_REACT.useState(hsv[0]);
    const [localS, setLocalS] = SP_REACT.useState(hsv[1]);
    const [localBri, setLocalBri] = SP_REACT.useState(brightness);
    const pending = SP_REACT.useRef(null);
    const onCommitRef = SP_REACT.useRef(onCommit);
    onCommitRef.current = onCommit;
    // A commit response landing mid-drag would otherwise snap the slider backwards.
    SP_REACT.useEffect(() => { if (!pending.current)
        setLocalH(hsv[0]); }, [hue]);
    SP_REACT.useEffect(() => { if (!pending.current)
        setLocalS(hsv[1]); }, [saturation]);
    SP_REACT.useEffect(() => { if (!pending.current)
        setLocalBri(brightness); }, [brightness]);
    const schedule = (h, s, bri) => {
        setLocalH(h);
        setLocalS(s);
        setLocalBri(bri);
        pending.current = { hsv: [h, s, 100], bri };
    };
    SP_REACT.useEffect(() => {
        if (pending.current === null)
            return;
        const snapshot = pending.current;
        const timer = window.setTimeout(() => {
            pending.current = null;
            onCommitRef.current(snapshot.hsv, snapshot.bri);
        }, COMMIT_DELAY);
        return () => window.clearTimeout(timer);
    }, [localH, localS, localBri]);
    // QAM unmounts on close; flush any edit still in the debounce window.
    SP_REACT.useEffect(() => () => {
        if (pending.current !== null) {
            const snapshot = pending.current;
            pending.current = null;
            onCommitRef.current(snapshot.hsv, snapshot.bri);
        }
    }, []);
    const setHue = (h) => schedule(h, localS, localBri);
    const setSaturation = (s) => schedule(localH, s, localBri);
    const setBrightness = (b) => schedule(localH, localS, b);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: "Hue", value: localH, min: 0, max: 359, step: 1, showValue: true, validValues: "range", valueSuffix: "\u00B0", bottomSeparator: "thick", className: `pocknix-led-${zone}-h`, onChange: setHue }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: "Saturation", value: localS, min: 0, max: 100, step: 1, showValue: true, validValues: "range", valueSuffix: "%", bottomSeparator: "thick", className: `pocknix-led-${zone}-s`, onChange: setSaturation }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: "Brightness", value: briToPercent(localBri), min: 0, max: 100, step: 1, showValue: true, validValues: "range", valueSuffix: "%", bottomSeparator: "thick", className: `pocknix-led-${zone}-v`, onChange: (percent) => setBrightness(percentToBri(percent)) }) }), SP_JSX.jsx("style", { children: `
        .pocknix-led-${zone}-h .${DFL.gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right,
            hsl(0,100%,50%), hsl(60,100%,50%), hsl(120,100%,50%),
            hsl(180,100%,50%), hsl(240,100%,50%), hsl(300,100%,50%), hsl(360,100%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
        .pocknix-led-${zone}-s .${DFL.gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right, hsl(0,0%,100%), hsl(${localH},100%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
        .pocknix-led-${zone}-v .${DFL.gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right, hsl(0,0%,0%), hsl(${localH},${localS}%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
      ` })] }));
}

// HSV <-> RGB conversion for the stick-light color picker.
function hsvToRgb(h, s, v) {
    const hh = ((h % 360) + 360) % 360;
    const ss = Math.max(0, Math.min(100, s)) / 100;
    const vv = Math.max(0, Math.min(100, v)) / 100;
    const c = vv * ss;
    const x = c * (1 - Math.abs(((hh / 60) % 2) - 1));
    const m = vv - c;
    let r = 0;
    let g = 0;
    let b = 0;
    if (hh < 60)
        [r, g, b] = [c, x, 0];
    else if (hh < 120)
        [r, g, b] = [x, c, 0];
    else if (hh < 180)
        [r, g, b] = [0, c, x];
    else if (hh < 240)
        [r, g, b] = [0, x, c];
    else if (hh < 300)
        [r, g, b] = [x, 0, c];
    else
        [r, g, b] = [c, 0, x];
    return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}
function rgbToHsv(r, g, b) {
    const rr = r / 255;
    const gg = g / 255;
    const bb = b / 255;
    const max = Math.max(rr, gg, bb);
    const min = Math.min(rr, gg, bb);
    const delta = max - min;
    let h = 0;
    let s = 0;
    const v = max;
    if (delta !== 0) {
        s = delta / max;
        if (max === rr)
            h = ((gg - bb) / delta + (gg < bb ? 6 : 0)) / 6;
        else if (max === gg)
            h = ((bb - rr) / delta + 2) / 6;
        else
            h = ((rr - gg) / delta + 4) / 6;
    }
    return [Math.round(h * 360), Math.round(s * 100), Math.round(v * 100)];
}

// Stored RGB holds the full-value color; the kernel multicolor class scales each
// channel by brightness/max_brightness, so dimming is linear and the color survives.
function commit(side, hsv, brightness, setConfig, reload) {
    const [r, g, b] = hsvToRgb(hsv[0], hsv[1], 100);
    setLed(side, r, g, b, brightness)
        .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
        .catch(() => reload());
}
function sideHsv(side) {
    return rgbToHsv(side.r, side.g, side.b);
}
function Lighting({ config, setConfig, reload }) {
    const led = config.led;
    const leftHsv = sideHsv(led.left);
    const rightHsv = sideHsv(led.right);
    const commitLeft = (hsv, brightness) => commit("left", hsv, brightness, setConfig, reload);
    const commitRight = (hsv, brightness) => commit("right", hsv, brightness, setConfig, reload);
    const commitBoth = (hsv, brightness) => commit("both", hsv, brightness, setConfig, reload);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "STICK LIGHTS", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Enable", checked: led.enabled, onChange: (value) => setLedEnabled(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Boot Pulse", description: "Pulse the sticks white on boot while Steam loads, then switch to your colors.", checked: led.bootPulse, disabled: !led.enabled, onChange: (value) => setBootPulse(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Link Left & Right", description: "Match both sticks to the same color.", checked: led.linked, disabled: !led.enabled, onChange: (value) => setLedLinked(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }), led.sidesAvailable && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Side Lights", description: "Match the side lighting to the sticks.", checked: led.sides, disabled: !led.enabled, onChange: (value) => setLedSides(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }))] }), led.enabled && (led.linked ? (SP_JSX.jsx(DFL.PanelSection, { title: "BOTH STICKS", children: SP_JSX.jsx(ColorControls, { zone: "both", hsv: leftHsv, brightness: led.left.brightness, onCommit: commitBoth }) })) : (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSection, { title: "LEFT STICK", children: SP_JSX.jsx(ColorControls, { zone: "left", hsv: leftHsv, brightness: led.left.brightness, onCommit: commitLeft }) }), SP_JSX.jsx(DFL.PanelSection, { title: "RIGHT STICK", children: SP_JSX.jsx(ColorControls, { zone: "right", hsv: rightHsv, brightness: led.right.brightness, onCommit: commitRight }) })] })))] }));
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

const SHOWN_UPDATES = 8;
const gib = (bytes) => (bytes / 1024 ** 3).toFixed(1);
// snapshot metadata stores ISO-8601 UTC; show local DD/MM/YYYY HH:MM
const fmtDate = (iso) => {
    const d = new Date(iso);
    if (isNaN(d.getTime()))
        return iso;
    const p = (n) => String(n).padStart(2, "0");
    return `${p(d.getDate())}-${p(d.getMonth() + 1)}-${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
};
function Updater() {
    const [updates, setUpdates] = SP_REACT.useState(null);
    const [checking, setChecking] = SP_REACT.useState(false);
    const [status, setStatus] = SP_REACT.useState(null);
    const [snap, setSnap] = SP_REACT.useState(null);
    const [rollingBack, setRollingBack] = SP_REACT.useState(false);
    const [rollbackDone, setRollbackDone] = SP_REACT.useState(false);
    const [error, setError] = SP_REACT.useState("");
    const [rollbackError, setRollbackError] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    const running = !!status?.running;
    busyRef.current = checking || running || rollingBack;
    const refreshSnap = () => snapshotStatus().then(setSnap).catch(() => { });
    // Re-attach to an update that survived a QAM close (or a Steam restart).
    SP_REACT.useEffect(() => {
        let cancelled = false;
        updateStatus()
            .then((next) => {
            if (!cancelled && (next.running || next.exitCode !== null))
                setStatus(next);
        })
            .catch(() => { });
        refreshSnap();
        return () => {
            cancelled = true;
        };
    }, []);
    SP_REACT.useEffect(() => {
        if (!running)
            return;
        const timer = window.setInterval(async () => {
            try {
                const next = await updateStatus();
                setStatus(next);
                if (!next.running) {
                    if (next.exitCode === 0)
                        setUpdates([]);
                    refreshSnap(); // a finished transaction changes snapshots + reboot-required
                }
            }
            catch (err) {
                setError(String(err));
            }
        }, 2000);
        return () => window.clearInterval(timer);
    }, [running]);
    const check = async () => {
        if (busyRef.current)
            return;
        setChecking(true);
        setError("");
        try {
            setUpdates(await checkUpdates());
        }
        catch (err) {
            setError(String(err));
        }
        finally {
            setChecking(false);
        }
    };
    const start = async () => {
        if (busyRef.current)
            return;
        setError("");
        try {
            setStatus(await startUpdate());
        }
        catch (err) {
            setError(String(err));
        }
    };
    const confirmStart = () => DFL.showModal(SP_JSX.jsx(DFL.ConfirmModal, { strTitle: "Install Updates", strDescription: "Downloads and installs all available system updates. Keep the device powered; a running game may stutter. Restart after it finishes.", strOKButtonText: "Install", onOK: start }));
    const lastSnapshot = snap?.supported && snap.snapshots.length > 0 ? snap.snapshots[snap.snapshots.length - 1] : null;
    // Already rolled back onto the latest snapshot: another rollback would be a no-op,
    // so hide the button until the next update (which clears the marker + snapshots anew).
    const onLastSnapshot = !!(snap?.rolledBack && lastSnapshot && snap.rolledBack.fromSnapshot === lastSnapshot.id);
    const rollBack = async () => {
        if (busyRef.current || !lastSnapshot)
            return;
        setRollbackError("");
        setRollingBack(true);
        try {
            setSnap(await startRollback(lastSnapshot.id));
            setRollbackDone(true);
        }
        catch (err) {
            setRollbackError(String(err));
        }
        finally {
            setRollingBack(false);
        }
    };
    const confirmRollback = () => {
        if (!lastSnapshot)
            return;
        DFL.showModal(SP_JSX.jsx(DFL.ConfirmModal, { strTitle: "Roll Back Last Update", strDescription: `Restores the system to before the update of ${fmtDate(lastSnapshot.created)}` +
                (lastSnapshot.targets ? ` (${lastSnapshot.targets})` : "") +
                `. Games, saves and settings are kept.` +
                (lastSnapshot.kernel ? " The previous kernel is restored too." : "") +
                ` Reboot after it completes.`, strOKButtonText: "Roll Back", onOK: rollBack }));
    };
    const reboot = () => rebootSystem().catch((err) => setError(String(err)));
    const finished = !running && status?.exitCode !== null && status?.exitCode !== undefined;
    const summary = updates === null
        ? "Not checked yet"
        : updates.length === 0
            ? "System is up to date"
            : `${updates.length} update${updates.length === 1 ? "" : "s"} available`;
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "SYSTEM UPDATES", children: [!running ? SP_JSX.jsx(DFL.Field, { label: "Status", description: summary }) : null, !running && updates && updates.length > 0 ? (SP_JSX.jsxs("div", { className: "pocknix-note", children: [updates.slice(0, SHOWN_UPDATES).map((update) => (SP_JSX.jsx("div", { children: `${update.name} ${update.current} → ${update.latest}` }, update.name))), updates.length > SHOWN_UPDATES ? SP_JSX.jsx("div", { children: `… and ${updates.length - SHOWN_UPDATES} more` }) : null] })) : null, SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: check, children: checking ? "Checking…" : "Check for Updates" }) }), !running && updates && updates.length > 0 ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: confirmStart, children: "Install Updates" }) })) : null, running ? SP_JSX.jsx(DFL.Field, { label: "Updating\u2026", description: "Safe to close this menu. Do not power off." }) : null, finished ? (SP_JSX.jsx(DFL.Field, { label: status.exitCode === 0 ? "Update complete" : `Update failed (code ${status.exitCode})`, description: status.exitCode === 0 ? "Restart to finish applying updates." : "See the log below." })) : null, finished && status.exitCode === 0 ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: reboot, children: "Restart Now" }) })) : null, (running || (finished && status.exitCode !== 0)) && status?.log ? (SP_JSX.jsx("div", { className: "pocknix-note pocknix-log", children: status.log })) : null, error ? SP_JSX.jsx(DFL.Field, { label: "Error", description: error }) : null] }), snap?.supported ? (SP_JSX.jsxs(DFL.PanelSection, { title: "ROLLBACK", children: [snap.rolledBack && !rollbackDone ? (SP_JSX.jsx(DFL.Field, { label: "System was rolled back", description: `Restored from snapshot ${snap.rolledBack.fromSnapshot} (${fmtDate(snap.rolledBack.ts)}).${onLastSnapshot ? " Rollback will be available again after the next update." : ""}` })) : null, rollbackDone ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.Field, { label: "Rolled back", description: "Reboot to finish switching to the restored system." }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: reboot, children: "Reboot Now" }) })] })) : onLastSnapshot ? null : lastSnapshot ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.Field, { label: "Last snapshot", description: `${fmtDate(lastSnapshot.created)}${lastSnapshot.targets ? ` — ${lastSnapshot.targets}` : ""}` }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: confirmRollback, children: rollingBack ? "Rolling back…" : "Roll Back Last Update" }) })] })) : (SP_JSX.jsx(DFL.Field, { label: "No snapshots yet", description: "A snapshot is taken automatically before every update." })), rollbackError ? SP_JSX.jsx(DFL.Field, { label: "Rollback error", description: rollbackError }) : null, SP_JSX.jsx(DFL.Field, { label: "Storage", description: `${gib(snap.freeBytes)} GB free${snap.lowSpace ? " — LOW: snapshots may be skipped" : ""}` })] })) : null] }));
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
    const tabs = [
        { id: "Games", title: tabIcons.Games, content: tabContent(SP_JSX.jsx(Games, { config: config, setConfig: setConfig, reload: load })) },
        { id: "Library", title: tabIcons.Library, content: tabContent(SP_JSX.jsx(Library, {})) },
        ...(config.led.available
            ? [{ id: "Lighting", title: tabIcons.Lighting, content: tabContent(SP_JSX.jsx(Lighting, { config: config, setConfig: setConfig, reload: load })) }]
            : []),
        { id: "Storage", title: tabIcons.Storage, content: tabContent(SP_JSX.jsx(Storage, {})) },
        { id: "Updater", title: tabIcons.Updater, content: tabContent(SP_JSX.jsx(Updater, {})) },
    ];
    return (SP_JSX.jsxs("div", { className: "pocknix-control-tabs", children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsx(DFL.Tabs, { activeTab: tab, onShowTab: setTab, tabs: tabs })] }));
}

/** Standalone per-game settings, opened from the library context menu. Saves on each change
 *  (no QAM debounce lifecycle here; the modal has an explicit close). */
function GameSettingsModal({ appid, name, closeModal }) {
    const [config, setConfig] = SP_REACT.useState(null);
    SP_REACT.useEffect(() => {
        getConfig()
            .then(setConfig)
            .catch(() => closeModal?.());
    }, []);
    if (!config)
        return SP_JSX.jsx(DFL.ModalRoot, { closeModal: closeModal, children: "Loading\u2026" });
    const gameSettings = config.tweaks.games[appid] || {};
    const enabled = gameSettings.enabled === true;
    const values = enabled ? { ...config.tweaks.global, ...gameSettings } : config.tweaks.global;
    const update = (mutate) => {
        const next = clone(config);
        mutate(next);
        setConfig(next);
        saveTweaks(next.tweaks).catch(() => { });
    };
    const patch = (fields) => update((next) => {
        const existing = next.tweaks.games[appid] || {};
        next.tweaks.games[appid] = { ...existing, enabled: true, name, ...fields };
    });
    return (SP_JSX.jsxs(DFL.ModalRoot, { closeModal: closeModal, children: [SP_JSX.jsx("div", { style: { fontWeight: 600, marginBottom: "8px" }, children: name || `App ${appid}` }), SP_JSX.jsx(DFL.ToggleField, { label: "Use Per-Game Settings", checked: enabled, onChange: (on) => update((next) => {
                    next.tweaks.games[appid] = { ...(next.tweaks.games[appid] || {}), enabled: on, name };
                }) }), enabled ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(PerfFields, { values: values, patch: patch }), SP_JSX.jsx(TweakFields, { config: config, appid: appid, values: values, patch: patch }), SP_JSX.jsx(ConfigSection, { game: { appid, name }, reload: () => getConfig().then(setConfig).catch(() => { }) })] })) : null] }));
}

// Adds "Pocknix Settings" to the library entry context menu (the Start-button menu).
// The menu class is no longer a module export: locate its module by the
// "().LibraryContextMenu" classname marker, take the wrapper member (the one injecting
// `navigator:` via the jsx runtime), and fake-render it — the element's type is the real
// class. Steam UI internals are unversioned, so every step is guarded: if the shape
// changes we lose the menu item, never the plugin.
function patchLibraryContextMenu() {
    try {
        const menuModule = DFL.findModuleChild((mod) => {
            if (typeof mod !== "object" || !mod)
                return undefined;
            for (const prop in mod) {
                try {
                    if (mod[prop]?.toString?.()?.includes("().LibraryContextMenu"))
                        return mod;
                }
                catch (error) { }
            }
            return undefined;
        });
        if (!menuModule)
            return () => { };
        const wrapper = Object.values(menuModule).find((member) => {
            try {
                return typeof member === "function" && member?.toString?.()?.includes("navigator:");
            }
            catch (error) {
                return false;
            }
        });
        if (!wrapper)
            return () => { };
        const LibraryContextMenu = DFL.fakeRenderComponent(wrapper)?.type;
        if (!LibraryContextMenu?.prototype?.BuildManageSubmenu)
            return () => { };
        // Patch the Manage submenu builder rather than the top-level render, so the entry
        // lands under Manage. The builder's return shape is guarded both ways (plain item
        // array vs element with children).
        const patch = DFL.afterPatch(LibraryContextMenu.prototype, "BuildManageSubmenu", function (_args, ret) {
            try {
                const overview = this.props?.overview;
                const appid = overview?.appid;
                if (!appid)
                    return ret;
                const children = Array.isArray(ret) ? ret : ret?.props?.children;
                if (!Array.isArray(children))
                    return ret;
                if (children.some((child) => child?.key === "pocknix-settings"))
                    return ret;
                children.push(SP_JSX.jsx(DFL.MenuItem, { onSelected: () => DFL.showModal(SP_JSX.jsx(GameSettingsModal, { appid: String(appid), name: String(overview?.display_name ?? "") })), children: "Pocknix Settings" }, "pocknix-settings"));
            }
            catch (error) { }
            return ret;
        });
        return () => patch.unpatch();
    }
    catch (error) {
        return () => { };
    }
}

var index = definePlugin(() => {
    const unpatchContextMenu = patchLibraryContextMenu();
    return {
        name: "Pocknix Control",
        content: SP_JSX.jsx(Content, {}),
        icon: SP_JSX.jsx("div", { style: { fontWeight: 700 }, children: "P" }),
        alwaysRender: true,
        onDismount() {
            unpatchContextMenu();
        },
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
