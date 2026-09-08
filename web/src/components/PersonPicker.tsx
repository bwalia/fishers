"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { roleLabel, type ClubMemberRow } from "@/lib/api";

export type Person = { id: string; name: string; note?: string };

/// Pick somebody out of a club by typing their name.
///
/// A dropdown is fine for a five-a-side squad and useless for a club of two
/// hundred, which is why this filters as you type. It stays a combobox rather
/// than a plain input because the point is to pick a known person, and it
/// still accepts a name nobody recognises — a visiting captain is often not on
/// Fishers at all.
export function PersonPicker({
  label,
  people,
  value,
  onChange,
  placeholder = "Start typing a name",
  loading = false,
  emptyHint,
}: {
  label: string;
  people: Person[];
  value: string;
  onChange: (name: string) => void;
  placeholder?: string;
  loading?: boolean;
  emptyHint?: string;
}) {
  const [query, setQuery] = useState(value);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const boxRef = useRef<HTMLDivElement>(null);
  const listId = useId();

  // The value can change under us — switching sides clears it — and the box
  // has to follow rather than keep showing the old club's captain.
  useEffect(() => {
    setQuery(value);
  }, [value]);

  const matches = useMemo(() => {
    const term = query.trim().toLowerCase();
    if (!term) return people;
    // A name that starts with what you typed comes first: typing "ra" should
    // reach Rahul before Vikram Ramesh.
    const starts: Person[] = [];
    const contains: Person[] = [];
    for (const p of people) {
      const name = p.name.toLowerCase();
      if (name.startsWith(term)) starts.push(p);
      else if (name.includes(term)) contains.push(p);
    }
    return [...starts, ...contains];
  }, [people, query]);

  useEffect(() => {
    setActive(0);
  }, [query]);

  // Clicking anywhere else is a dismissal, not a selection.
  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => {
      if (!boxRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", away);
    return () => document.removeEventListener("mousedown", away);
  }, [open]);

  const choose = (person: Person) => {
    onChange(person.name);
    setQuery(person.name);
    setOpen(false);
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Escape") {
      setOpen(false);
      return;
    }
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!open) {
        setOpen(true);
        return;
      }
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
    <div className="person-picker" ref={boxRef}>
      <label htmlFor={`${listId}-input`}>{label}</label>
      <input
        id={`${listId}-input`}
        role="combobox"
        aria-expanded={open}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={open && matches[active] ? `${listId}-${active}` : undefined}
        autoComplete="off"
        value={query}
        placeholder={loading ? "Loading the squad…" : placeholder}
        onFocus={() => setOpen(true)}
        onKeyDown={onKeyDown}
        onChange={(e) => {
          setQuery(e.target.value);
          // Typing is itself an answer — a name nobody recognises is still a
          // name, so the value tracks the box rather than only a chosen row.
          onChange(e.target.value);
          setOpen(true);
        }}
      />

      {open && people.length > 0 && (
        <ul className="person-list" id={listId} role="listbox">
          {matches.map((p, i) => (
            <li key={p.id} id={`${listId}-${i}`} role="option" aria-selected={i === active}>
              <button
                type="button"
                className={`person-row${i === active ? " active" : ""}`}
                // mousedown, because blur would close the list before a click.
                onMouseDown={(e) => {
                  e.preventDefault();
                  choose(p);
                }}
                onMouseEnter={() => setActive(i)}
              >
                <span className="person-name">{p.name}</span>
                {p.note && <span className="person-note">{p.note}</span>}
              </button>
            </li>
          ))}
          {matches.length === 0 && (
            <li className="person-empty">
              Nobody in the squad matches. Leave it as typed to record them anyway.
            </li>
          )}
        </ul>
      )}

      {!loading && people.length === 0 && emptyHint && (
        <span className="subtle">{emptyHint}</span>
      )}
    </div>
  );
}

/// Club members as the picker wants them, with the role worth showing.
export function peopleFromMembers(members: ClubMemberRow[]): Person[] {
  return members.map((m) => ({
    id: m.user_id,
    name: m.name,
    note: m.role === "member" ? undefined : roleLabel(m.role),
  }));
}
