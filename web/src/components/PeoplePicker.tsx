"use client";

import { useMemo, useState } from "react";

export type Person = { id: string; name: string; note?: string };
export type PeopleTab = { label: string; people: Person[] };

/// Pick one person, from tabbed lists.
///
/// Two full teams plus the officials is thirty names. As one wrapping wall of
/// chips that is a mess to read and worse to search — so each side gets its
/// own tab and you only ever look at one team at a time, which is how anybody
/// at a ground thinks about it anyway.
export function PeoplePicker({
  tabs,
  chosen,
  onChoose,
  searchFrom = 8,
  empty = "Nobody to choose from yet.",
}: {
  tabs: PeopleTab[];
  chosen: string | null;
  onChoose: (id: string) => void;
  /// Below this many names in a tab, a search box is just another thing to
  /// read past.
  searchFrom?: number;
  empty?: string;
}) {
  const shown = tabs.filter((t) => t.people.length > 0);
  const [active, setActive] = useState(0);
  const [filter, setFilter] = useState("");

  // A tab can empty out under you — somebody appointed, a squad reloaded.
  const index = Math.min(active, Math.max(shown.length - 1, 0));
  const tab = shown[index];

  const people = useMemo(() => {
    const term = filter.trim().toLowerCase();
    if (!tab) return [];
    return term ? tab.people.filter((p) => p.name.toLowerCase().includes(term)) : tab.people;
  }, [tab, filter]);

  if (shown.length === 0) return <p className="muted">{empty}</p>;

  return (
    <div className="people-picker">
      {shown.length > 1 && (
        <div className="people-tabs" role="tablist" aria-label="Which team">
          {shown.map((t, i) => (
            <button
              key={t.label}
              type="button"
              role="tab"
              aria-selected={i === index}
              className={i === index ? "on" : undefined}
              onClick={() => {
                setActive(i);
                setFilter("");
              }}
            >
              {t.label}
              <span className="people-count num">{t.people.length}</span>
            </button>
          ))}
        </div>
      )}

      {tab && tab.people.length >= searchFrom && (
        <input
          className="people-search"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder={`Search ${tab.label}`}
          aria-label={`Search ${tab.label}`}
        />
      )}

      <ul className="people-list" role="listbox" aria-label={tab?.label}>
        {people.map((p) => (
          <li key={p.id}>
            <button
              type="button"
              role="option"
              aria-selected={chosen === p.id}
              className={chosen === p.id ? "on" : undefined}
              onClick={() => onChoose(p.id)}
            >
              <span className="people-name">{p.name}</span>
              {p.note && <span className="tag grey">{p.note}</span>}
              <span className="people-tick" aria-hidden>
                {chosen === p.id ? "✓" : ""}
              </span>
            </button>
          </li>
        ))}
      </ul>

      {people.length === 0 && <p className="muted">Nobody by that name in {tab?.label}.</p>}
    </div>
  );
}
