"use client";

import { useCallback, useEffect, useState } from "react";
import { Icon } from "@/components/Icon";
import {
  myUmpiring,
  ratingLabel,
  setUmpiring,
  umpiringOf,
  type UmpireProfile,
} from "@/lib/umpire";
import { readErr } from "@/lib/api";

/// Somebody's umpiring record.
///
/// Club cricket umpires itself — the batting side gives two, or it is whoever
/// is next in — and the person who does it every week has had nothing to show
/// for it. This is that: how often they have stood, what the players thought,
/// and a switch saying whether they will do it again.
///
/// One component for your own page and for somebody else's, because they are
/// the same record; the difference is whether the switch is a switch or a
/// sentence.
export function Umpiring({ userId, name }: { userId?: string; name?: string }) {
  const mine = !userId;
  const [profile, setProfile] = useState<UmpireProfile | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setProfile(mine ? await myUmpiring() : await umpiringOf(userId!));
    } catch (err) {
      setError(readErr(err, "Could not load the umpiring record"));
    } finally {
      setLoading(false);
    }
  }, [mine, userId]);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) return <div className="skeleton" style={{ height: 180, borderRadius: "var(--radius)" }} />;
  if (error) return <p className="error">{error}</p>;
  if (!profile) return null;

  return (
    <section className="ump" aria-labelledby="ump-h">
      <div className="ump-head">
        <h2 id="ump-h">
          <Icon name="shield" size={20} /> Umpiring
        </h2>
        {mine ? (
          <WillingSwitch profile={profile} onSaved={setProfile} />
        ) : (
          profile.umpires && <span className="tag">Will stand</span>
        )}
      </div>

      <div className="ump-figures">
        <Figure value={String(profile.matches)} label={profile.matches === 1 ? "match umpired" : "matches umpired"} />
        <Figure
          value={profile.rating_average === null ? "—" : profile.rating_average.toFixed(1)}
          label={ratingLabel(profile)}
        />
      </div>

      {profile.note && <p className="ump-note">{profile.note}</p>}

      {profile.rating_count > 0 && <Breakdown counts={profile.rating_breakdown} total={profile.rating_count} />}

      {profile.reviews.length > 0 ? (
        <ul className="ump-reviews">
          {profile.reviews.map((r) => (
            <li key={r.id} className="ump-review">
              <div className="ump-review-head">
                <Stars value={r.rating} />
                <span className="muted">
                  {r.reviewer_name} · {r.match_title}
                </span>
              </div>
              {r.comment && <p>{r.comment}</p>}
            </li>
          ))}
        </ul>
      ) : (
        <p className="muted ump-blank">
          {profile.matches === 0
            ? mine
              ? "You have not umpired a match here yet. Ask your captain to name you as umpire and it starts counting."
              : `${name ?? "They"} have not umpired a match here yet.`
            : "No reviews yet — the players in the next match can leave one afterwards."}
        </p>
      )}
    </section>
  );
}

function Figure({ value, label }: { value: string; label: string }) {
  return (
    <div className="ump-figure">
      <strong>{value}</strong>
      <span className="muted">{label}</span>
    </div>
  );
}

/// One to five, drawn. Never the only signal: the number is beside it, because
/// five shapes in a row is a hard thing to count at a glance and an impossible
/// one to hear.
export function Stars({ value, size = 16 }: { value: number; size?: number }) {
  return (
    <span className="stars" role="img" aria-label={`${value} out of 5`}>
      {[1, 2, 3, 4, 5].map((n) => (
        <svg key={n} width={size} height={size} viewBox="0 0 20 20" aria-hidden="true" className={n <= value ? "on" : ""}>
          <path d="M10 1.6l2.5 5.3 5.6.8-4.1 4 1 5.7L10 14.7 4.9 17.4l1-5.7-4.1-4 5.6-.8z" />
        </svg>
      ))}
    </span>
  );
}

/// How the ratings fall. A 4.0 from ten fours is a different umpire from a 4.0
/// from five fives and five threes, and the average alone hides that.
function Breakdown({ counts, total }: { counts: readonly number[]; total: number }) {
  return (
    <ul className="ump-breakdown">
      {[5, 4, 3, 2, 1].map((n) => {
        const count = counts[n - 1] ?? 0;
        return (
          <li key={n}>
            <span className="ump-bd-n">{n}</span>
            <span className="ump-bd-bar">
              <i style={{ width: `${total ? (count / total) * 100 : 0}%` }} />
            </span>
            <span className="ump-bd-c muted">{count}</span>
          </li>
        );
      })}
    </ul>
  );
}

function WillingSwitch({
  profile,
  onSaved,
}: {
  profile: UmpireProfile;
  onSaved: (p: UmpireProfile) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [editing, setEditing] = useState(false);
  const [note, setNote] = useState(profile.note ?? "");
  const [error, setError] = useState<string | null>(null);

  const save = async (body: { umpires?: boolean; note?: string | null }) => {
    setBusy(true);
    setError(null);
    try {
      onSaved(await setUmpiring(body));
      setEditing(false);
    } catch (err) {
      setError(readErr(err, "Could not save that"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="ump-willing">
      <label className="switch">
        <input
          type="checkbox"
          checked={profile.umpires}
          disabled={busy}
          onChange={(e) => save({ umpires: e.target.checked })}
        />
        <span>I umpire</span>
      </label>
      {profile.umpires &&
        (editing ? (
          <form
            className="ump-note-edit"
            onSubmit={(e) => {
              e.preventDefault();
              save({ note: note.trim() || null });
            }}
          >
            <label htmlFor="ump-note">Anything a captain should know</label>
            <input
              id="ump-note"
              value={note}
              maxLength={200}
              placeholder="Level 1 ECB · club matches only"
              onChange={(e) => setNote(e.target.value)}
            />
            <button className="btn primary" disabled={busy}>
              {busy ? "Saving…" : "Save"}
            </button>
            <button type="button" className="btn" onClick={() => setEditing(false)}>
              Cancel
            </button>
          </form>
        ) : (
          <button type="button" className="btn" onClick={() => setEditing(true)}>
            {profile.note ? "Edit note" : "Add a note"}
          </button>
        ))}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
