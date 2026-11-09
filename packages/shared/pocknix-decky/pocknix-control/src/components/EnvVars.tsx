import { ButtonItem, ConfirmModal, DropdownItem, Field, PanelSectionRow, showModal } from "@decky/ui";
import { useState } from "react";
import { envPresets, parseEnvVars, presetFor, serializeEnvVars } from "../lib/envVars";
import type { EnvVar } from "../lib/envVars";
import { APPLIES_NEXT_LAUNCH } from "../lib/applies";

function AddEnvVarModal({ current, onAdd, closeModal }: {
  current: EnvVar[];
  onAdd: (key: string, value: string) => void;
  closeModal?: () => void;
}) {
  const [key, setKey] = useState(envPresets[0].key);
  const preset = presetFor(key)!;
  const existing = current.find(([k]) => k === key)?.[1];
  const [value, setValue] = useState<string | null>(null);
  const picked = value ?? (preset.values.some((v) => v.data === existing) ? existing! : preset.values[0].data);
  return (
    <ConfirmModal
      strTitle="Add Environment Variable"
      strDescription={preset.description}
      strOKButtonText="Add"
      onCancel={() => closeModal?.()}
      onOK={() => {
        onAdd(key, picked);
        closeModal?.();
      }}
    >
      <DropdownItem
        label="Variable"
        selectedOption={key}
        rgOptions={envPresets.map((p) => ({ data: p.key, label: p.label }))}
        onChange={(option) => {
          setKey(String(option.data));
          setValue(null);
        }}
      />
      {preset.values.length > 1 ? (
        <DropdownItem label="Value" selectedOption={picked} rgOptions={preset.values} onChange={(option) => setValue(String(option.data))} />
      ) : null}
    </ConfirmModal>
  );
}

const describe = ([key, value]: EnvVar) => `${key}=${value}`;

/** own = this scope's envVars; inherited = the Default list a game adds its own on top of.
 *  Default has no Add: only variables saved there before can be seen and removed. */
export function EnvVarsField({ own, inherited, canAdd = true, onChange }: {
  own: unknown;
  inherited?: unknown;
  canAdd?: boolean;
  onChange: (envVars: string | null) => void;
}) {
  const vars = parseEnvVars(own);
  const fromDefault = parseEnvVars(inherited).filter(([key]) => !vars.some(([k]) => k === key));
  const save = (next: EnvVar[]) => onChange(serializeEnvVars(next));
  if (!canAdd && !vars.length) return null;
  return (
    <>
      <PanelSectionRow>
        <Field label="Environment Variables" description={APPLIES_NEXT_LAUNCH} />
      </PanelSectionRow>
      {vars.map((entry) => (
        <PanelSectionRow key={entry[0]}>
          <ButtonItem
            label={presetFor(entry[0])?.label || entry[0]}
            description={describe(entry)}
            onClick={() => save(vars.filter(([key]) => key !== entry[0]))}
          >
            Remove
          </ButtonItem>
        </PanelSectionRow>
      ))}
      {fromDefault.map((entry) => (
        <PanelSectionRow key={`default-${entry[0]}`}>
          <Field label={presetFor(entry[0])?.label || entry[0]} description={`${describe(entry)} (from Default)`} />
        </PanelSectionRow>
      ))}
      {canAdd ? (
        <PanelSectionRow>
          <ButtonItem
            layout="below"
            onClick={() =>
              showModal(
                <AddEnvVarModal
                  current={vars}
                  onAdd={(key, value) => save([...vars.filter(([k]) => k !== key), [key, value]])}
                />,
              )
            }
          >
            Add Environment Variable
          </ButtonItem>
        </PanelSectionRow>
      ) : null}
    </>
  );
}
