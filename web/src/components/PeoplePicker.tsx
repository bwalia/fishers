"use client";

import { useMemo, useState } from "react";

export type Person = { id: string; name: string; note?: string };
export type PeopleTab = {
  label: string;
  people: Person[];
  /// Said in the tab when it has nobody — why, not just that.
  emptyText?: string;
};

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
  keepTabs = false,
  openOn,
}: {
  tabs: PeopleTab[];
  chosen: string | null;
  onChoose: (id: string) => void;
  /// Below this many names in a tab, a search box is just another thing to
  /// read past.
  searchFrom?: number;
  empty?: string;
  /// Show every tab even when it is empty. Two teams are the frame people
  /// think in: with one team's tab hidden, a single list reads as everybody
  /// mixed together, and nothing says where the other side went.
  keepTabs?: boolean;
  /// The label of the tab the answer is almost certainly on — the side about
  /// to bat, when the book is crossing at an innings break. Ignored when that
  /// tab has nobody in it, so an opposition who aren't on Fishers still land
  /// on a list with names in it rather than an explanation.
  openOn?: string;
}) {
  const shown = keepTabs ? tabs : tabs.filter((t) => t.people.length > 0);
  // Open on the tab the caller expects, else the first one with somebody in it.
  const [active, setActive] = useState(() => {
    const wanted = shown.findIndex((t) => t.label === openOn && t.people.length > 0);
    return wanted >= 0 ? wanted : Math.max(0, shown.findIndex((t) => t.people.length > 0));
  });
  const [filter, setFilter] = useState("");

  // A tab can empty out under you — somebody appointed, a squad reloaded.
  const index = Math.min(active, Math.max(shown.length - 1, 0));
  const tab = shown[index];

  const people = useMemo(() => {
    const term = filter.trim().toLowerCase();
    if (!tab) return [];
    return term ? tab.people.filter((p) => p.name.toLowerCase().includes(term)) : tab.people;
  }, [tab, filter]);

  if (shown.every((t) => t.people.length === 0) && !keepTabs) return <p className="muted">{empty}</p>;

  return (
    <div className="people-picker">
      {(shown.length > 1 || keepTabs) && (
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

      {tab && tab.people.length === 0 && (
        <p className="muted people-empty">{tab.emptyText ?? `Nobody in ${tab.label}.`}</p>
      )}
      {tab && tab.people.length > 0 && people.length === 0 && (
        <p className="muted">Nobody by that name in {tab.label}.</p>
      )}
    </div>
  );
}
