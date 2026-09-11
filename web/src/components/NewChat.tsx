"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { api, getStoredUser, readErr, type Club, type ClubMemberRow, type Team } from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";
import { Sheet } from "@/components/Sheet";

type Person = { id: string; name: string; avatar?: string | null; clubs: string[]; clubIds: string[] };

/// Start a chat: with people, or a thread for a club or one of its teams.
///
/// People come from every club you are in at once — somebody in two clubs
/// with you is one person here, not two — with a chip per club to narrow it
/// down. One person opens your chat with them (or starts it); several make a
/// group. Only people you share a club with: a stranger cannot be messaged,
/// and cannot message you.
export function NewChat({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const [mode, setMode] = useState<"people" | "club">("people");
  const [clubs, setClubs] = useState<Club[] | null>(null);
  const [people, setPeople] = useState<Person[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const me = getStoredUser()?.id;
    (async () => {
      try {
        const mine = await api<Club[]>("GET", "/clubs");
        const rosters = await Promise.all(
          mine.map((c) => api<ClubMemberRow[]>("GET", `/clubs/${c.id}/members`).catch(() => [] as ClubMemberRow[]))
        );
        const byId = new Map<string, Person>();
        rosters.forEach((rows, i) => {
          for (const m of rows) {
            if (m.user_id === me || m.status !== "active") continue;
            const p = byId.get(m.user_id) ?? { id: m.user_id, name: m.name, avatar: m.avatar_url, clubs: [], clubIds: [] };
            p.clubs.push(mine[i].name);
            p.clubIds.push(mine[i].id);
            byId.set(m.user_id, p);
          }
        });
        setClubs(mine);
        setPeople([...byId.values()].sort((a, b) => a.name.localeCompare(b.name)));
      } catch (err) {
        setError(readErr(err, "Could not load your clubs"));
      }
    })();
  }, []);

  const open = async (body: Record<string, unknown>) => {
    setBusy(true);
    setError(null);
    try {
      const chat = await api<{ id: string }>("POST", "/conversations", body);
      onClose();
      router.push(`/chat/${chat.id}`);
    } catch (err) {
      setError(readErr(err, "Could not start that chat"));
      setBusy(false);
    }
  };

  return (
    <Sheet title="New chat" onClose={onClose}>
      <div className="people-tabs new-chat-modes" role="tablist" aria-label="Who is it with">
        <button type="button" role="tab" aria-selected={mode === "people"} className={mode === "people" ? "on" : undefined} onClick={() => setMode("people")}>
          <Icon name="chat" size={14} /> People
        </button>
        <button type="button" role="tab" aria-selected={mode === "club"} className={mode === "club" ? "on" : undefined} onClick={() => setMode("club")}>
          <Icon name="users" size={14} /> Club or team
        </button>
      </div>

      {clubs === null && !error && <div className="skeleton" style={{ height: 180, marginTop: "var(--s3)" }} />}
      {clubs?.length === 0 && (
        <div className="new-chat-empty">
          <p className="muted">
            You chat with the people in your clubs. Join one — or start yours — and they are all here.
          </p>
          <a className="btn primary" href="/clubs">
            <Icon name="users" size={16} /> Your clubs
          </a>
        </div>
      )}
      {clubs && clubs.length > 0 && mode === "people" && (
        <PickPeople clubs={clubs} people={people} busy={busy} onStart={open} />
      )}
      {clubs && clubs.length > 0 && mode === "club" && <PickClub clubs={clubs} busy={busy} onStart={open} />}
      {error && <p className="error">{error}</p>}
    </Sheet>
  );
}

function PickPeople({
  clubs,
  people,
  busy,
  onStart,
}: {
  clubs: Club[];
  people: Person[];
  busy: boolean;
  onStart: (body: Record<string, unknown>) => void;
}) {
  const [club, setClub] = useState("");
  const [term, setTerm] = useState("");
  const [chosen, setChosen] = useState<string[]>([]);
  const [name, setName] = useState("");

  const shown = useMemo(() => {
    const t = term.trim().toLowerCase();
    return people.filter((p) => (!club || p.clubIds.includes(club)) && (!t || p.name.toLowerCase().includes(t)));
  }, [people, club, term]);
  const picked = chosen.map((id) => people.find((p) => p.id === id)!).filter(Boolean);
  const toggle = (id: string) => setChosen((c) => (c.includes(id) ? c.filter((x) => x !== id) : [...c, id]));

  const firsts = picked.map((p) => p.name.split(" ")[0]);
  const groupName = firsts.length <= 3 ? firsts.join(", ").replace(/, ([^,]*)$/, " & $1") : `${firsts.slice(0, 2).join(", ")} & ${firsts.length - 2} more`;

  if (people.length === 0) {
    return <p className="muted new-chat-empty">Nobody else in your clubs yet. Add players first, and they appear here.</p>;
  }

  return (
    <>
      <input
        className="people-search"
        type="search"
        value={term}
        onChange={(e) => setTerm(e.target.value)}
        placeholder="Search by name"
        aria-label="Search by name"
      />
      {clubs.length > 1 && (
        <div className="chip-set new-chat-clubs" role="group" aria-label="Which club">
          <button type="button" className={`chip${club === "" ? " on" : ""}`} aria-pressed={club === ""} onClick={() => setClub("")}>
            All clubs
          </button>
          {clubs.map((c) => (
            <button key={c.id} type="button" className={`chip${club === c.id ? " on" : ""}`} aria-pressed={club === c.id} onClick={() => setClub(c.id)}>
              {c.name}
            </button>
          ))}
        </div>
      )}

      <ul className="people-list new-chat-people" aria-label="People">
        {shown.map((p) => {
          const on = chosen.includes(p.id);
          return (
            <li key={p.id}>
              <button type="button" role="checkbox" aria-checked={on} className={on ? "on" : undefined} onClick={() => toggle(p.id)}>
                <Avatar name={p.name} url={p.avatar} size={32} />
                <span className="people-name">
                  {p.name}
                  <span className="subtle new-chat-where">{p.clubs.join(" · ")}</span>
                </span>
                <span className="people-tick" aria-hidden>{on ? "✓" : ""}</span>
              </button>
            </li>
          );
        })}
        {shown.length === 0 && <li className="muted">Nobody by that name{club ? " in that club" : ""}.</li>}
      </ul>

      <div className="new-chat-go">
        {picked.length > 1 && (
          <label>
            Group name <span className="subtle">(optional)</span>
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder={groupName} maxLength={120} />
          </label>
        )}
        <button
          className="btn primary lg"
          type="button"
          disabled={busy || picked.length === 0}
          onClick={() =>
            onStart({
              kind: "direct",
              member_ids: chosen,
              title: picked.length === 1 ? picked[0].name : name.trim() || groupName,
            })
          }
        >
          <Icon name="send" size={16} />{" "}
          {busy
            ? "Opening…"
            : picked.length === 0
              ? "Choose who to message"
              : picked.length === 1
                ? `Message ${firsts[0]}`
                : `Start a group of ${picked.length + 1}`}
        </button>
      </div>
    </>
  );
}

function PickClub({
  clubs,
  busy,
  onStart,
}: {
  clubs: Club[];
  busy: boolean;
  onStart: (body: Record<string, unknown>) => void;
}) {
  const [clubId, setClubId] = useState(clubs[0].id);
  const [teams, setTeams] = useState<Team[]>([]);
  const [teamId, setTeamId] = useState("");
  const [title, setTitle] = useState("");

  useEffect(() => {
    setTeamId("");
    api<Team[]>("GET", `/clubs/${clubId}/teams`).then(setTeams, () => setTeams([]));
  }, [clubId]);

  const club = clubs.find((c) => c.id === clubId);
  return (
    <div className="setup-fields new-chat-club">
      {clubs.length > 1 && (
        <label>
          Club
          <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
            {clubs.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </label>
      )}
      <fieldset className="chip-set">
        <legend>Who&apos;s in it</legend>
        <button type="button" className={`chip${teamId === "" ? " on" : ""}`} aria-pressed={teamId === ""} onClick={() => setTeamId("")}>
          Everyone at {club?.name}
        </button>
        {teams.map((t) => (
          <button key={t.id} type="button" className={`chip${teamId === t.id ? " on" : ""}`} aria-pressed={teamId === t.id} onClick={() => setTeamId(t.id)}>
            {t.name}
          </button>
        ))}
      </fieldset>
      <label>
        What is it about
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Sunday XI, kit orders, winter nets" maxLength={120} />
      </label>
      <button
        className="btn primary lg"
        type="button"
        disabled={busy || !title.trim()}
        onClick={() =>
          onStart(teamId ? { kind: "team", club_id: clubId, team_id: teamId, title: title.trim() } : { kind: "club", club_id: clubId, title: title.trim() })
        }
      >
        <Icon name="plus" size={16} /> {busy ? "Starting…" : "Start the thread"}
      </button>
    </div>
  );
}
