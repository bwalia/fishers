"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, getStoredUser, readErr, type Club, type ClubMemberRow, type Team } from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";
import { SearchSelect } from "@/components/SearchSelect";
import { Sheet } from "@/components/Sheet";
import { useT } from "@/lib/i18n/provider";

type Person = { id: string; name: string; avatar?: string | null; clubs: string[]; clubIds: string[] };

/// Start a chat: with people, or a thread for a club or one of its teams.
///
/// People come from every club you are in at once — somebody in two clubs
/// with you is one person here, not two — with a chip per club to narrow it
/// down. One person opens your chat with them (or starts it); several make a
/// group. Only people you share a club with: a stranger cannot be messaged,
/// and cannot message you.
export function NewChat({ onClose }: { onClose: () => void }) {
  const t = useT();
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
        setError(readErr(err, t("sh.could_not_load_clubs")));
      }
    })();
  }, [t]);

  const open = async (body: Record<string, unknown>) => {
    setBusy(true);
    setError(null);
    try {
      const chat = await api<{ id: string }>("POST", "/conversations", body);
      onClose();
      router.push(`/chat/${chat.id}`);
    } catch (err) {
      setError(readErr(err, t("le.could_not_start_that_chat")));
      setBusy(false);
    }
  };

  return (
    <Sheet title={t("le.new_chat")} onClose={onClose}>
      <div className="people-tabs new-chat-modes" role="tablist" aria-label={t("rest.who_is_it_with")}>
        <button type="button" role="tab" aria-selected={mode === "people"} className={mode === "people" ? "on" : undefined} onClick={() => setMode("people")}>
          <Icon name="chat" size={14} /> {t("rest.people")}
        </button>
        <button type="button" role="tab" aria-selected={mode === "club"} className={mode === "club" ? "on" : undefined} onClick={() => setMode("club")}>
          <Icon name="users" size={14} /> {t("rest.club_or_team")}
        </button>
      </div>

      {clubs === null && !error && <div className="skeleton" style={{ height: 180, marginTop: "var(--s3)" }} />}
      {clubs?.length === 0 && (
        <div className="new-chat-empty">
          <p className="muted">
            {t("rest.you_chat_with_the_people_in_your_clubs")}
          </p>
          <Link className="btn primary" href="/clubs">
            <Icon name="users" size={16} /> {t("rest.your_clubs")}
          </Link>
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
  const t = useT();
  const [club, setClub] = useState("");
  const [term, setTerm] = useState("");
  const [chosen, setChosen] = useState<string[]>([]);
  const [name, setName] = useState("");

  const findClub = useCallback(
    async (needle: string) => {
      const term = needle.toLowerCase();
      return clubs.filter((c) => !term || c.name.toLowerCase().includes(term));
    },
    [clubs]
  );

  const shown = useMemo(() => {
    const t = term.trim().toLowerCase();
    return people.filter((p) => (!club || p.clubIds.includes(club)) && (!t || p.name.toLowerCase().includes(t)));
  }, [people, club, term]);
  const picked = chosen.map((id) => people.find((p) => p.id === id)!).filter(Boolean);
  const toggle = (id: string) => setChosen((c) => (c.includes(id) ? c.filter((x) => x !== id) : [...c, id]));

  const firsts = picked.map((p) => p.name.split(" ")[0]);
  const groupName = firsts.length <= 3 ? firsts.join(", ").replace(/, ([^,]*)$/, " & $1") : `${firsts.slice(0, 2).join(", ")} & ${firsts.length - 2} more`;

  if (people.length === 0) {
    return <p className="muted new-chat-empty">{t("rest.nobody_else_in_your_clubs_yet_add_play")}</p>;
  }

  return (
    <>
      <input
        className="people-search"
        type="search"
        value={term}
        onChange={(e) => setTerm(e.target.value)}
        placeholder={t("rest.search_by_name")}
        aria-label={t("rest.search_by_name")}
      />
      {clubs.length > 1 && (
        <div className="new-chat-clubs">
          <SearchSelect
            value={club}
            onChange={setClub}
            search={findClub}
            label={t("ev.which_club")}
            anyLabel={t("ev.all_clubs")}
          />
        </div>
      )}

      <ul className="people-list new-chat-people" aria-label={t("rest.people")}>
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
            {t("rest.group_name")} <span className="subtle">(optional)</span>
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
              ? t("le.choose_who_to_message")
              : picked.length === 1
                ? `Message ${firsts[0]}`
                : t("fin.start_a_group_of", { n: picked.length + 1 })}
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
  const t = useT();
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
        <legend>{t("le.whos_in_it")}</legend>
        <button type="button" className={`chip${teamId === "" ? " on" : ""}`} aria-pressed={teamId === ""} onClick={() => setTeamId("")}>
          {t("le.everyone_at_club", { club: club?.name ?? "" })}
        </button>
        {teams.map((t) => (
          <button key={t.id} type="button" className={`chip${teamId === t.id ? " on" : ""}`} aria-pressed={teamId === t.id} onClick={() => setTeamId(t.id)}>
            {t.name}
          </button>
        ))}
      </fieldset>
      <label>
        {t("rest.what_is_it_about")}
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={t("rest.sunday_xi_kit_orders_winter_nets")} maxLength={120} />
      </label>
      <button
        className="btn primary lg"
        type="button"
        disabled={busy || !title.trim()}
        onClick={() =>
          onStart(teamId ? { kind: "team", club_id: clubId, team_id: teamId, title: title.trim() } : { kind: "club", club_id: clubId, title: title.trim() })
        }
      >
        <Icon name="plus" size={16} /> {busy ? "Starting…" : t("le.start_the_thread")}
      </button>
    </div>
  );
}
