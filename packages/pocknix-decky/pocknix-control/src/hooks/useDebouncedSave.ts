import { useCallback, useEffect, useRef } from "react";
import type { MutableRefObject, Dispatch, SetStateAction } from "react";
import type { Config } from "../types";

interface DebouncedSaveOptions {
  config: Config | null;
  field: "tweaks";
  snapshot: MutableRefObject<string>;
  save: (value: any) => Promise<Config>;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  onError?: (error: unknown) => void;
  delay?: number;
}

export function useDebouncedSave(options: DebouncedSaveOptions) {
  const { config, field, snapshot, save, setConfig, onError, delay = 900 } = options;
  const value = config ? (config as any)[field] : undefined;
  // Latest unsaved edit; written by the debounce timer or the unmount flush below.
  const pending = useRef<{ value: any; serialized: string } | null>(null);

  const flush = useCallback(async () => {
    const entry = pending.current;
    if (!entry) return;
    pending.current = null;
    try {
      const next = await save(entry.value);
      snapshot.current = JSON.stringify((next as any)[field]);
      setConfig((stored) => {
        if (!stored) return next;
        if (JSON.stringify((stored as any)[field]) !== entry.serialized) return stored;
        return { ...stored, [field]: (next as any)[field] };
      });
    } catch (error) {
      onError?.(error);
    }
  }, [save, field, snapshot, setConfig, onError]);
  const flushRef = useRef(flush);
  flushRef.current = flush;

  useEffect(() => {
    if (!config || !snapshot.current) return;
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
  useEffect(() => () => void flushRef.current(), []);
}
