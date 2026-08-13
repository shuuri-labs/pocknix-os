export interface GameTweak {
  enabled?: boolean;
  name?: string;
  fexProfile?: string;
  /** Audio buffer in ms (PULSE_LATENCY_MSEC exported by pocknix-proton-wrapper); "" = game default. */
  audioLatency?: string;
  /** Turnip series pin (e.g. "25.2"); the wrapper resolves arch + point release. "" = default. */
  mesaVersion?: string;
  /** Space-separated KEY=VALUE pairs applied at launch; launch options win over these. */
  envVars?: string;
  /** Per-game fan curve override, applied for the game session only; "" = use global. */
  fanMode?: string;
  /** Per-game scx_lavd mode override, applied for the game session only; "" = use global. */
  lavdMode?: string;
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
  /** Turnip payload choices, one per series (data "25.2"). ARM Proton only. */
  mesaVersions?: DropdownChoice[];
  installedGames: InstalledGame[];
  led: LedConfig;
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

export interface ConfigExportResult {
  /** true = target file already exists and nothing was written (rename/overwrite flow). */
  exists: boolean;
  base: string;
  path: string;
}

export interface ConfigPreview {
  device: string;
  exported: string;
  games: { appid: string; name: string; protonTool: string }[];
}

export interface ConfigImportResult {
  protonTool: string;
}

export interface SdcardInfo {
  present: boolean;
  device?: string;
  sizeBytes?: number;
  fstype?: string;
  label?: string;
  mountpoint?: string;
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
