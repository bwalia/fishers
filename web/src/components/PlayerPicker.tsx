"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";

export type PickablePlayer = {
  id: string;
  name: string;
  /// Where they bat, so the list reads like a team sheet rather than an
  /// alphabetical index.
  position: number;
  /// Already at the crease, or already bowling — shown, but not choosable.
  takenBy?: string;
};

/// Choose one player out of a named XI, by typing.
///
/// Unlike `PersonPicker` this only ever yields somebody who is actually in the
/// side: a striker is a player id the engine has to recognise, not a name
/// somebody typed. Anyone unavailable stays visible with the reason, because
/// "where is Alex?" is a question a scorer will otherwise ask out loud.
export function PlayerPicker({
  label,
  hint,
  players,
  value,
  onChange,
  placeholder = "Type a name",
}: {
  label: string;
  hint?: string;
  players: PickablePlayer[];
  value: string;
  onChange: (id: string) => void;
  placeholder?: string;
}) {
  const chosen = players.find((p) => p.id === value) ?? null;
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const boxRef = useRef<HTMLDivElement>(null);
  const listId = useId();

  const matches = useMemo(() => {
    const term = query.trim().toLowerCase();
    const usable = players.filter((p) => !p.takenBy);
    const taken = players.filter((p) => p.takenBy);
    const hit = (p: PickablePlayer) => p.name.toLowerCase().includes(term);
    if (!term) return [...usable, ...taken];
    // A name that starts with what you typed comes first: "da" should reach
    // Dan before Sundar.
    const starts = usable.filter((p) => p.name.toLowerCase().startsWith(term));
    const rest = usable.filter((p) => !p.name.toLowerCase().startsWith(term) && hit(p));
    return [...starts, ...rest, ...taken.filter(hit)];
  }, [players, query]);

  useEffect(() => setActive(0), [query]);

  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => {
      if (!boxRef.current?.contains(e.target as Node)) {
        setOpen(false);
        setQuery("");
      }
    };
    document.addEventListener("mousedown", away);
    return () => document.removeEventListener("mousedown", away);
  }, [open]);

  const choose = (p: PickablePlayer) => {
    if (p.takenBy) return;
    onChange(p.id);
    setQuery("");
    setOpen(false);
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Escape") {
      setOpen(false);
      setQuery("");
      return;
    }
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!open) return setOpen(true);
      setActive((i) => {
        const next = e.key === "ArrowDown" ? i + 1 : i - 1;
        return (next + matches.length) % Math.max(matches.length, 1);
      });
      return;
    }
    if (e.key === "Enter" && open && matches[active]) {
      e.preventDefault();
      choose(matches[active]);
    }
  };

  return (
    <div className="player-picker" ref={boxRef}>
      <label htmlFor={`${listId}-input`}>{label}</label>
      {hint && <span className="player-picker-hint">{hint}</span>}

      <div className={`player-field${open ? " open" : ""}`}>
        {/* The chosen player stays visible while you type over them, so you
            can see what you are replacing. */}
        {chosen && !query && (
          <span className="player-chosen">
            <span className="player-no num">{chosen.position}</span>
            {chosen.name}
          </span>
        )}
        <input
          id={`${listId}-input`}
          role="combobox"
          aria-expanded={open}
          aria-controls={listId}
          aria-autocomplete="list"
          aria-activedescendant={open && matches[active] ? `${listId}-${active}` : undefined}
          autoComplete="off"
          value={query}
          placeholder={chosen && !query ? "" : placeholder}
          onFocus={() => setOpen(true)}
          onKeyDown={onKeyDown}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
        />
        {/* The universal "there is a list behind this" mark — without it the
            field reads as a plain text box and nobody tries typing. */}
        <svg className="player-caret" width="12" height="12" viewBox="0 0 12 12" aria-hidden>
          <path d="M2 4.5 6 8.5 10 4.5" fill="none" stroke="currentColor"
                strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>

      {open && (
        <ul className="player-list" id={listId} role="listbox">
          {matches.map((p, i) => (
            <li key={p.id} id={`${listId}-${i}`} role="option" aria-selected={i === active}>
              <button
                type="button"
                className={`player-row${i === active ? " active" : ""}${
                  p.takenBy ? " taken" : ""
                }${p.id === value ? " chosen" : ""}`}
                disabled={!!p.takenBy}
                onMouseDown={(e) => {
                  e.preventDefault();
                  choose(p);
                }}
                onMouseEnter={() => setActive(i)}
              >
                <span className="player-no num">{p.position}</span>
                <span className="player-name">{p.name}</span>
                {p.takenBy && <span className="player-taken">{p.takenBy}</span>}
              </button>
            </li>
          ))}
          {matches.length === 0 && <li className="player-empty">Nobody by that name.</li>}
        </ul>
      )}
    </div>
  );
}
