import { Dropdown, DropdownItem, PanelSectionRow } from "@decky/ui";
import type { ReactNode } from "react";
import type { DropdownChoice } from "../types";

type Option = string | DropdownChoice;

export function SelectEdit({ label, value, options, onChange }: {
  label?: ReactNode;
  value: any;
  options: Option[];
  onChange: (data: any) => void;
}) {
  const rgOptions = options.map((option) => (typeof option === "string" ? { data: option, label: option } : option));
  return (
    <PanelSectionRow>
      {label === undefined ? (
        <Dropdown selectedOption={value} rgOptions={rgOptions} onChange={(option) => onChange(option.data)} />
      ) : (
        <DropdownItem label={label} selectedOption={value} rgOptions={rgOptions} onChange={(option) => onChange(option.data)} />
      )}
    </PanelSectionRow>
  );
}
