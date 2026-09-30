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
import { useT } from "@/lib/i18n/provider";
import type { T } from "@/lib/i18n";
import type { Key } from "@/lib/i18n/en";

/// The rules a tournament runs on, as one editable thing.
///
/// Shared by the form that creates a tournament and the one that changes it
/// afterwards: two copies of eighteen fields drift, and the pair that drifts is
/// always the one nobody is looking at.

/* ---------- Formats ---------- */

/// A recognised format, and the numbers that go with it.
///
/// This is the form's answer to "la.i_don_t_know_what_to_put". Somebody who has
/// never set a tournament up picks *Twenty20* and gets twenty overs, four an
/// over each, and a six-over powerplay — the real ones, not our guesses. Every
/// number stays editable underneath.
export type Format = {
  key: string;
  /// Dictionary keys: `FORMATS` is built once at module scope and read in
  /// whichever language the viewer chose.
  name: Key;
  detail: Key;
  icon: IconName;
  overs: number;
  perBowler: number;
  powerplay: number;
  side: number;
};

export const FORMATS: Format[] = [
  { key: "t20", name: "la.twenty20", detail: "tn.fmt_t20_detail",
    icon: "ball", overs: 20, perBowler: 4, powerplay: 6, side: 11 },
  { key: "t10", name: "la.ten10", detail: "tn.fmt_t10_detail",
    icon: "ball", overs: 10, perBowler: 2, powerplay: 3, side: 11 },
  { key: "forty", name: "la.forty_over", detail: "tn.fmt_forty_detail",
    icon: "bat", overs: 40, perBowler: 8, powerplay: 0, side: 11 },
  { key: "fifty", name: "la.fifty_over", detail: "tn.fmt_fifty_detail",
    icon: "bat", overs: 50, perBowler: 10, powerplay: 10, side: 11 },
  { key: "sixes", name: "tn.fmt_sixes", detail: "tn.fmt_sixes_detail",
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
export function rulesSummary(r: Rules, t: T): string {
  const f = FORMATS.find((x) => x.key === formatOf(r));
  return [
    r.maxEntrants.trim()
      ? t("tn.n_sides", { n: r.maxEntrants })
      : t("tn.no_entry_limit"),
    f ? t(f.name) : t("tn.n_overs", { n: r.overs }),
    t("tn.n_a_side", { n: r.playersPerSide }),
    t(BALL_LABEL[r.ball]).toLowerCase(),
    r.ageGroup !== "open" ? t(AGE_LABEL[r.ageGroup]) : null,
    r.gender !== "open" ? t(GENDER_LABEL[r.gender]) : null,
    r.guests > 0
      ? t("tn.n_guests_a_side", { n: r.guests, count: r.guests })
      : t("tn.club_members_only"),
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
  const t = useT();
  const chosen = formatOf(rules);
  // Closed to begin with: somebody who picked "la.twenty20" has already answered
  // all of this, and showing five more boxes only invites them to doubt it.
  const [open, setOpen] = useState(chosen === "custom");
  const fee = pence(rules.entryFee);

  const pickFormat = (f: Format) =>
    set({ overs: f.overs, perBowler: f.perBowler, powerplay: f.powerplay, playersPerSide: f.side });

  return (
    <>
      <Step n={from} title={"tn.the_format"} hint={"la.pick_the_one_you_are_playing_the_numbe"}>
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
                <span className="opt-card-title">{t(f.name)}</span>
                <span className="opt-card-text">{t(f.detail)}</span>
              </span>
              <span className="opt-card-tick"><Icon name="check" size={12} /></span>
            </label>
          ))}
          {chosen === "custom" && (
            <span className="opt-card on" aria-hidden>
              <span className="opt-card-icon"><Icon name="more" size={18} /></span>
              <span className="opt-card-body">
                <span className="opt-card-title">{"tn.your_own"}</span>
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
          {open ? "la.hide_the_details" : "la.change_the_details"}
        </button>

        {open && (
          <div className="setup-fields" style={{ marginTop: "var(--s3)" }}>
            <label>
              {"tn.overs_an_innings"}
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
              {"tn.most_overs_one_bowler"}
              <input
                type="number" min={1} max={rules.overs} value={rules.perBowler}
                onChange={(e) => set({ perBowler: clamp(Number(e.target.value), 1, rules.overs, 1) })}
              />
              <span className="subtle">{"tn.usually_a_fifth_of_the_innings"}</span>
            </label>
            <label>
              {"tn.players_a_side"}
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
              <span className="subtle">{"tn.zero_for_none"}</span>
            </label>
            <label>
              Ball
              <select value={rules.ball} onChange={(e) => set({ ball: e.target.value })}>
                {BALLS.map((b) => <option key={b} value={b}>{t(BALL_LABEL[b])}</option>)}
              </select>
              <span className="subtle">{"tn.white_for_limited_overs_red_for_the_lo"}</span>
            </label>
            <label>
              Ground
              <select value={rules.ground} onChange={(e) => set({ ground: e.target.value })}>
                {GROUNDS.map((g) => <option key={g} value={g}>{t(GROUND_LABEL[g])}</option>)}
              </select>
            </label>
          </div>
        )}
      </Step>

      <Step n={from + 1} title={"tn.entry"} hint={"la.who_can_enter_by_when_and_what_it_cost"}>
        <div className="setup-fields">
          <label>
            {"tn.how_many_sides"}
            <input
              type="number" min={2} value={rules.maxEntrants} placeholder="8"
              onChange={(e) => set({ maxEntrants: e.target.value })}
            />
            <span className="subtle">Leave empty for no limit.</span>
          </label>
          <label>
            {"tn.entries_close"}
            <input
              type="datetime-local" value={rules.entryDeadline}
              onChange={(e) => set({ entryDeadline: e.target.value })}
            />
            <span className="subtle">{"tn.after_this_nobody_else_can_be_asked_in"}</span>
          </label>
          <label>
            {"tn.entry_fee_per_side"}
            <input
              inputMode="decimal" value={rules.entryFee} placeholder={"tn.50_00"}
              onChange={(e) => set({ entryFee: e.target.value })}
            />
            <span className="subtle">{"tn.what_a_club_pays_to_enter_empty_is_fre"}</span>
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
          <p className="error">{"tn.give_the_entry_fee_as_an_amount_like_5"}</p>
        )}
      </Step>

      <Step n={from + 2} title={"tn.who_may_play"} hint={"la.the_rule_clubs_argue_about_on_the_day"}>
        <div className="setup-fields">
          <label>
            {"tn.guest_players_allowed"}
            <input
              type="number" min={0} max={rules.playersPerSide} value={rules.guests}
              onChange={(e) => set({ guests: clamp(Number(e.target.value), 0, rules.playersPerSide, 0) })}
            />
            <span className="subtle">
              {rules.guests === 0
                ? "la.every_player_must_be_a_member_of_the_e"
                : `A side may borrow up to ${rules.guests} from outside.`}
            </span>
          </label>
          <label>
            {"tn.age_group"}
            <select value={rules.ageGroup} onChange={(e) => set({ ageGroup: e.target.value })}>
              {AGE_GROUPS.map((a) => <option key={a} value={a}>{t(AGE_LABEL[a])}</option>)}
            </select>
          </label>
          <label>
            {"tn.who_it_is_for"}
            <select value={rules.gender} onChange={(e) => set({ gender: e.target.value })}>
              {GENDERS.map((g) => <option key={g} value={g}>{t(GENDER_LABEL[g])}</option>)}
            </select>
          </label>
        </div>
        <label style={{ marginTop: "var(--s4)" }}>
          {"tn.anything_else_in_the_rules"}
          <textarea
            rows={2} value={rules.rulesNotes}
            onChange={(e) => set({ rulesNotes: e.target.value })}
            placeholder={"tn.ties_settled_on_wickets_lost_then_boun"}
          />
        </label>
      </Step>
    </>
  );
}

/// Pick a ground, or add one without leaving the form.
///
/// "la.add_grounds_on_the_club_page" meant abandoning a half-filled tournament to
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
      setError(readErr(err, "la.could_not_add_that_ground"));
    } finally {
      setBusy(false);
    }
  };

  if (adding) {
    return (
      <div className="ground-add">
        <label>
          {"tn.new_ground"}
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={"tn.wray_crescent"}
            maxLength={160}
            autoFocus
          />
        </label>
        <label>
          {"tn.where_it_is"}
          <input
            value={address}
            onChange={(e) => setAddress(e.target.value)}
            placeholder={"tn.optional_the_address_or_the_postcode"}
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
            {busy ? "la.adding" : "la.add_it"}
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
      {"tn.main_ground"}
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
        <option value="">{"tn.not_decided"}</option>
        {venues.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
        <option value="__new">+ Add a new ground…</option>
      </select>
      <span className="subtle">
        {venues.length === 0
          ? "la.none_saved_yet_add_one_here"
          : "la.pitches_are_laid_out_later"}
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
