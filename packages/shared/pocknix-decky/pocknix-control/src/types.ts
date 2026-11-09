export interface GameTweak {
  enabled?: boolean;
  name?: string;
  fexProfile?: string;
  /** Audio buffer in ms (PULSE_LATENCY_MSEC exported by pocknix-game-launch); "" = game default. */
  audioLatency?: string;
  /** Turnip series pin ("25.2"); pocknix-game-launch picks arch + point release. "" = default. */
  mesaVersion?: string;
  /** Shell-quoted KEY=VALUE words, added to the Default list (a game's value wins); launch options win over both. */
  envVars?: string;
  /** Per-game fan curve override, applied for the game session only; "" = follow Default. */
  fanMode?: string;
  /** Per-game scx_lavd mode override, applied for the game session only; "" = follow Default. */
  lavdMode?: string;
  /** pocknix-game-launch exports PROTON_USE_XALIA=0 unless false; absent = disabled. */
  disableXalia?: boolean;
  /** true = pocknix-game-launch lists the prime core first in Wine's CPU topology. */
  primeCoreFirst?: boolean;
  /** true = the touchscreen is inhibited while this game runs (pocknix_control/touch.py). */
  touchDisabled?: boolean;
  [key: string]: any;
}

export interface Tweaks {
  global: Record<string, any>;
  games: Record<string, GameTweak>;
}

export interface InstalledGame {
  appid: string;
  name: string;
}

export interface FexProfile {
  label: string;
  config?: Record<string, string>;
  /** STEAM_COMPAT_FEX_CONFIG string pocknix-game-launch exports for Valve's x86 FEX; "" = none. */
  steam?: string;
}

export interface GameRef {
  appid: string;
  name: string;
  nonSteam?: boolean;
}

export interface Config {
  fanMode: string;
  lavdMode: string;
  tweaks: Tweaks;
  fexProfiles: Record<string, FexProfile>;
  /** Turnip payload choices, one per series (data "25.2"); the label marks single-arch series. */
  mesaVersions?: DropdownChoice[];
  installedGames: InstalledGame[];
  led: LedConfig;
  /** Pocknix tiles launched without pocknix-game-launch (Tools, Store): no per-game settings. */
  plainTiles?: PlainTile[];
  /** cores.sh's prime core ("7"); "" = the board has none, so the toggle is hidden. */
  primeCore?: string;
  game?: GameRef | null;
  selectedGame?: GameRef | null;
}

export interface DropdownChoice {
  data: string;
  label: string;
}

export interface UpdateInfo {
  name: string;
  current: string;
  latest: string;
}

export interface UpdateStatus {
  running: boolean;
  log: string;
  exitCode: number | null;
  ablRefused: boolean;
}

export interface SnapshotInfo {
  id: string;
  created: string;
  ok: boolean;
  /** true when that transaction included a kernel (rollback restores /flash boot files too) */
  kernel: boolean;
  targets: string;
}

export interface SnapshotStatus {
  supported: boolean;
  freeBytes: number;
  totalBytes: number;
  lowSpace: boolean;
  rebootRequired: boolean;
  rolledBack: { fromSnapshot: string; ts: string } | null;
  /** oldest -> newest; "roll back last update" targets the last entry */
  snapshots: SnapshotInfo[];
}

export interface LedSide {
  r: number;
  g: number;
  b: number;
  brightness: number;
}

export type LedSideKey = "left" | "right" | "both";

export interface LedConfig {
  available: boolean;
  sidesAvailable: boolean;
  enabled: boolean;
  linked: boolean;
  sides: boolean;
  left: LedSide;
  right: LedSide;
}

export interface PlainTile {
  name: string;
  exe: string;
  args: string;
}
