import type { DropdownChoice } from "../types";

export interface EnvPreset {
  key: string;
  label: string;
  description: string;
  /** First entry is the one picked by default. */
  values: DropdownChoice[];
}

const shaderModels = ["6_8", "6_7", "6_6", "6_5", "6_4", "6_3", "6_2", "6_1", "6_0"].map((v) => ({ data: v, label: v.replace("_", ".") }));

export const envPresets: EnvPreset[] = [
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

export const presetFor = (key: string) => envPresets.find((preset) => preset.key === key);

export type EnvVar = [key: string, value: string];

/** POSIX-shell word splitting, the same rules as the launcher's shlex.split. */
export function parseEnvVars(raw: unknown): EnvVar[] {
  if (typeof raw !== "string") return [];
  const words: string[] = [];
  let word = "";
  let inWord = false;
  let quote = "";
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (quote === "'") {
      if (c === "'") quote = "";
      else word += c;
    } else if (quote === '"') {
      if (c === '"') quote = "";
      else if (c === "\\" && i + 1 < raw.length && '"\\$`'.includes(raw[i + 1])) word += raw[++i];
      else word += c;
    } else if (c === "'" || c === '"') {
      quote = c;
      inWord = true;
    } else if (c === "\\" && i + 1 < raw.length) {
      word += raw[++i];
      inWord = true;
    } else if (/\s/.test(c)) {
      if (inWord) words.push(word);
      word = "";
      inWord = false;
    } else {
      word += c;
      inWord = true;
    }
  }
  if (quote) return [];
  if (inWord) words.push(word);
  const vars = new Map<string, string>();
  for (const w of words) {
    const at = w.indexOf("=");
    const key = w.slice(0, at);
    // First one wins, as in the launcher, so the list shows what a launch applies.
    if (at > 0 && /^[A-Za-z_][A-Za-z0-9_]*$/.test(key) && !vars.has(key)) vars.set(key, w.slice(at + 1));
  }
  return Array.from(vars.entries());
}

const quoteValue = (value: string) => (/^[A-Za-z0-9_.,:=\/+@%-]*$/.test(value) ? value : `'${value.replace(/'/g, `'\\''`)}'`);

/** "" -> null so an emptied list removes the key instead of storing a blank. */
export function serializeEnvVars(vars: EnvVar[]): string | null {
  return vars.length ? vars.map(([key, value]) => `${key}=${quoteValue(value)}`).join(" ") : null;
}
