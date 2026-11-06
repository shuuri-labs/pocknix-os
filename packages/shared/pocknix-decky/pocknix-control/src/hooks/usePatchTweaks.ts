import { useCallback, useRef } from "react";
import type { Dispatch, MutableRefObject, SetStateAction } from "react";
import { patchTweaks } from "../backend";
import { clone } from "../lib/util";
import type { Config } from "../types";

export function applyPatch(config: Config, appid: string, fields: Record<string, any>): Config {
  const next = clone(config);
  if (appid && !next.tweaks.games[appid]) next.tweaks.games[appid] = {};
  const target = appid ? next.tweaks.games[appid] : next.tweaks.global;
  for (const [key, value] of Object.entries(fields)) {
    if (value === null) delete target[key];
    else target[key] = value;
  }
  return next;
}

/** Shows the edit at once and sends only the changed fields ("" = Default). */
export function usePatchTweaks(
  setConfig: Dispatch<SetStateAction<Config | null>>,
  onError?: (error: unknown) => void,
  seq?: MutableRefObject<number>,
) {
  // Replies can arrive out of order; only the newest may replace what is on screen.
  const own = useRef(0);
  const latest = seq ?? own;
  return useCallback(
    (appid: string, fields: Record<string, any>) => {
      setConfig((current) => (current ? applyPatch(current, appid, fields) : current));
      const seq = ++latest.current;
      patchTweaks(appid, fields)
        .then((tweaks) => {
          if (seq === latest.current) setConfig((current) => (current ? { ...current, tweaks } : current));
        })
        .catch((error) => onError?.(error));
    },
    [setConfig, onError],
  );
}
