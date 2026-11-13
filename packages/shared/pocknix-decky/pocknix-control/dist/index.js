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
const useQuickAccessVisible = api.useQuickAccessVisible;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

function gameDisplayName(game) {
    if (!game?.appid)
        return "";
    return game.name || `App ${game.appid}`;
}
// The backend lists every appmanifest in steamapps, tools included. app_type 4 = tool in
// Steam's appStore overview; this name pattern is the fallback when no overview exists.
const NON_GAME_NAME = /^(Proton[ 0-9]|Proton (Hotfix|EasyAntiCheat|BattlEye)|Steam Linux Runtime|Steamworks Common)/i;
function isGame(appid, name = "") {
    try {
        const overview = window.appStore?.GetAppOverviewByAppID?.(Number(appid));
        if (typeof overview?.app_type === "number")
            return overview.app_type !== 4;
    }
    catch (error) {
    }
    return !NON_GAME_NAME.test(name);
}
function installedSteamGames(config) {
    return (config.installedGames || [])
        .filter((game) => game?.appid && isGame(String(game.appid), game.name || ""))
        .map((game) => String(game.appid));
}
// Matched by name, as pocknix-tiles names them, so a stale duplicate tile is caught too.
let plainTileNames = new Set();
function rememberPlainTiles(config) {
    plainTileNames = new Set((config.plainTiles || []).map((tile) => tile.name));
    return config;
}
function isPlainTile(appid, name) {
    if (Number(appid) < 0x80000000)
        return false;
    let display = name;
    if (display === undefined) {
        try {
            display = window.appStore?.GetAppOverviewByAppID?.(Number(appid))?.display_name || "";
        }
        catch (error) {
            display = "";
        }
    }
    return plainTileNames.has(display || "");
}
// Non-Steam shortcuts have no appmanifest, so only deckDesktopApps sees them. Their appids are
// unsigned and above 2^31, hence the >>> 0: some builds hand out the signed-int32 form.
function nonSteamShortcuts() {
    return allShortcuts().filter((shortcut) => !isPlainTile(shortcut.appid, shortcut.name));
}
function plainTileShortcuts() {
    return allShortcuts().filter((shortcut) => isPlainTile(shortcut.appid, shortcut.name));
}
function allShortcuts() {
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
    // Saved tweaks keep a game listed even when the lookups above miss it, so existing
    // per-game config can never become unreachable.
    for (const [appid, game] of Object.entries(config.tweaks?.games || {})) {
        if (game && typeof game === "object" && !games.has(String(appid)) && !isPlainTile(String(appid), game.name)) {
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
    return isPlainTile(id, name) ? null : { appid: id, name: name || `App ${id}` };
}

const getConfig = () => call("get_config").then(rememberPlainTiles);
const setFanMode = (mode) => call("set_fan_mode", mode);
const setLavdMode = (mode) => call("set_lavd_mode", mode);
const gameLifetime = (appid, running) => call("game_lifetime", appid, running);
const patchTweaks = (appid, fields) => call("patch_tweaks", appid, fields);
const setLed = (side, r, g, b, brightness) => call("set_led", side, r, g, b, brightness);
const setLedLinked = (linked) => call("set_led_linked", linked);
const setLedEnabled = (enabled) => call("set_led_enabled", enabled);
const setLedSides = (sides) => call("set_led_sides", sides);
const checkUpdates = () => call("check_updates");
const startUpdate = () => call("start_update");
const updateStatus = () => call("update_status");
const bootloaderStatus = () => call("bootloader_status");
const snapshotStatus = () => call("snapshot_status");
const startRollback = (id) => call("start_rollback", id);
const rebootSystem = () => call("reboot_system");

// Every Steam game and every non-Steam shortcut (emulator tiles, ROM managers, a Windows .exe on
// Proton) launches through pocknix-game-launch, which applies the per-game tweaks at launch
// time, so a settings change never has to touch launch options. Pocknix's own settings apps
// (launch=plain tiles) are the exception: they never take game tweaks.
// Bare name: Steam runs launch options through a shell with the system PATH (/usr/bin).
const LAUNCHER = "pocknix-game-launch";
const COMMAND = "%command%";
// Written by Pocknix Control before the launcher existed; the launcher exports it itself now.
const FEX_TOKEN = /STEAM_COMPAT_FEX_CONFIG=("[^"]*"|\S*)\s*/g;
function getDetails(appid) {
    return new Promise((resolve) => {
        const apps = window.SteamClient?.Apps;
        if (!apps?.RegisterForAppDetails)
            return resolve(null);
        let registration;
        let timer;
        let done = false;
        const finish = (value) => {
            if (done)
                return;
            done = true;
            if (timer !== undefined)
                window.clearTimeout(timer);
            // Steam may call back before RegisterForAppDetails returns; unregister on a microtask.
            Promise.resolve().then(() => registration?.unregister?.());
            resolve(value);
        };
        timer = window.setTimeout(() => finish(null), 3000);
        try {
            registration = apps.RegisterForAppDetails(Number(appid), (details) => {
                finish({ exe: String(details?.strShortcutExe ?? "").replace(/^"|"$/g, ""), launchOptions: String(details?.strLaunchOptions ?? "") });
            });
        }
        catch (error) {
            finish(null);
        }
    });
}
/** null = already wrapped. Keeps the user's own options around %command%. */
function wrapLaunchOptions(current) {
    const stripped = current.replace(FEX_TOKEN, "").trim();
    if (stripped.includes(LAUNCHER))
        return stripped === current.trim() ? null : stripped;
    if (stripped.includes(COMMAND))
        return stripped.replace(COMMAND, `${LAUNCHER} ${COMMAND}`);
    // Without %command% Steam appends bare options as arguments, so they stay after it.
    return [`${LAUNCHER} ${COMMAND}`, stripped].filter(Boolean).join(" ");
}
/** Bails rather than clobber when the current value can't be read. */
async function ensureLaunchWrapper(appid) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.SetAppLaunchOptions)
        return false;
    const details = await getDetails(appid);
    if (details === null)
        return false;
    const next = wrapLaunchOptions(details.launchOptions);
    if (next !== null)
        apps.SetAppLaunchOptions(Number(appid), next);
    return true;
}
async function wrapShortcuts(appids) {
    for (const appid of appids)
        await ensureLaunchWrapper(appid);
}
/** pocknix-tiles finds a tile by exe + launch options, so an older sweep's wrapper hid it. Only an
 *  exact wrapper + manifest args match is undone; anything else on the tile is the user's. */
async function unwrapPlainTiles(tiles, shortcuts) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.SetAppLaunchOptions)
        return;
    for (const shortcut of shortcuts) {
        const details = await getDetails(shortcut.appid);
        if (!details)
            continue;
        const tile = tiles.find((t) => t.name === shortcut.name && t.exe === details.exe);
        if (tile && details.launchOptions.trim() === `${LAUNCHER} ${COMMAND} ${tile.args}`.trim()) {
            apps.SetAppLaunchOptions(Number(shortcut.appid), tile.args);
        }
    }
}
async function wrapAllGames(appids) {
    let next = 0;
    const worker = async () => {
        while (next < appids.length)
            await ensureLaunchWrapper(appids[next++]);
    };
    await Promise.all(Array.from({ length: Math.min(8, appids.length) }, worker));
}
/** New installs get wrapped once their download queues; returns the unregister. */
function registerDownloadWrapper(isGame) {
    const downloads = window.SteamClient?.Downloads;
    if (!downloads?.RegisterForDownloadItems)
        return () => { };
    const pending = new Set();
    let timer;
    const flush = () => {
        timer = undefined;
        const ids = Array.from(pending);
        pending.clear();
        wrapAllGames(ids.filter(isGame));
    };
    // Each queue item is { item_data: [{ appid, ... }] }: the appids live in item_data.
    const handle = downloads.RegisterForDownloadItems((_paused, items) => {
        if (!Array.isArray(items))
            return;
        for (const item of items) {
            for (const entry of Object.values(item?.item_data || {})) {
                const appid = String(entry?.appid ?? "");
                if (appid && appid !== "0")
                    pending.add(appid);
            }
        }
        if (timer === undefined)
            timer = window.setTimeout(flush, 1500);
    });
    return () => {
        if (timer !== undefined)
            window.clearTimeout(timer);
        try {
            handle?.unregister?.();
        }
        catch (error) {
        }
    };
}

// Replaces the stock "Add a Non-Steam Game" flow: Steam's file browser cannot open a new
// window under the Plasma Mobile X11 session, so Decky's in-UI picker feeds this instead.
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
    ensureLaunchWrapper(String(appId >>> 0));
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
    return (SP_JSX.jsxs(DFL.PanelSection, { title: "NON-STEAM GAMES", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: pick, children: "Add Non-Steam Game" }) }), SP_JSX.jsx("div", { className: "pocknix-note", children: "Pick an executable to add it to your Steam library" })] }));
}

function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}

function applyPatch(config, appid, fields) {
    const next = clone(config);
    if (appid && !next.tweaks.games[appid])
        next.tweaks.games[appid] = {};
    const target = appid ? next.tweaks.games[appid] : next.tweaks.global;
    for (const [key, value] of Object.entries(fields)) {
        if (value === null)
            delete target[key];
        else
            target[key] = value;
    }
    return next;
}
/** Shows the edit at once and sends only the changed fields ("" = Default). */
function usePatchTweaks(setConfig, onError, seq) {
    // Replies can arrive out of order; only the newest may replace what is on screen.
    const own = SP_REACT.useRef(0);
    const latest = seq ?? own;
    return SP_REACT.useCallback((appid, fields) => {
        setConfig((current) => (current ? applyPatch(current, appid, fields) : current));
        const seq = ++latest.current;
        patchTweaks(appid, fields)
            .then((tweaks) => {
            if (seq === latest.current)
                setConfig((current) => (current ? { ...current, tweaks } : current));
        })
            .catch((error) => onError?.(error));
    }, [setConfig, onError]);
}

function Icon({ path }) {
    return (SP_JSX.jsx("svg", { style: { display: "block" }, width: "20", height: "20", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: "2", strokeLinecap: "round", strokeLinejoin: "round", children: path }));
}
const tabIcons = {
    Games: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("line", { x1: "6", x2: "10", y1: "11", y2: "11" }), SP_JSX.jsx("line", { x1: "8", x2: "8", y1: "9", y2: "13" }), SP_JSX.jsx("line", { x1: "15", x2: "15.01", y1: "12", y2: "12" }), SP_JSX.jsx("line", { x1: "18", x2: "18.01", y1: "10", y2: "10" }), SP_JSX.jsx("path", { d: "M17.32 5H6.68a4 4 0 0 0-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 0 1 9.828 16h4.344a2 2 0 0 1 1.414.586L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.545-.604-6.584-.685-7.258-.007-.05-.011-.1-.017-.151A4 4 0 0 0 17.32 5z" })] }) })),
    AddGame: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("rect", { width: "18", height: "18", x: "3", y: "3", rx: "2" }), SP_JSX.jsx("path", { d: "M8 12h8" }), SP_JSX.jsx("path", { d: "M12 8v8" })] }) })),
    StickLights: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("path", { d: "M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5" }), SP_JSX.jsx("path", { d: "M9 18h6" }), SP_JSX.jsx("path", { d: "M10 22h4" })] }) })),
    Updater: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("path", { d: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" }), SP_JSX.jsx("polyline", { points: "7 10 12 15 17 10" }), SP_JSX.jsx("line", { x1: "12", x2: "12", y1: "15", y2: "3" })] }) })),
};

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
function StickLights({ config, setConfig, reload }) {
    const led = config.led;
    const leftHsv = sideHsv(led.left);
    const rightHsv = sideHsv(led.right);
    const commitLeft = (hsv, brightness) => commit("left", hsv, brightness, setConfig, reload);
    const commitRight = (hsv, brightness) => commit("right", hsv, brightness, setConfig, reload);
    const commitBoth = (hsv, brightness) => commit("both", hsv, brightness, setConfig, reload);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "STICK LIGHTS", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Enable", checked: led.enabled, onChange: (value) => setLedEnabled(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Link Left & Right", description: "Match both sticks to the same color.", checked: led.linked, disabled: !led.enabled, onChange: (value) => setLedLinked(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }), led.sidesAvailable && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Side Lights", description: "Match the side lighting to the sticks.", checked: led.sides, disabled: !led.enabled, onChange: (value) => setLedSides(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }))] }), led.enabled && (led.linked ? (SP_JSX.jsx(DFL.PanelSection, { title: "BOTH STICKS", children: SP_JSX.jsx(ColorControls, { zone: "both", hsv: leftHsv, brightness: led.left.brightness, onCommit: commitBoth }) })) : (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSection, { title: "LEFT STICK", children: SP_JSX.jsx(ColorControls, { zone: "left", hsv: leftHsv, brightness: led.left.brightness, onCommit: commitLeft }) }), SP_JSX.jsx(DFL.PanelSection, { title: "RIGHT STICK", children: SP_JSX.jsx(ColorControls, { zone: "right", hsv: rightHsv, brightness: led.right.brightness, onCommit: commitRight }) })] })))] }));
}

// Drives the same state as Steam's own per-game compatibility dropdown (SpecifyCompatTool +
// app details), so never store a shadow copy: the two UIs stay in sync by construction.

// Steam's tool list is only reachable via its react-query hook, which throws outside Steam's
// QueryClient; a throwaway root under Steam's provider works from any tree.
const steam = {
    hook: null,
    provider: null,
    client: null,
    createRoot: null,
};
function findSteam() {
    steam.hook || (steam.hook = DFL.findModuleExport((e) => typeof e === "function" && e.toString().includes("Failed to fetch available compat tools")));
    steam.provider || (steam.provider = DFL.findModuleExport((e) => {
        if (typeof e !== "function")
            return false;
        const src = e.toString();
        return src.length < 400 && /\.mount\(\)/.test(src) && /unmount\(\)/.test(src) && /children/.test(src);
    }));
    steam.client || (steam.client = DFL.findModuleExport((e) => e && typeof e === "object" && typeof e.getQueryCache === "function" && typeof e.invalidateQueries === "function"));
    steam.createRoot || (steam.createRoot = DFL.findModule((m) => typeof m?.createRoot === "function")?.createRoot);
    return !!(steam.hook && steam.provider && steam.client && steam.createRoot);
}
class ProbeBoundary extends SP_REACT.Component {
    constructor() {
        super(...arguments);
        this.state = { failed: false };
    }
    static getDerivedStateFromError() {
        return { failed: true };
    }
    componentDidCatch(error) {
        this.props.onError(error);
    }
    render() {
        return this.state.failed ? null : this.props.children;
    }
}
function steamCompatTools(appid) {
    return new Promise((resolve) => {
        let root = null;
        const finish = (tools) => {
            clearTimeout(timer);
            resolve(tools);
            setTimeout(() => root?.unmount(), 0);
        };
        const timer = setTimeout(() => finish([]), 10000);
        const Probe = () => {
            const [query] = steam.hook(Number(appid));
            if (query.status === "success")
                finish(fromSteam(query.data));
            else if (query.status === "error")
                finish([]);
            return null;
        };
        try {
            root = steam.createRoot(document.createElement("div"));
            root.render(SP_REACT.createElement(ProbeBoundary, { onError: () => finish([]) }, SP_REACT.createElement(steam.provider, { client: steam.client }, SP_REACT.createElement(Probe))));
        }
        catch {
            finish([]);
        }
    });
}
function fromSteam(data) {
    return (data?.tools ?? [])
        .filter((tool) => !tool.is_incompatible)
        .map((tool) => ({ name: String(tool.name ?? ""), label: String(tool.display_name || tool.name || "") }))
        .filter((tool) => tool.name);
}
async function availableCompatTools(appid) {
    const apps = window.SteamClient?.Apps;
    try {
        if (apps?.GetAvailableCompatTools) {
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
        return findSteam() ? await steamCompatTools(appid) : [];
    }
    catch {
        return [];
    }
}
// Steam reports its own choice in the same fields as a user's pick; only the priority tells them
// apart, and a pick made in Properties (or by SpecifyCompatTool) is saved at 250.
const USER_PICK_PRIORITY = 250;
/** Live view of the game's tool; fires again when it changes anywhere (incl. Steam's UI). */
function registerForCompatTool(appid, onChange) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.RegisterForAppDetails)
        return () => { };
    const registration = apps.RegisterForAppDetails(Number(appid), (details) => {
        const tool = String(details?.strCompatToolName ?? "");
        const label = String(details?.strCompatToolDisplayName || tool);
        onChange({ tool: Number(details?.nCompatToolPriority) >= USER_PICK_PRIORITY ? tool : "", label });
    });
    return () => registration?.unregister?.();
}
function setCompatTool(appid, tool) {
    window.SteamClient?.Apps?.SpecifyCompatTool?.(Number(appid), tool);
    // A shortcut picked up after the load-time sweep still gets the launcher.
    if (tool && Number(appid) >= 0x80000000)
        ensureLaunchWrapper(appid);
}

const shaderModels = ["6_8", "6_7", "6_6", "6_5", "6_4", "6_3", "6_2", "6_1", "6_0"].map((v) => ({ data: v, label: v.replace("_", ".") }));
const envPresets = [
    {
        key: "VKD3D_FEATURE_LEVEL",
        label: "DirectX 12 feature level",
        description: "For DirectX 12 games that won't start or say your graphics card isn't supported. 12.1 fixes most.",
        values: ["12_1", "12_2", "12_0", "11_1", "11_0"].map((v) => ({ data: v, label: v.replace("_", ".") })),
    },
    {
        key: "VKD3D_SHADER_MODEL",
        label: "DirectX 12 shader model",
        description: "Lower it if a DirectX 12 game crashes or shows broken graphics.",
        values: shaderModels,
    },
    {
        key: "PROTON_LOG",
        label: "Write a Proton log",
        description: "Saves steam-<game id>.log in your home folder for troubleshooting. Remove it afterwards: it slows the game.",
        values: [{ data: "1", label: "On" }],
    },
];
const presetFor = (key) => envPresets.find((preset) => preset.key === key);
/** POSIX-shell word splitting, the same rules as the launcher's shlex.split. */
function parseEnvVars(raw) {
    if (typeof raw !== "string")
        return [];
    const words = [];
    let word = "";
    let inWord = false;
    let quote = "";
    for (let i = 0; i < raw.length; i++) {
        const c = raw[i];
        if (quote === "'") {
            if (c === "'")
                quote = "";
            else
                word += c;
        }
        else if (quote === '"') {
            if (c === '"')
                quote = "";
            else if (c === "\\" && i + 1 < raw.length && '"\\$`'.includes(raw[i + 1]))
                word += raw[++i];
            else
                word += c;
        }
        else if (c === "'" || c === '"') {
            quote = c;
            inWord = true;
        }
        else if (c === "\\" && i + 1 < raw.length) {
            word += raw[++i];
            inWord = true;
        }
        else if (/\s/.test(c)) {
            if (inWord)
                words.push(word);
            word = "";
            inWord = false;
        }
        else {
            word += c;
            inWord = true;
        }
    }
    if (quote)
        return [];
    if (inWord)
        words.push(word);
    const vars = new Map();
    for (const w of words) {
        const at = w.indexOf("=");
        const key = w.slice(0, at);
        // First one wins, as in the launcher, so the list shows what a launch applies.
        if (at > 0 && /^[A-Za-z_][A-Za-z0-9_]*$/.test(key) && !vars.has(key))
            vars.set(key, w.slice(at + 1));
    }
    return Array.from(vars.entries());
}
const quoteValue = (value) => (/^[A-Za-z0-9_.,:=\/+@%-]*$/.test(value) ? value : `'${value.replace(/'/g, `'\\''`)}'`);
/** "" -> null so an emptied list removes the key instead of storing a blank. */
function serializeEnvVars(vars) {
    return vars.length ? vars.map(([key, value]) => `${key}=${quoteValue(value)}`).join(" ") : null;
}

const APPLIES_NOW = "Applies now";
const APPLIES_NEXT_LAUNCH = "Applies on next launch";
/** Now and next launch only differ while a running game uses the settings being edited; at any
 *  other time everything takes effect when a game starts, which one note says instead. */
const timed = (live, when, text) => (live ? (text ? `${when}. ${text}` : when) : text);

function AddEnvVarModal({ current, onAdd, closeModal }) {
    const [key, setKey] = SP_REACT.useState(envPresets[0].key);
    const preset = presetFor(key);
    const existing = current.find(([k]) => k === key)?.[1];
    const [value, setValue] = SP_REACT.useState(null);
    const picked = value ?? (preset.values.some((v) => v.data === existing) ? existing : preset.values[0].data);
    return (SP_JSX.jsxs(DFL.ConfirmModal, { strTitle: "Add Environment Variable", strDescription: preset.description, strOKButtonText: "Add", onCancel: () => closeModal?.(), onOK: () => {
            onAdd(key, picked);
            closeModal?.();
        }, children: [SP_JSX.jsx(DFL.DropdownItem, { label: "Variable", selectedOption: key, rgOptions: envPresets.map((p) => ({ data: p.key, label: p.label })), onChange: (option) => {
                    setKey(String(option.data));
                    setValue(null);
                } }), preset.values.length > 1 ? (SP_JSX.jsx(DFL.DropdownItem, { label: "Value", selectedOption: picked, rgOptions: preset.values, onChange: (option) => setValue(String(option.data)) })) : null] }));
}
const describe = ([key, value]) => `${key}=${value}`;
/** own = this scope's envVars; inherited = the Default list a game adds its own on top of.
 *  Default has no Add: only variables saved there before can be seen and removed. */
function EnvVarsField({ own, inherited, canAdd = true, live, onChange }) {
    const vars = parseEnvVars(own);
    const fromDefault = parseEnvVars(inherited).filter(([key]) => !vars.some(([k]) => k === key));
    const save = (next) => onChange(serializeEnvVars(next));
    if (!canAdd && !vars.length)
        return null;
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.Field, { label: "Environment Variables", description: timed(live, APPLIES_NEXT_LAUNCH) }) }), vars.map((entry) => (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { label: presetFor(entry[0])?.label || entry[0], description: describe(entry), onClick: () => save(vars.filter(([key]) => key !== entry[0])), children: "Remove" }) }, entry[0]))), fromDefault.map((entry) => (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.Field, { label: presetFor(entry[0])?.label || entry[0], description: `${describe(entry)} (from Default)` }) }, `default-${entry[0]}`))), canAdd ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => DFL.showModal(SP_JSX.jsx(AddEnvVarModal, { current: vars, onAdd: (key, value) => save([...vars.filter(([k]) => k !== key), [key, value]]) })), children: "Add Environment Variable" }) })) : null] }));
}

function SelectEdit({ label, description, value, options, onChange }) {
    const rgOptions = options.map((option) => (typeof option === "string" ? { data: option, label: option } : option));
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: label === undefined ? (SP_JSX.jsx(DFL.Dropdown, { selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) : (SP_JSX.jsx(DFL.DropdownItem, { label: label, description: description, selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) }));
}

// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default.
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
function Note({ text }) {
    return SP_JSX.jsx("div", { style: { padding: "4px 16px 8px", fontSize: "12px", lineHeight: "16px", opacity: 0.62 }, children: text });
}
function GameOnlyToggle({ checked, onChange }) {
    return SP_JSX.jsx(DFL.ToggleField, { label: "Use Per-Game Settings", checked: checked, onChange: onChange });
}
function XaliaToggle({ values, patch, live }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Disable Xalia", description: timed(live, APPLIES_NEXT_LAUNCH, "Saves CPU in every game. Turn off for a game whose menus only work with a mouse, if you can't tap the screen (e.g. docked)."), checked: values.disableXalia !== false, onChange: (checked) => patch({ disableXalia: checked }) }) }));
}
function KeepCompressedToggle({ values, patch, live }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Keep Images Compressed", description: timed(live, APPLIES_NEXT_LAUNCH, "Can raise FPS. ARM Proton and emulators on the built-in Mesas only. Turn off if colours look wrong."), checked: values.keepCompressed === true, onChange: (on) => patch({ keepCompressed: on }) }) }));
}
function TouchField({ values, patch, live }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Disable Touchscreen", description: timed(live, APPLIES_NOW, "Stops stray touches during play."), checked: values.touchDisabled === true, onChange: (on) => patch({ touchDisabled: on }) }) }));
}
function PrimeCoreToggle({ primeCore, values, patch, live }) {
    if (!primeCore)
        return null;
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Fastest Core First", description: timed(live, APPLIES_NEXT_LAUNCH, `Gives the game the fastest core (CPU ${primeCore}) as its first one. Can help games that do most of their work on one core.`), checked: values.primeCoreFirst === true, onChange: (on) => patch({ primeCoreFirst: on }) }) }));
}
const pick = (options, value) => {
    const v = String(value ?? "");
    return options.some((option) => option.data === v) ? v : "";
};
const labelOf = (options, value) => options.find((o) => o.data === value)?.label || value;
const withAllGames = (options, current) => [
    { data: "", label: `Default (${labelOf(options, current)})` },
    ...options,
];
/** Per-game override ("" = follow Default); the backend retunes a running game on save. */
function FanField({ config, values, patch, live }) {
    const options = withAllGames(fanOptions, config.fanMode);
    return (SP_JSX.jsx(SelectEdit, { label: "Fan Curve", description: timed(live, APPLIES_NOW), value: pick(options, values.fanMode), options: options, onChange: (id) => patch({ fanMode: id }) }));
}
function SchedulerField({ config, values, patch, live }) {
    const options = withAllGames(lavdOptions, config.lavdMode);
    return (SP_JSX.jsx(SelectEdit, { label: "CPU Scheduler", description: timed(live, APPLIES_NOW), value: pick(options, values.lavdMode), options: options, onChange: (id) => patch({ lavdMode: id }) }));
}
function ResetGame({ name, onReset }) {
    return (SP_JSX.jsx(DFL.PanelSection, { children: SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => DFL.showModal(SP_JSX.jsx(DFL.ConfirmModal, { strTitle: `Reset ${name}?`, strDescription: "Clears this game's own settings so it uses Default again. Proton Version is Steam's setting and stays as it is.", strOKButtonText: "Reset", onOK: onReset })), children: "Reset This Game" }) }) }));
}
/** Every per-game control, shared by the Games tab and the library context-menu modal. */
function TweakFields({ config, appid, name, values, patch, live, onReset }) {
    // Proton pick is Steam's own per-game compat setting (see lib/compat.ts) — read live and
    // written straight back to Steam, so it mirrors the game-properties dropdown both ways.
    const [compatTools, setCompatTools] = SP_REACT.useState([]);
    const [compat, setCompat] = SP_REACT.useState({ tool: "", label: "" });
    SP_REACT.useEffect(() => {
        setCompatTools([]);
        setCompat({ tool: "", label: "" });
        if (!appid)
            return;
        let mounted = true;
        availableCompatTools(appid).then((tools) => {
            if (mounted)
                setCompatTools(tools);
        });
        const unregister = registerForCompatTool(appid, (next) => {
            if (mounted)
                setCompat(next);
        });
        return () => {
            mounted = false;
            unregister();
        };
    }, [appid]);
    const compatOptions = [
        { data: "", label: "Steam default" },
        ...compatTools.map((tool) => ({ data: tool.name, label: tool.label })),
    ];
    const compatValue = compatOptions.some((option) => option.data === compat.tool) ? compat.tool : "";
    const steamChoice = !compatValue && compat.label ? `Steam picks ${compat.label}.` : undefined;
    const presets = config.fexProfiles || {};
    const storedProfile = values.fexProfile;
    const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
    const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
    const storedLatency = String(values.audioLatency ?? "");
    const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
    const mesaOptions = config.mesaVersions?.length ? config.mesaVersions : [{ data: "", label: "System default" }];
    const storedMesa = String(values.mesaVersion ?? "");
    const mesaValue = mesaOptions.some((option) => option.data === storedMesa) ? storedMesa : "";
    const nextLaunch = timed(live, APPLIES_NEXT_LAUNCH);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [live ? null : SP_JSX.jsx(Note, { text: "Changes apply when you start the game." }), SP_JSX.jsxs(DFL.PanelSection, { title: "PERFORMANCE", children: [SP_JSX.jsx(FanField, { config: config, values: values, patch: patch, live: live }), SP_JSX.jsx(SchedulerField, { config: config, values: values, patch: patch, live: live })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "GAME TWEAKS", children: [SP_JSX.jsx(SelectEdit, { label: "Proton Version", description: timed(live, APPLIES_NEXT_LAUNCH, steamChoice), value: compatValue, options: compatOptions, onChange: (tool) => {
                            setCompat((current) => ({ ...current, tool: String(tool) }));
                            setCompatTool(appid, String(tool));
                        } }), SP_JSX.jsx(SelectEdit, { label: "FEX Preset", description: nextLaunch, value: fexValue, options: fexOptions, onChange: (id) => patch({ fexProfile: id }) }), SP_JSX.jsx(SelectEdit, { label: "Mesa Version", description: nextLaunch, value: mesaValue, options: mesaOptions, onChange: (id) => patch({ mesaVersion: id }) }), SP_JSX.jsx(KeepCompressedToggle, { values: values, patch: patch, live: live }), SP_JSX.jsx(SelectEdit, { label: "Audio Buffer", description: nextLaunch, value: audioValue, options: audioLatencyOptions, onChange: (id) => patch({ audioLatency: id }) }), SP_JSX.jsx(TouchField, { values: values, patch: patch, live: live }), SP_JSX.jsx(XaliaToggle, { values: values, patch: patch, live: live })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "ADVANCED", children: [SP_JSX.jsx(PrimeCoreToggle, { primeCore: config.primeCore, values: values, patch: patch, live: live }), SP_JSX.jsx(EnvVarsField, { own: config.tweaks.games[appid]?.envVars, inherited: config.tweaks.global.envVars, live: live, onChange: (envVars) => patch({ envVars }) })] }), SP_JSX.jsx(ResetGame, { name: name, onReset: onReset })] }));
}
/** The fields that undo a game's own settings, keeping its saved name. */
function resetFields(config, appid) {
    const own = config.tweaks.games[appid] || {};
    const cleared = Object.fromEntries(Object.keys(own).filter((key) => key !== "name").map((key) => [key, null]));
    return { ...cleared, enabled: false };
}

function Games({ config, setConfig, patch, reload }) {
    const runtimeGame = config.game;
    const games = availableGames(config);
    const game = config.selectedGame || runtimeGame || null;
    const tweaks = config.tweaks;
    const gameSettings = game?.appid ? tweaks.games[game.appid] || {} : {};
    const editingDefault = !game?.appid;
    const perGameEnabled = !!(game?.appid && gameSettings.enabled === true);
    const values = editingDefault || !perGameEnabled ? tweaks.global : { ...tweaks.global, ...gameSettings };
    const patchSettings = (fields) => {
        if (editingDefault)
            patch("", fields);
        else if (perGameEnabled)
            patch(game.appid, { ...fields, enabled: true, name: game.name || "" });
    };
    const setPerGameEnabled = (enabled) => {
        if (game?.appid)
            patch(game.appid, { enabled, name: game.name || "" });
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
    // Default's fan and scheduler are the system modes, not tweaks.global.
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
    // Default reaches whatever is running; a game's own settings only reach that game.
    const live = !!runtimeGame?.appid && (editingDefault || runtimeGame.appid === game?.appid);
    const nextLaunch = timed(live, APPLIES_NEXT_LAUNCH);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "PERFORMANCE & GAME TWEAKS", children: [SP_JSX.jsx(SelectEdit, { label: "Game", value: game?.appid || "", options: editTargetOptions(config), onChange: setSelectedGame }), !editingDefault ? SP_JSX.jsx(GameOnlyToggle, { checked: perGameEnabled, onChange: setPerGameEnabled }) : null] }), editingDefault ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [live ? null : SP_JSX.jsx(Note, { text: "Changes apply to every game you start." }), SP_JSX.jsxs(DFL.PanelSection, { title: "PERFORMANCE", children: [SP_JSX.jsx(SelectEdit, { label: "Fan Curve", description: live ? APPLIES_NOW : "Outside games too.", value: config.fanMode, options: fanOptions, onChange: (mode) => applyMode(setFanMode, mode) }), SP_JSX.jsx(SelectEdit, { label: "CPU Scheduler", description: live ? APPLIES_NOW : "Outside games too.", value: config.lavdMode, options: lavdOptions, onChange: (mode) => applyMode(setLavdMode, mode) })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "GAME TWEAKS", children: [SP_JSX.jsx(SelectEdit, { label: "FEX Preset", description: nextLaunch, value: fexValue, options: fexOptions, onChange: (id) => patchSettings({ fexProfile: id }) }), SP_JSX.jsx(KeepCompressedToggle, { values: values, patch: patchSettings, live: live }), SP_JSX.jsx(SelectEdit, { label: "Audio Buffer", description: nextLaunch, value: audioValue, options: audioLatencyOptions, onChange: (id) => patchSettings({ audioLatency: id }) }), SP_JSX.jsx(TouchField, { values: values, patch: patchSettings, live: live }), SP_JSX.jsx(XaliaToggle, { values: values, patch: patchSettings, live: live })] }), config.primeCore || parseEnvVars(tweaks.global.envVars).length ? (SP_JSX.jsxs(DFL.PanelSection, { title: "ADVANCED", children: [SP_JSX.jsx(PrimeCoreToggle, { primeCore: config.primeCore, values: values, patch: patchSettings, live: live }), SP_JSX.jsx(EnvVarsField, { own: tweaks.global.envVars, canAdd: false, live: live, onChange: (envVars) => patchSettings({ envVars }) })] })) : null] })) : perGameEnabled ? (SP_JSX.jsx(TweakFields, { config: config, appid: game.appid, name: game.name || `App ${game.appid}`, values: values, patch: patchSettings, live: live, onReset: () => patch(game.appid, resetFields(config, game.appid)) })) : null] }));
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
    const [needsAbl, setNeedsAbl] = SP_REACT.useState(false);
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
        bootloaderStatus()
            .then((s) => {
            if (!cancelled)
                setNeedsAbl(s.needsOpenAbl);
        })
            .catch(() => { });
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
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "SYSTEM UPDATES", children: [needsAbl ? (SP_JSX.jsx(DFL.Field, { label: "OpenABL needed", description: "OpenABL is mandatory going forward. Until it's installed, you'll be unable to install future updates. Install it from Pocknix Tools > Advanced > Bootloader." })) : null, !running ? SP_JSX.jsx(DFL.Field, { label: "Status", description: summary }) : null, !running && updates && updates.length > 0 ? (SP_JSX.jsxs("div", { className: "pocknix-note", children: [updates.slice(0, SHOWN_UPDATES).map((update) => (SP_JSX.jsx("div", { children: `${update.name} ${update.current} → ${update.latest}` }, update.name))), updates.length > SHOWN_UPDATES ? SP_JSX.jsx("div", { children: `… and ${updates.length - SHOWN_UPDATES} more` }) : null] })) : null, SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: check, children: checking ? "Checking…" : "Check for Updates" }) }), !running && updates && updates.length > 0 ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: confirmStart, children: "Install Updates" }) })) : null, running ? SP_JSX.jsx(DFL.Field, { label: "Updating\u2026", description: "Safe to close this menu. Do not power off." }) : null, finished ? (SP_JSX.jsx(DFL.Field, { label: status.exitCode === 0 ? "Update complete" : `Update failed (code ${status.exitCode})`, description: status.exitCode === 0
                            ? "Restart to finish applying updates."
                            : status.ablRefused
                                ? "This update needs OpenABL. Install it from Pocknix Tools > Advanced > Bootloader, restart, then update again."
                                : "See the log below." })) : null, finished && status.exitCode === 0 ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: reboot, children: "Restart Now" }) })) : null, (running || (finished && status.exitCode !== 0)) && status?.log ? (SP_JSX.jsx("div", { className: "pocknix-note pocknix-log", children: status.log })) : null, error ? SP_JSX.jsx(DFL.Field, { label: "Error", description: error }) : null] }), snap?.supported ? (SP_JSX.jsxs(DFL.PanelSection, { title: "ROLLBACK", children: [snap.rolledBack && !rollbackDone ? (SP_JSX.jsx(DFL.Field, { label: "System was rolled back", description: `Restored from snapshot ${snap.rolledBack.fromSnapshot} (${fmtDate(snap.rolledBack.ts)}).${onLastSnapshot ? " Rollback will be available again after the next update." : ""}` })) : null, rollbackDone ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.Field, { label: "Rolled back", description: "Reboot to finish switching to the restored system." }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: reboot, children: "Reboot Now" }) })] })) : onLastSnapshot ? null : lastSnapshot ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.Field, { label: "Last snapshot", description: `${fmtDate(lastSnapshot.created)}${lastSnapshot.targets ? ` — ${lastSnapshot.targets}` : ""}` }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: confirmRollback, children: rollingBack ? "Rolling back…" : "Roll Back Last Update" }) })] })) : (SP_JSX.jsx(DFL.Field, { label: "No snapshots yet", description: "A snapshot is taken automatically before every update." })), rollbackError ? SP_JSX.jsx(DFL.Field, { label: "Rollback error", description: rollbackError }) : null, SP_JSX.jsx(DFL.Field, { label: "Storage", description: `${gib(snap.freeBytes)} GB free${snap.lowSpace ? " — LOW: snapshots may be skipped" : ""}` })] })) : null] }));
}

function Content() {
    const [tab, setTab] = SP_REACT.useState("Games");
    const [config, setConfig] = SP_REACT.useState(null);
    const [message, setMessage] = SP_REACT.useState("Loading");
    const patchSeq = SP_REACT.useRef(0);
    const load = SP_REACT.useCallback(async () => {
        const seq = patchSeq.current;
        try {
            const next = await getConfig();
            next.game = currentGame();
            // get_config is slow (it re-parses the Steam library): a save made meanwhile is newer than its tweaks.
            const tweaks = (current) => (current && patchSeq.current !== seq ? current.tweaks : next.tweaks);
            setConfig((current) => ({ ...next, tweaks: tweaks(current), selectedGame: current ? current.selectedGame : next.game || null }));
        }
        catch (error) {
            setMessage(String(error));
        }
    }, []);
    // alwaysRender keeps this panel mounted while the QAM is closed, so the library modal's
    // saves only show up if every reopen re-reads them.
    const visible = useQuickAccessVisible();
    SP_REACT.useEffect(() => {
        if (visible)
            load();
    }, [visible, load]);
    const patch = usePatchTweaks(setConfig, load, patchSeq);
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
    if (!config)
        return SP_JSX.jsx(DFL.PanelSection, { title: "Pocknix Control", children: SP_JSX.jsx(DFL.Field, { label: message }) });
    const tabContent = (content) => (SP_JSX.jsx("div", { className: "pocknix-control-tab-content", children: content }));
    const tabs = [
        { id: "Games", title: tabIcons.Games, content: tabContent(SP_JSX.jsx(Games, { config: config, setConfig: setConfig, patch: patch, reload: load })) },
        ...(config.led.available
            ? [{ id: "StickLights", title: tabIcons.StickLights, content: tabContent(SP_JSX.jsx(StickLights, { config: config, setConfig: setConfig, reload: load })) }]
            : []),
        { id: "AddGame", title: tabIcons.AddGame, content: tabContent(SP_JSX.jsx(AddGameSection, {})) },
        { id: "Updater", title: tabIcons.Updater, content: tabContent(SP_JSX.jsx(Updater, {})) },
    ];
    return (SP_JSX.jsxs("div", { className: "pocknix-control-tabs", children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsx(DFL.Tabs, { activeTab: tab, onShowTab: setTab, tabs: tabs })] }));
}

/** Standalone per-game settings, opened from the library context menu. */
function GameSettingsModal({ appid, name, closeModal }) {
    const [config, setConfig] = SP_REACT.useState(null);
    const reload = () => getConfig().then(setConfig).catch(() => { });
    const patchGame = usePatchTweaks(setConfig, reload);
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
    const patch = (fields) => patchGame(appid, { ...fields, enabled: true, name });
    return (SP_JSX.jsxs(DFL.ModalRoot, { closeModal: closeModal, children: [SP_JSX.jsx("div", { style: { fontWeight: 600, marginBottom: "8px" }, children: name || `App ${appid}` }), SP_JSX.jsx(GameOnlyToggle, { checked: enabled, onChange: (on) => patchGame(appid, { enabled: on, name }) }), enabled ? (SP_JSX.jsx(TweakFields, { config: config, appid: appid, name: name || `App ${appid}`, values: values, patch: patch, live: currentGame()?.appid === appid, onReset: () => patchGame(appid, resetFields(config, appid)) })) : null] }));
}

// LibraryContextMenu is not exported: reach it via classname marker -> `navigator:` wrapper ->
// fake-render. Steam internals are unversioned: each step is guarded, so a change costs the item.
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
        // The builder returns either a plain item array or an element with children.
        const patch = DFL.afterPatch(LibraryContextMenu.prototype, "BuildManageSubmenu", function (_args, ret) {
            try {
                const overview = this.props?.overview;
                const appid = overview?.appid;
                if (!appid || isPlainTile(String(Number(appid) >>> 0), String(overview?.display_name ?? "")))
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

// Reports every Steam game start/stop to the backend, which owns the touchscreen tweak (touch.py).
// Shortcut appids are unsigned above 2^31, hence the >>> 0.
function registerTouchLifetime() {
    const report = (appid, running) => gameLifetime(appid, running).catch(() => { });
    // A plugin reload mid-game misses the start notification.
    const running = currentGame();
    if (running)
        report(running.appid, true);
    try {
        const handle = window.SteamClient?.GameSessions?.RegisterForAppLifetimeNotifications?.((update) => {
            const appid = String(Number(update?.unAppID) >>> 0);
            // Default's Disable Touchscreen must not lock the touch UI of Pocknix Tools or the Store.
            if (!isPlainTile(appid))
                report(appid, !!update?.bRunning);
        });
        return () => handle?.unregister?.();
    }
    catch (error) {
        return () => { };
    }
}

var index = definePlugin(() => {
    const unpatchContextMenu = patchLibraryContextMenu();
    const unregisterTouch = registerTouchLifetime();
    const unregisterDownloads = registerDownloadWrapper((appid) => isGame(appid));
    getConfig()
        .then(async (config) => {
        await wrapAllGames(installedSteamGames(config));
        await wrapShortcuts(nonSteamShortcuts().map((shortcut) => shortcut.appid));
        await unwrapPlainTiles(config.plainTiles || [], plainTileShortcuts());
    })
        .catch(() => { });
    return {
        name: "Pocknix Control",
        content: SP_JSX.jsx(Content, {}),
        icon: SP_JSX.jsx("div", { style: { fontWeight: 700 }, children: "P" }),
        alwaysRender: true,
        onDismount() {
            unpatchContextMenu();
            unregisterTouch();
            unregisterDownloads();
        },
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
