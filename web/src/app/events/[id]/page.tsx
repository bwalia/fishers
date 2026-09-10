"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  getAccessToken,
  money,
  readErr,
  type ClubMemberRow,
  type EventRow,
} from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";
import { PeoplePicker, type PeopleTab } from "@/components/PeoplePicker";

/// Everyone the fixture knows about, and what they said.
type Attendee = {
  user_id: string;
  name: string;
  /// `going` | `not_going` | `maybe` | `invited`
  status: string;
  availability: string | null;
  paid: boolean;
};

const RSVP_LABEL: Record<string, string> = {
  going: "Playing",
  not_going: "Can't",
  maybe: "Maybe",
  invited: "Not answered",
};

/// One fixture: who is coming, who owes, and — if you run it — calling it off.
export default function EventPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [event, setEvent] = useState<EventRow | null>(null);
  const [attendees, setAttendees] = useState<Attendee[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const [e, a] = await Promise.all([
        api<EventRow>("GET", `/events/${id}`),
        api<Attendee[]>("GET", `/events/${id}/attendees`).catch(() => [] as Attendee[]),
      ]);
      setEvent(e);
      setAttendees(a);
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load this fixture"));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to see this fixture.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

  const act = async (what: string, run: () => Promise<unknown>, said: string) => {
    setBusy(what);
    setError(null);
    setNote(null);
    try {
      await run();
      setNote(said);
      await load();
    } catch (err) {
      setError(readErr(err, "That did not work"));
    } finally {
      setBusy(null);
    }
  };

  if (error && !event) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !event)
    return <main id="main"><div className="skeleton" style={{ height: 260 }} /></main>;

  const count = (s: string) => attendees.filter((a) => a.status === s).length;
  const owing = attendees.filter((a) => !a.paid && a.status === "going");

  return (
    <main id="main">
      <section className="hero">
        <p className="club-eyebrow">
          {new Date(event.start_at).toLocaleString("en-GB", {
            weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit",
          })}
        </p>
        <h1>{event.title}</h1>
        <div className="hero-tags">
          <span className="tag">{count("going")} playing</span>
          {count("maybe") > 0 && <span className="tag gold">{count("maybe")} maybe</span>}
          {count("invited") > 0 && (
            <span className="tag grey">{count("invited")} not answered</span>
          )}
          {event.status !== "scheduled" && (
            <span className="tag danger">{event.status}</span>
          )}
        </div>
      </section>

      {error && <p className="error">{error}</p>}
      {note && <p className="notice">{note}</p>}

      <div className="pro-cols">
        <div className="pro-main">
          <div className="panel">
            <div className="panel-head">
              <h2>Are you playing?</h2>
              {event.fee_amount_cents != null && (
                <span className="tag gold">{money(event.fee_amount_cents)} match fee</span>
              )}
            </div>
            <div className="field-row">
              {(["going", "maybe", "not_going"] as const).map((answer) => (
                <button
                  key={answer}
                  className={answer === "going" ? "btn primary" : "btn"}
                  type="button"
                  disabled={busy !== null}
                  onClick={() =>
                    act(answer, () => api("POST", `/events/${id}/rsvp`, { status: answer }),
                        `Told them: ${RSVP_LABEL[answer].toLowerCase()}.`)
                  }
                >
                  {RSVP_LABEL[answer]}
                </button>
              ))}
            </div>
          </div>

          <div className="panel">
            <div className="panel-head">
              <h2>Who is coming</h2>
              <Link className="btn ghost sm" href={`/events/${id}/selection`}>
                Pick the squad
              </Link>
            </div>
            {attendees.length === 0 ? (
              <p className="muted">Nobody asked yet. Invite people below.</p>
            ) : (
              <ul className="pick-list">
                {attendees.map((a) => (
                  <li key={a.user_id}>
                    <Avatar name={a.name} size={32} />
                    <div className="pick-who">
                      <strong>{a.name}</strong>
                      <span className="pick-signals">
                        <span className={`tag ${a.status === "going" ? "" : a.status === "not_going" ? "danger" : "grey"}`}>
                          {RSVP_LABEL[a.status] ?? a.status}
                        </span>
                        {a.availability && (
                          <span className="subtle">calendar says {a.availability}</span>
                        )}
                      </span>
                    </div>
                    <div className="pick-actions">
                      {event.fee_amount_cents != null && (
                        <span className={a.paid ? "tag" : "tag grey"}>
                          {a.paid ? "paid" : "owes"}
                        </span>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <Invite eventId={id} clubId={event.club_id} asked={attendees} onInvited={load} />
        </div>

        <aside className="pro-rail">
          {event.fee_amount_cents != null && owing.length > 0 && (
            <div className="panel">
              <h2>Still to pay</h2>
              <p className="muted">
                {owing.length} of the {count("going")} playing owe{" "}
                {money(event.fee_amount_cents * owing.length)} between them.
              </p>
            </div>
          )}

          <CallOff
            status={event.status}
            busy={busy !== null}
            onDo={(status, note) =>
              act(
                "status",
                () => api("POST", `/events/${id}/status`, { status, note: note || null }),
                status === "cancelled" ? "Called off — everybody has been told."
                  : status === "postponed" ? "Postponed — everybody has been told."
                  : "Back on."
              )
            }
          />

          <p className="muted">
            <Link href="/events">← All fixtures</Link>
          </p>
        </aside>
      </div>
    </main>
  );
}

/// Ask more people. Only offers club members who have not been asked yet —
/// inviting somebody twice is noise for them and a duplicate row here.
function Invite({
  eventId,
  clubId,
  asked,
  onInvited,
}: {
  eventId: string;
  clubId: string;
  asked: Attendee[];
  onInvited: () => void;
}) {
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [open, setOpen] = useState(false);
  const [chosen, setChosen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || members.length > 0) return;
    api<ClubMemberRow[]>("GET", `/clubs/${clubId}/members`)
      .then(setMembers)
      .catch(() => setError("Only a captain or secretary can invite people."));
  }, [open, members.length, clubId]);

  const already = new Set(asked.map((a) => a.user_id));
  const tabs: PeopleTab[] = [
    {
      label: "Not asked yet",
      people: members
        .filter((m) => !already.has(m.user_id))
        .map((m) => ({ id: m.user_id, name: m.name, note: m.position_role ?? undefined })),
    },
  ];

  const invite = async () => {
    if (!chosen) return;
    setBusy(true);
    setError(null);
    try {
      await api("POST", `/events/${eventId}/invite`, { user_id: chosen });
      setChosen(null);
      onInvited();
    } catch (err) {
      setError(readErr(err, "Could not invite them"));
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <button className="btn" type="button" onClick={() => setOpen(true)}>
        <Icon name="plus" size={16} /> Ask somebody else
      </button>
    );
  }

  return (
    <div className="panel">
      <h2>Ask somebody else</h2>
      <PeoplePicker
        tabs={tabs}
        chosen={chosen}
        onChoose={setChosen}
        empty="Everybody in the club has already been asked."
      />
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !chosen} onClick={invite}>
          {busy ? "Asking…" : "Ask them"}
        </button>
        <button className="btn" type="button" onClick={() => { setOpen(false); setChosen(null); }}>
          Done
        </button>
      </div>
    </div>
  );
}

/// Postponing or calling a fixture off.
///
/// Both tell everybody who was asked, so the reason is worth typing — "ground
/// unplayable after Friday's rain" saves a captain fifteen replies.
function CallOff({
  status,
  busy,
  onDo,
}: {
  status: string;
  busy: boolean;
  onDo: (status: string, note: string) => void;
}) {
  const [note, setNote] = useState("");
  const off = status === "cancelled" || status === "postponed";

  return (
    <div className="panel">
      <h2>{off ? "This fixture is off" : "Call it off"}</h2>
      {off ? (
        <>
          <p className="muted">It is marked {status}. Everybody asked has been told.</p>
          <button className="btn" type="button" disabled={busy}
                  onClick={() => onDo("scheduled", "")}>
            Put it back on
          </button>
        </>
      ) : (
        <>
          <p className="muted">
            Everybody who was asked gets told, so the reason is worth typing.
          </p>
          <label>
            Why
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Ground unplayable after Friday's rain"
            />
          </label>
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button className="btn" type="button" disabled={busy}
                    onClick={() => onDo("postponed", note)}>
              Postpone
            </button>
            <button className="btn danger" type="button" disabled={busy}
                    onClick={() => onDo("cancelled", note)}>
              Cancel it
            </button>
          </div>
        </>
      )}
    </div>
  );
}
