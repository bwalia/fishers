"use client";

import Link from "next/link";
import { use, useEffect, useState } from "react";
import {
  api,
  getAccessToken,
  getStoredUser,
  readErr,
  type Club,
  type MyRole,
  type SharedPlayerCard,
} from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";

/// Where a player's shared profile link lands.
///
/// The reader is a club secretary deciding whether to invite them, so the page
/// is the player's card and one button. The invite goes to their account and
/// waits there for them to accept — sharing a link never puts anyone in a club
/// they did not agree to join.
export default function SharedProfilePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [card, setCard] = useState<SharedPlayerCard | null>(null);
  const [clubs, setClubs] = useState<Club[] | null>(null);
  const [clubId, setClubId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const me = typeof window !== "undefined" ? getStoredUser() : null;

  useEffect(() => {
    // Not signed in: api() sends them to sign in and back here.
    if (!getAccessToken()) {
      window.location.href = `/login?next=${encodeURIComponent(`/p/${token}`)}`;
      return;
    }
    (async () => {
      try {
        const [c, mine] = await Promise.all([
          api<SharedPlayerCard>("GET", `/players/card/${encodeURIComponent(token)}`),
          api<Club[]>("GET", "/clubs"),
        ]);
        // Only the clubs they can actually invite into.
        const roles = await Promise.all(
          mine.map((club) =>
            api<MyRole>("GET", `/clubs/${club.id}/my-role`).catch(() => null)
          )
        );
        const invitable = mine.filter((_, i) => {
          const r = roles[i];
          return r && (r.is_secretary || r.permissions.includes("invite_to_club"));
        });
        setCard(c);
        setClubs(invitable);
        if (invitable[0]) setClubId(invitable[0].id);
      } catch (err) {
        setError(readErr(err, "That profile link did not open"));
      }
    })();
  }, [token]);

  const invite = async () => {
    if (!card || !clubId) return;
    setBusy(true);
    setError(null);
    try {
      await api("POST", "/invites", {
        target_type: "club",
        target_id: clubId,
        invited_user_id: card.id,
      });
      const club = clubs?.find((c) => c.id === clubId);
      setSent(club?.name ?? "your club");
    } catch (err) {
      setError(readErr(err, "Could not send the invite"));
    } finally {
      setBusy(false);
    }
  };

  if (error && !card) {
    return (
      <main id="main" className="shared-profile">
        <div className="panel empty">
          <Icon name="link" size={28} />
          <h1>This link didn&apos;t work</h1>
          <p className="muted">{error}. Ask the player to send you their link again.</p>
        </div>
      </main>
    );
  }
  if (!card || clubs === null) {
    return (
      <main id="main" className="shared-profile">
        <div className="panel">
          <div className="skeleton" style={{ height: 160 }} />
        </div>
      </main>
    );
  }

  const first = card.name.split(" ")[0];
  const sport = card.sport_profiles?.find((p) => p.sport === card.primary_sport) ?? card.sport_profiles?.[0];
  const isMe = me?.id === card.id;

  return (
    <main id="main" className="shared-profile">
      <p className="subtle shared-kicker">
        <Icon name="users" size={14} /> A player would like to join your club
      </p>

      <div className="panel player-card">
        <Avatar name={card.name} url={card.avatar_url} size={96} />
        <div>
          <h1>{card.name}</h1>
          <p className="player-card-meta">
            {[card.primary_sport, sport?.position, sport?.skill_level, card.area]
              .filter(Boolean)
              .map((x) => String(x).replaceAll("_", " "))
              .join(" · ") || "Profile not filled in yet"}
          </p>
        </div>
      </div>

      {isMe ? (
        <div className="panel">
          <h2>This is your own link</h2>
          <p className="muted">
            Send it to your club&apos;s secretary. They open it, invite you, and the invite appears on your
            dashboard to accept.
          </p>
          <Link className="btn" href="/">
            Back to your dashboard
          </Link>
        </div>
      ) : sent ? (
        <div className="panel invite-sent" role="status">
          <span className="invite-sent-icon" aria-hidden="true">
            <Icon name="check" size={22} />
          </span>
          <div>
            <h2>Invite sent</h2>
            <p className="muted">
              {first} will see it next time they open Fishers. Once they accept, they&apos;re in {sent}.
            </p>
            <Link className="btn" href={`/clubs/${clubId}#members`}>
              Go to your members
            </Link>
          </div>
        </div>
      ) : clubs.length === 0 ? (
        <div className="panel">
          <h2>Start a club to invite {first}</h2>
          <p className="muted">
            Invites come from a club&apos;s secretary. Start your club and this link will be waiting.
          </p>
          <Link className="btn primary" href="/clubs?new=1">
            <Icon name="plus" size={16} /> Start your club
          </Link>
        </div>
      ) : (
        <div className="panel">
          <h2>Invite {first} to your club</h2>
          <p className="muted">
            They&apos;ll get an invite to accept — nobody is added to a club without saying yes.
          </p>
          {clubs.length > 1 && (
            <label>
              Club
              <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
                {clubs.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          <button className="btn primary lg" type="button" onClick={invite} disabled={busy}>
            <Icon name="send" size={16} /> {busy ? "Sending…" : `Invite to ${clubs.find((c) => c.id === clubId)?.name}`}
          </button>
          {error && <p className="error">{error}</p>}
        </div>
      )}
    </main>
  );
}
