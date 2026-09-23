"use client";

import { useState } from "react";
import { api, readErr } from "@/lib/api";
import { Icon, type IconName } from "@/components/Icon";
import {
  AGE_GROUPS,
  AGE_LABEL,
  BALLS,
  BALL_LABEL,
  defaultConditions,
  GENDERS,
  GENDER_LABEL,
  GROUNDS,
  GROUND_LABEL,
  standardOversPerBowler,
  type MatchConditions,
} from "@/lib/tournament";

/// The rules a tournament runs on, as one editable thing.
///
/// Shared by the form that creates a tournament and the one that changes it
/// afterwards: two copies of eighteen fields drift, and the pair that drifts is
/// always the one nobody is looking at.

/* ---------- Formats ---------- */

/// A recognised format, and the numbers that go with it.
///
/// This is the form's answer to "I don't know what to put". Somebody who has
/// never set a tournament up picks *Twenty20* and gets twenty overs, four an
/// over each, and a six-over powerplay — the real ones, not our guesses. Every
/// number stays editable underneath.
export type Format = {
  key: string;
  name: string;
  detail: string;
  icon: IconName;
  overs: number;
  perBowler: number;
  powerplay: number;
  side: number;
};

export const FORMATS: Format[] = [
  { key: "t20", name: "Twenty20", detail: "20 overs · 4 an over each · 6-over powerplay",
    icon: "ball", overs: 20, perBowler: 4, powerplay: 6, side: 11 },
  { key: "t10", name: "Ten10", detail: "10 overs · 2 an over each · 3-over powerplay",
    icon: "ball", overs: 10, perBowler: 2, powerplay: 3, side: 11 },
  { key: "forty", name: "Forty over", detail: "40 overs · 8 an over each · club Sunday",
    icon: "bat", overs: 40, perBowler: 8, powerplay: 0, side: 11 },
  { key: "fifty", name: "Fifty over", detail: "50 overs · 10 an over each · 10-over powerplay",
    icon: "bat", overs: 50, perBowler: 10, powerplay: 10, side: 11 },
  { key: "sixes", name: "Sixes", detail: "6 overs · six a side · a whole day of them",
    icon: "trophy", overs: 6, perBowler: 2, powerplay: 0, side: 6 },
];

/* ---------- State ---------- */

export type Rules = {
  description: string;
  maxEntrants: string;
  entryDeadline: string;
  entryFee: string;
  venueId: string;
  playersPerSide: number;
  guests: number;
  ageGroup: string;
  gender: string;
  overs: number;
  perBowler: number;
  ball: string;
  ground: string;
  powerplay: number;
  rulesNotes: string;
};

export function emptyRules(): Rules {
  const t20 = FORMATS[0];
  return {
    description: "", maxEntrants: "", entryDeadline: "", entryFee: "", venueId: "",
    playersPerSide: t20.side, guests: 0, ageGroup: "open", gender: "open",
    overs: t20.overs, perBowler: t20.perBowler, ball: "white", ground: "open",
    powerplay: t20.powerplay, rulesNotes: "",
  };
}

/// Which format these numbers are, or `custom` when they are nobody's.
export function formatOf(r: Rules): string {
  return (
    FORMATS.find(
      (f) =>
        f.overs === r.overs &&
        f.perBowler === r.perBowler &&
        f.powerplay === r.powerplay &&
        f.side === r.playersPerSide
    )?.key ?? "custom"
  );
}

/// Pounds as typed, pence as stored. `NaN` when it is not an amount at all —
/// "abc" used to strip to "" and save the tournament as free to enter.
export function pence(typed: string): number | null {
  const t = typed.trim().replace(/^£/, "");
  if (t === "") return null;
  return /^\d+(\.\d{1,2})?$/.test(t) ? Math.round(Number(t) * 100) : NaN;
}

/// What the form sends. `clear` names the settings being removed, because a
/// missing field and a null field look identical over JSON.
export function rulesPayload(r: Rules, conditions: MatchConditions) {
  return {
    description: r.description.trim() || null,
    venue_id: r.venueId || null,
    max_entrants: r.maxEntrants.trim() === "" ? null : Number(r.maxEntrants),
    entry_deadline: r.entryDeadline ? new Date(r.entryDeadline).toISOString() : null,
    entry_fee_cents: pence(r.entryFee),
    players_per_side: r.playersPerSide,
    guest_players_allowed: r.guests,
    age_group: r.ageGroup,
    gender: r.gender,
    conditions: {
      ...conditions,
      overs_limit: r.overs,
      overs_per_bowler: r.perBowler,
      ball: r.ball,
      ground: r.ground,
      powerplay_overs: r.powerplay,
    },
    rules_notes: r.rulesNotes.trim() || null,
    clear: [
      r.maxEntrants.trim() === "" && "max_entrants",
      r.entryDeadline === "" && "entry_deadline",
      r.entryFee.trim() === "" && "entry_fee_cents",
      r.description.trim() === "" && "description",
      r.rulesNotes.trim() === "" && "rules_notes",
      r.venueId === "" && "venue_id",
    ].filter((v): v is string => typeof v === "string"),
  };
}

/// The tournament in one line, so it can be checked before it is created.
export function rulesSummary(r: Rules): string {
  const f = FORMATS.find((x) => x.key === formatOf(r));
  return [
    r.maxEntrants.trim() ? `${r.maxEntrants} sides` : "no entry limit",
    f ? f.name : `${r.overs} overs`,
    `${r.playersPerSide} a side`,
    BALL_LABEL[r.ball]?.toLowerCase(),
    r.ageGroup !== "open" ? AGE_LABEL[r.ageGroup] : null,
    r.gender !== "open" ? GENDER_LABEL[r.gender] : null,
    r.guests > 0 ? `${r.guests} guest${r.guests === 1 ? "" : "s"} a side` : "club members only",
  ]
    .filter(Boolean)
    .join(" · ");
}

/* ---------- The fields ---------- */

export type Venue = { id: string; name: string };

export function TournamentRuleFields({
  rules,
  set,
  venues,
  clubId,
  onVenueAdded,
  /// Where this component's steps start. The create form puts its own "what it
  /// is" step first, so these follow on from it rather than restarting at one.
  from = 1,
}: {
  rules: Rules;
  set: (patch: Partial<Rules>) => void;
  venues: Venue[];
  /// Whose grounds these are — needed to add one.
  clubId: string;
  onVenueAdded: (venue: Venue) => void;
  from?: number;
}) {
  const chosen = formatOf(rules);
  // Closed to begin with: somebody who picked "Twenty20" has already answered
  // all of this, and showing five more boxes only invites them to doubt it.
  const [open, setOpen] = useState(chosen === "custom");
  const fee = pence(rules.entryFee);

  const pickFormat = (f: Format) =>
    set({ overs: f.overs, perBowler: f.perBowler, powerplay: f.powerplay, playersPerSide: f.side });

  return (
    <>
      <Step n={from} title="The format" hint="Pick the one you are playing — the numbers fill in.">
        <div className="opt-cards opt-cards-wide">
          {FORMATS.map((f) => (
            <label key={f.key} className={`opt-card${chosen === f.key ? " on" : ""}`}>
              <input
                type="radio"
                name="format"
                checked={chosen === f.key}
                onChange={() => pickFormat(f)}
              />
              <span className="opt-card-icon"><Icon name={f.icon} size={18} /></span>
              <span className="opt-card-body">
                <span className="opt-card-title">{f.name}</span>
                <span className="opt-card-text">{f.detail}</span>
              </span>
              <span className="opt-card-tick"><Icon name="check" size={12} /></span>
            </label>
          ))}
          {chosen === "custom" && (
            <span className="opt-card on" aria-hidden>
              <span className="opt-card-icon"><Icon name="more" size={18} /></span>
              <span className="opt-card-body">
                <span className="opt-card-title">Your own</span>
                <span className="opt-card-text">
                  {rules.overs} overs · {rules.perBowler} an over each · {rules.playersPerSide} a side
                </span>
              </span>
            </span>
          )}
        </div>

        <button
          type="button"
          className="disclose"
          aria-expanded={open}
          onClick={() => setOpen(!open)}
        >
          <Icon name="arrowLeft" size={14} className="disclose-chev" />
          {open ? "Hide the details" : "Change the details"}
        </button>

        {open && (
          <div className="setup-fields" style={{ marginTop: "var(--s3)" }}>
            <label>
              Overs an innings
              <input
                type="number" min={1} max={100} value={rules.overs}
                onChange={(e) => {
                  const overs = clamp(Number(e.target.value), 1, 100, 20);
                  // A bowler's allocation is carried over, only never left
                  // above the innings — six overs with four each is a choice,
                  // six overs with ten each is a contradiction the server
                  // refuses. Picking a format sets both together.
                  set({
                    overs,
                    perBowler: Math.min(rules.perBowler, overs) || standardOversPerBowler(overs),
                  });
                }}
              />
            </label>
            <label>
              Most overs one bowler
              <input
                type="number" min={1} max={rules.overs} value={rules.perBowler}
                onChange={(e) => set({ perBowler: clamp(Number(e.target.value), 1, rules.overs, 1) })}
              />
              <span className="subtle">Usually a fifth of the innings.</span>
            </label>
            <label>
              Players a side
              <input
                type="number" min={2} max={15} value={rules.playersPerSide}
                onChange={(e) => set({ playersPerSide: clamp(Number(e.target.value), 2, 15, 11) })}
              />
            </label>
            <label>
              Powerplay overs
              <input
                type="number" min={0} max={rules.overs} value={rules.powerplay}
                onChange={(e) => set({ powerplay: clamp(Number(e.target.value), 0, rules.overs, 0) })}
              />
              <span className="subtle">Zero for none.</span>
            </label>
            <label>
              Ball
              <select value={rules.ball} onChange={(e) => set({ ball: e.target.value })}>
                {BALLS.map((b) => <option key={b} value={b}>{BALL_LABEL[b]}</option>)}
              </select>
              <span className="subtle">White for limited overs, red for the longer game.</span>
            </label>
            <label>
              Ground
              <select value={rules.ground} onChange={(e) => set({ ground: e.target.value })}>
                {GROUNDS.map((g) => <option key={g} value={g}>{GROUND_LABEL[g]}</option>)}
              </select>
            </label>
          </div>
        )}
      </Step>

      <Step n={from + 1} title="Entry" hint="Who can enter, by when, and what it costs them.">
        <div className="setup-fields">
          <label>
            How many sides
            <input
              type="number" min={2} value={rules.maxEntrants} placeholder="8"
              onChange={(e) => set({ maxEntrants: e.target.value })}
            />
            <span className="subtle">Leave empty for no limit.</span>
          </label>
          <label>
            Entries close
            <input
              type="datetime-local" value={rules.entryDeadline}
              onChange={(e) => set({ entryDeadline: e.target.value })}
            />
            <span className="subtle">After this nobody else can be asked in.</span>
          </label>
          <label>
            Entry fee per side
            <input
              inputMode="decimal" value={rules.entryFee} placeholder="50.00"
              onChange={(e) => set({ entryFee: e.target.value })}
            />
            <span className="subtle">What a club pays to enter. Empty is free.</span>
          </label>
          <GroundField
            venues={venues}
            venueId={rules.venueId}
            clubId={clubId}
            onPick={(venueId) => set({ venueId })}
            onAdded={(v) => {
              onVenueAdded(v);
              set({ venueId: v.id });
            }}
          />
        </div>
        {fee !== null && Number.isNaN(fee) && (
          <p className="error">Give the entry fee as an amount, like 50.00.</p>
        )}
      </Step>

      <Step n={from + 2} title="Who may play" hint="The rule clubs argue about on the day.">
        <div className="setup-fields">
          <label>
            Guest players allowed
            <input
              type="number" min={0} max={rules.playersPerSide} value={rules.guests}
              onChange={(e) => set({ guests: clamp(Number(e.target.value), 0, rules.playersPerSide, 0) })}
            />
            <span className="subtle">
              {rules.guests === 0
                ? "Every player must be a member of the entering club."
                : `A side may borrow up to ${rules.guests} from outside.`}
            </span>
          </label>
          <label>
            Age group
            <select value={rules.ageGroup} onChange={(e) => set({ ageGroup: e.target.value })}>
              {AGE_GROUPS.map((a) => <option key={a} value={a}>{AGE_LABEL[a]}</option>)}
            </select>
          </label>
          <label>
            Who it is for
            <select value={rules.gender} onChange={(e) => set({ gender: e.target.value })}>
              {GENDERS.map((g) => <option key={g} value={g}>{GENDER_LABEL[g]}</option>)}
            </select>
          </label>
        </div>
        <label style={{ marginTop: "var(--s4)" }}>
          Anything else in the rules
          <textarea
            rows={2} value={rules.rulesNotes}
            onChange={(e) => set({ rulesNotes: e.target.value })}
            placeholder="Ties settled on wickets lost, then boundaries. Last man bats with a runner."
          />
        </label>
      </Step>
    </>
  );
}

/// Pick a ground, or add one without leaving the form.
///
/// "Add grounds on the club page" meant abandoning a half-filled tournament to
/// go and do it, so most people picked *not decided* and never came back.
function GroundField({
  venues,
  venueId,
  clubId,
  onPick,
  onAdded,
}: {
  venues: Venue[];
  venueId: string;
  clubId: string;
  onPick: (id: string) => void;
  onAdded: (venue: Venue) => void;
}) {
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const add = async () => {
    setBusy(true);
    setError(null);
    try {
      const venue = await api<Venue>("POST", `/clubs/${clubId}/venues`, {
        name: name.trim(),
        address: address.trim() || null,
      });
      onAdded(venue);
      setAdding(false);
      setName("");
      setAddress("");
    } catch (err) {
      // Adding a ground is `ManageClubOps`, which a team captain does not hold
      // even though they may be running the tournament. Say so rather than
      // leaving a button that quietly does nothing.
      setError(readErr(err, "Could not add that ground"));
    } finally {
      setBusy(false);
    }
  };

  if (adding) {
    return (
      <div className="ground-add">
        <label>
          New ground
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Wray Crescent"
            maxLength={160}
            autoFocus
          />
        </label>
        <label>
          Where it is
          <input
            value={address}
            onChange={(e) => setAddress(e.target.value)}
            placeholder="Optional — the address or the postcode"
          />
        </label>
        {error && <p className="error">{error}</p>}
        <div className="field-row">
          <button
            className="btn primary sm"
            type="button"
            disabled={busy || !name.trim() || !clubId}
            onClick={add}
          >
            {busy ? "Adding…" : "Add it"}
          </button>
          <button
            className="btn sm"
            type="button"
            disabled={busy}
            onClick={() => {
              setAdding(false);
              setError(null);
            }}
          >
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <label>
      Main ground
      <select
        value={venueId}
        onChange={(e) => {
          if (e.target.value === "__new") {
            setAdding(true);
            return;
          }
          onPick(e.target.value);
        }}
      >
        <option value="">Not decided</option>
        {venues.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
        <option value="__new">+ Add a new ground…</option>
      </select>
      <span className="subtle">
        {venues.length === 0
          ? "None saved yet — add one here."
          : "Pitches are laid out later."}
      </span>
    </label>
  );
}

/// Defaults for a tournament whose rules have never been set.
export function conditionsBase(existing: MatchConditions | null): MatchConditions {
  return existing ?? defaultConditions();
}

/* ---------- Bits ---------- */

/// A numbered section. The number is what turns a wall of boxes into steps
/// somebody can work through without knowing the whole form first.
export function Step({
  n,
  title,
  hint,
  children,
}: {
  n: number;
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="form-step">
      <h3 className="form-step-head">
        <span className="step-num" aria-hidden>{n}</span>
        {title}
      </h3>
      {hint && <p className="form-step-hint">{hint}</p>}
      {children}
    </section>
  );
}

function clamp(v: number, lo: number, hi: number, fallback: number): number {
  if (!Number.isFinite(v)) return fallback;
  return Math.max(lo, Math.min(hi, v));
}
