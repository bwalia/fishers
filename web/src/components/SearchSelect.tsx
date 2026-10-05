"use client";

import { useEffect, useId, useRef, useState } from "react";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

export type Choice = { id: string; name: string };

/// Pick one thing out of a list that may be long, by typing at it.
///
/// A row of buttons is a fine filter for three clubs and a wall of text for
/// thirty — and whoever has thirty is exactly the person who needs the filter.
/// So the options are fetched as they are typed rather than gathered from
/// whatever happens to be on screen: the list on the page is one window onto
/// the data, and a filter built from that window can only ever offer what is
/// already visible.
///
/// `search` is called with the trimmed term, debounced, and may hit the
/// network. It is also called with an empty term when the panel opens, which
/// is what fills the list before anybody types.
export function SearchSelect({
  value,
  onChange,
  search,
  label,
  anyLabel,
  placeholder,
}: {
  /// The chosen id, or "" for the "any" option.
  value: string;
  onChange: (id: string, name: string) => void;
  search: (term: string) => Promise<Choice[]>;
  /// What this picks, for the screen reader and the closed button.
  label: string;
  /// The "no filter" option, e.g. "All clubs".
  anyLabel: string;
  placeholder?: string;
}) {
  const t = useT();
  const id = useId();
  const [open, setOpen] = useState(false);
  const [term, setTerm] = useState("");
  const [found, setFound] = useState<Choice[] | null>(null);
  const [chosenName, setChosenName] = useState("");
  const box = useRef<HTMLDivElement>(null);
  const input = useRef<HTMLInputElement>(null);

  // Debounced, and the late answer to an earlier keystroke is dropped: typing
  // "lud" fires three searches and the one that matters is the last.
  useEffect(() => {
    if (!open) return;
    let live = true;
    const timer = window.setTimeout(() => {
      search(term.trim())
        .then((list) => live && setFound(list))
        .catch(() => live && setFound([]));
    }, term.trim() ? 200 : 0);
    return () => {
      live = false;
      window.clearTimeout(timer);
    };
  }, [term, open, search]);

  useEffect(() => {
    if (open) input.current?.focus();
    else setTerm("");
  }, [open]);

  // Clicking away closes it, as does Escape — a panel you cannot dismiss
  // without choosing something is a trap.
  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => {
      if (box.current && !box.current.contains(e.target as Node)) setOpen(false);
    };
    const key = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", away);
    document.addEventListener("keydown", key);
    return () => {
      document.removeEventListener("mousedown", away);
      document.removeEventListener("keydown", key);
    };
  }, [open]);

  const pick = (choice: Choice) => {
    setChosenName(choice.id ? choice.name : "");
    onChange(choice.id, choice.name);
    setOpen(false);
  };

  const shown = value ? chosenName || label : anyLabel;

  return (
    <div className="search-select" ref={box}>
      <button
        type="button"
        className={`chip search-select-open${value ? " on" : ""}`}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={`${id}-list`}
        onClick={() => setOpen((o) => !o)}
      >
        <Icon name="search" size={14} />
        <span className="search-select-value">{shown}</span>
        <span aria-hidden>{open ? "▴" : "▾"}</span>
      </button>

      {open && (
        <div className="search-select-panel">
          <input
            ref={input}
            className="people-search"
            value={term}
            onChange={(e) => setTerm(e.target.value)}
            placeholder={placeholder ?? label}
            aria-label={label}
            role="combobox"
            aria-expanded
            aria-controls={`${id}-list`}
            aria-autocomplete="list"
          />
          <ul className="people-list" id={`${id}-list`} role="listbox" aria-label={label}>
            <li>
              <button
                type="button"
                role="option"
                aria-selected={value === ""}
                className={value === "" ? "on" : undefined}
                onClick={() => pick({ id: "", name: anyLabel })}
              >
                <span className="people-name">{anyLabel}</span>
                <span className="people-tick" aria-hidden>{value === "" ? "✓" : ""}</span>
              </button>
            </li>
            {(found ?? []).map((c) => (
              <li key={c.id}>
                <button
                  type="button"
                  role="option"
                  aria-selected={value === c.id}
                  className={value === c.id ? "on" : undefined}
                  onClick={() => pick(c)}
                >
                  <span className="people-name">{c.name}</span>
                  <span className="people-tick" aria-hidden>{value === c.id ? "✓" : ""}</span>
                </button>
              </li>
            ))}
          </ul>
          {found !== null && found.length === 0 && term.trim() && (
            <p className="muted people-empty">{t("ev.nothing_by_that_name")}</p>
          )}
          {found === null && <div className="skeleton" style={{ height: 40 }} />}
        </div>
      )}
    </div>
  );
}
