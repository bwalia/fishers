"use client";

import Link from "next/link";
import { use, useEffect, useMemo, useState } from "react";
import {
  api,
  getAccessToken,
  getStoredUser,
  readErr,
  type Club,
  type MyRole,
  type SharedPlayerCard,
  type Team,
} from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";

type Place = { club: Club; role: MyRole; teams: Team[] };

/// Where a player's shared profile link lands.
///
/// The reader is a club secretary or a captain deciding whether to bring them
/// in, so the page is the player's card and one choice: which club, and which
/// team in it. The invite goes to their account as a notification they approve
/// — sharing a link never puts anyone in a club or a team they did not agree
/// to join.
export default function SharedProfilePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [card, setCard] = useState<SharedPlayerCard | null>(null);
  const [places, setPlaces] = useState<Place[] | null>(null);
  const [clubId, setClubId] = useState("");
  /// A team id, or "" for the club as a whole.
  const [teamId, setTeamId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const me = typeof window !== "undefined" ? getStoredUser() : null;

  useEffect(() => {
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
        const found = await Promise.all(
          mine.map(async (club) => {
            const role = await api<MyRole>("GET", `/clubs/${club.id}/my-role`).catch(() => null);
            // A secretary can add to the club or any team; a captain to a
            // team. The server has the final word on which team, and says so.
            if (!role || !(role.permissions.includes("invite_to_club") || role.permissions.includes("invite_to_team")))
              return null;
            const teams = await api<Team[]>("GET", `/clubs/${club.id}/teams`).catch(() => [] as Team[]);
            return { club, role, teams };
          })
        );
        const usable = found.filter((p): p is Place => !!p);
        setCard(c);
        setPlaces(usable);
        // Arriving from "Add by link" on a club or team page: start there.
        const q = new URLSearchParams(window.location.search);
        const wantClub = usable.find((p) => p.club.id === q.get("club")) ?? usable[0];
        if (wantClub) {
          setClubId(wantClub.club.id);
          const wantTeam = wantClub.teams.find((t) => t.id === q.get("team"));
          setTeamId(wantTeam?.id ?? (canInviteToClub(wantClub) ? "" : wantClub.teams[0]?.id ?? ""));
        }
      } catch (err) {
        setError(readErr(err, "That profile link did not open"));
      }
    })();
  }, [token]);

  const place = useMemo(() => places?.find((p) => p.club.id === clubId) ?? null, [places, clubId]);
  const team = place?.teams.find((t) => t.id === teamId) ?? null;
  const target = team ? team.name : place?.club.name;

  const invite = async () => {
    if (!card || !place) return;
    setBusy(true);
    setError(null);
    try {
      await api("POST", "/invites", {
        target_type: team ? "team" : "club",
        target_id: team ? team.id : place.club.id,
        invited_user_id: card.id,
      });
      setSent(team ? `${team.name} at ${place.club.name}` : place.club.name);
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
  if (!card || places === null) {
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
              .join(" · ") || <span className="plain">Profile not filled in yet</span>}
          </p>
        </div>
      </div>

      {isMe ? (
        <div className="panel">
          <h2>This is your own link</h2>
          <p className="muted">
            Send it to your club&apos;s secretary or captain. They add you from it, and you get a
            notification to approve.
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
              {first} gets a notification to approve. The moment they do, they&apos;re in {sent} — and
              you&apos;ll be told.
            </p>
            <Link className="btn" href={`/clubs/${clubId}#members`}>
              Go to your members
            </Link>
          </div>
        </div>
      ) : places.length === 0 ? (
        <div className="panel">
          <h2>Start a club to add {first}</h2>
          <p className="muted">
            Players are added by a club&apos;s secretary or a team&apos;s captain. Start your club and this
            link will be waiting.
          </p>
          <Link className="btn primary" href="/clubs?new=1">
            <Icon name="plus" size={16} /> Start your club
          </Link>
        </div>
      ) : (
        <div className="panel">
          <h2>Add {first} to your club</h2>
          <p className="muted">
            They get a notification to approve — nobody is added anywhere without saying yes.
          </p>

          {places.length > 1 && (
            <label>
              Club
              <select
                value={clubId}
                onChange={(e) => {
                  const next = places.find((p) => p.club.id === e.target.value);
                  setClubId(e.target.value);
                  setTeamId(next && canInviteToClub(next) ? "" : next?.teams[0]?.id ?? "");
                }}
              >
                {places.map((p) => (
                  <option key={p.club.id} value={p.club.id}>
                    {p.club.name}
                  </option>
                ))}
              </select>
            </label>
          )}

          {place && (place.teams.length > 0 || !canInviteToClub(place)) && (
            <fieldset className="chip-set add-to">
              <legend>Add them to</legend>
              {canInviteToClub(place) && (
                <button
                  type="button"
                  className={`chip${teamId === "" ? " on" : ""}`}
                  aria-pressed={teamId === ""}
                  onClick={() => setTeamId("")}
                >
                  The club
                </button>
              )}
              {place.teams.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  className={`chip${teamId === t.id ? " on" : ""}`}
                  aria-pressed={teamId === t.id}
                  onClick={() => setTeamId(t.id)}
                >
                  {t.name}
                </button>
              ))}
            </fieldset>
          )}
          {place && !canInviteToClub(place) && place.teams.length === 0 && (
            <p className="muted">This club has no teams yet — the secretary adds those first.</p>
          )}

          <button
            className="btn primary lg"
            type="button"
            onClick={invite}
            disabled={busy || !place || (!team && !canInviteToClub(place))}
          >
            <Icon name="send" size={16} /> {busy ? "Sending…" : `Add to ${target ?? "your club"}`}
          </button>
          {team && (
            <p className="subtle add-to-note">
              Joining {team.name} makes them a member of {place?.club.name} too.
            </p>
          )}
          {error && <p className="error">{error}</p>}
        </div>
      )}
    </main>
  );
}

function canInviteToClub(p: Place) {
  return p.role.is_secretary || p.role.permissions.includes("invite_to_club");
}
