"use client";

/// Bulk roster work for a secretary: paste a spreadsheet of people in, invite
/// them all, and fix roles across the whole club without opening one row at a
/// time.
///
/// What this deliberately cannot do is create accounts. Signing someone up
/// needs their password, which is theirs and not a secretary's to choose — so
/// the web tool invites, and scripts/register-from-csv.py is the thing that
/// registers people wholesale, run by an operator who has their consent.

import { use, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  api,
  readErr,
  roleLabel,
  CLUB_ROLES,
  type Club,
  type ClubMemberRow,
  type Invite,
  type MyRole,
} from "@/lib/api";
import { copyText } from "@/lib/clipboard";
import { useRequireAuth } from "@/lib/require-auth";

const ROLE_VALUES = CLUB_ROLES.map((r) => r.value) as readonly string[];
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PHONE_RE = /^\+[1-9]\d{6,14}$/;

/// One line of the pasted sheet, with whatever is wrong with it.
type Draft = {
  key: string;
  name: string;
  email: string;
  phone: string;
  role: string;
  problems: string[];
  /// Set once the row has been acted on, so a re-run skips it.
  done?: "invited" | "already a member" | "already invited";
  failed?: string;
};

const blank = (): Draft => ({
  key: Math.random().toString(36).slice(2),
  name: "",
  email: "",
  phone: "",
  role: "member",
  problems: [],
});

/// Excel and Sheets both put tabs between cells and newlines between rows.
/// CSV arrives the same way from a file, with commas — so one parser does both.
function parseSheet(text: string): Draft[] {
  const lines = text.replace(/\r\n?/g, "\n").split("\n").filter((l) => l.trim());
  if (!lines.length) return [];
  const sep = lines[0].includes("\t") ? "\t" : ",";
  const split = (line: string) =>
    line.split(sep).map((c) => c.trim().replace(/^"(.*)"$/, "$1"));

  let header: string[] | null = null;
  const first = split(lines[0]).map((c) => c.toLowerCase());
  if (first.includes("name") || first.includes("email")) header = first;

  const col = (cells: string[], want: string, fallback: number) => {
    if (!header) return cells[fallback] ?? "";
    const i = header.indexOf(want);
    return i === -1 ? "" : cells[i] ?? "";
  };

  return lines.slice(header ? 1 : 0).map((line) => {
    const cells = split(line);
    const row = blank();
    row.name = col(cells, "name", 0);
    row.email = col(cells, "email", 1);
    row.phone = col(cells, "phone", 2);
    const role = col(cells, "role", 3).toLowerCase().replace(/\s+/g, "_");
    row.role = ROLE_VALUES.includes(role) ? role : "member";
    return row;
  });
}

/// The same rules the CLI script applies, so a sheet that works in one works
/// in the other.
function check(rows: Draft[], members: ClubMemberRow[], invites: Invite[]): Draft[] {
  const seen = new Map<string, number>();
  const memberEmails = new Set(
    members.map((m) => (m.email || "").toLowerCase()).filter(Boolean)
  );
  const invitedEmails = new Set(
    invites
      .filter((i) => i.status === "pending")
      .map((i) => (i.invited_email || "").toLowerCase())
      .filter(Boolean)
  );

  return rows.map((row, index) => {
    const problems: string[] = [];
    if (!row.name.trim()) problems.push("needs a name");
    if (!row.email.trim() && !row.phone.trim()) problems.push("needs an email or a phone");
    if (row.email && !EMAIL_RE.test(row.email)) problems.push("email looks wrong");
    if (row.phone && !PHONE_RE.test(row.phone)) problems.push("phone must be +447700900123");
    if (!ROLE_VALUES.includes(row.role)) problems.push("unknown role");

    const ident = (row.email || row.phone || "").toLowerCase();
    if (ident) {
      const earlier = seen.get(ident);
      if (earlier !== undefined) problems.push(`same as row ${earlier + 1}`);
      else seen.set(ident, index);
    }

    let done = row.done;
    if (!done && row.email) {
      const e = row.email.toLowerCase();
      if (memberEmails.has(e)) done = "already a member";
      else if (invitedEmails.has(e)) done = "already invited";
    }
    return { ...row, problems, done };
  });
}

export default function ClubPeoplePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const authed = useRequireAuth();

  const [club, setClub] = useState<Club | null>(null);
  const [myRole, setMyRole] = useState<MyRole | null>(null);
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [invites, setInvites] = useState<Invite[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [tab, setTab] = useState<"import" | "members">("import");

  const [rows, setRows] = useState<Draft[]>([blank(), blank(), blank()]);
  const [running, setRunning] = useState(false);
  const [progress, setProgress] = useState<{ at: number; of: number } | null>(null);

  const load = useCallback(async () => {
    try {
      const [c, role, m] = await Promise.all([
        api<Club>("GET", `/clubs/${id}`),
        api<MyRole>("GET", `/clubs/${id}/my-role`),
        api<ClubMemberRow[]>("GET", `/clubs/${id}/members`),
      ]);
      setClub(c);
      setMyRole(role);
      setMembers(m);
      // Pending invites are best-effort: the page is still useful without them.
      setInvites(await api<Invite[]>("GET", "/invites/mine").catch(() => []));
    } catch (e) {
      setErr(readErr(e, "Could not load this club."));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (authed) void load();
  }, [authed, load]);

  const checked = useMemo(() => check(rows, members, invites), [rows, members, invites]);
  const ready = checked.filter((r) => !r.problems.length && !r.done && (r.name || r.email));
  const blocked = checked.filter((r) => r.problems.length && (r.name || r.email || r.phone));

  const setCell = (key: string, field: keyof Draft, value: string) =>
    setRows((prev) => {
      const next = prev.map((r) => (r.key === key ? { ...r, [field]: value } : r));
      // Typing in the last row grows the sheet, so it never runs out.
      const last = next[next.length - 1];
      if (last && (last.name || last.email || last.phone)) next.push(blank());
      return next;
    });

  const onPaste = (e: React.ClipboardEvent) => {
    const text = e.clipboardData.getData("text/plain");
    if (!text.includes("\t") && !text.includes("\n")) return; // one cell — let it be
    e.preventDefault();
    const parsed = parseSheet(text);
    if (parsed.length) setRows((prev) => [...prev.filter((r) => r.name || r.email), ...parsed, blank()]);
  };

  const onFile = async (file: File) => {
    const parsed = parseSheet(await file.text());
    if (parsed.length) setRows([...parsed, blank()]);
  };

  /// One invite per person, in sequence. No bulk endpoint exists, and firing
  /// fifty requests at once at a shared API to save four seconds is not a
  /// trade worth making.
  const invite = async () => {
    if (!ready.length || running) return;
    setRunning(true);
    setErr(null);
    const done: Record<string, Partial<Draft>> = {};
    for (let i = 0; i < ready.length; i++) {
      const row = ready[i];
      setProgress({ at: i + 1, of: ready.length });
      try {
        await api<Invite>("POST", "/invites", {
          target_type: "club",
          target_id: id,
          invited_email: row.email || undefined,
        });
        done[row.key] = { done: "invited", failed: undefined };
      } catch (e) {
        done[row.key] = { failed: readErr(e, "could not invite") };
      }
    }
    setRows((prev) => prev.map((r) => (done[r.key] ? { ...r, ...done[r.key] } : r)));
    setProgress(null);
    setRunning(false);
    await load();
  };

  const changeRole = async (userId: string, role: string) => {
    try {
      await api("PATCH", `/clubs/${id}/members/${userId}`, { role });
      setMembers((prev) => prev.map((m) => (m.user_id === userId ? { ...m, role } : m)));
    } catch (e) {
      setErr(readErr(e, "Could not change that role."));
    }
  };

  const remove = async (userId: string, name: string) => {
    if (!confirm(`Remove ${name} from ${club?.name ?? "this club"}?`)) return;
    try {
      await api("DELETE", `/clubs/${id}/members/${userId}`);
      setMembers((prev) => prev.filter((m) => m.user_id !== userId));
    } catch (e) {
      setErr(readErr(e, "Could not remove that member."));
    }
  };

  if (!authed || loading) return <main className="page"><p className="muted">Loading…</p></main>;

  if (myRole && !myRole.is_secretary) {
    return (
      <main className="page">
        <h1>People</h1>
        <p className="muted">
          Only a club secretary can bulk-manage the roster.{" "}
          <Link href={`/clubs/${id}`}>Back to the club</Link>.
        </p>
      </main>
    );
  }

  const pending = invites.filter(
    (i) => i.status === "pending" && i.target_type === "club" && i.target_id === id
  );

  return (
    <main className="page">
      <p className="muted" style={{ marginBottom: 4 }}>
        <Link href={`/clubs/${id}`}>← {club?.name ?? "Club"}</Link>
      </p>
      <h1>People</h1>
      <p className="muted">
        Paste a spreadsheet, import a CSV, or type. Same columns as{" "}
        <code>scripts/register-from-csv.example.csv</code>, so a sheet that works here works there.
      </p>

      {err && <p className="error" role="alert">{err}</p>}

      <nav className="tabs" style={{ margin: "16px 0" }}>
        <button className={`btn ghost${tab === "import" ? " active" : ""}`} onClick={() => setTab("import")}>
          Invite in bulk
        </button>
        <button className={`btn ghost${tab === "members" ? " active" : ""}`} onClick={() => setTab("members")}>
          Members ({members.length})
        </button>
      </nav>

      {tab === "import" ? (
        <section>
          <div style={{ display: "flex", gap: 12, alignItems: "center", marginBottom: 12 }}>
            <label className="btn ghost">
              Import CSV
              <input
                type="file"
                accept=".csv,text/csv,text/plain"
                style={{ display: "none" }}
                onChange={(e) => e.target.files?.[0] && void onFile(e.target.files[0])}
              />
            </label>
            <button className="btn ghost" onClick={() => setRows([blank(), blank(), blank()])}>
              Clear
            </button>
            <span className="muted">
              {ready.length} ready
              {blocked.length > 0 && <> · <strong>{blocked.length} to fix</strong></>}
            </span>
          </div>

          <div className="roster-grid" onPaste={onPaste}>
            <table>
              <thead>
                <tr>
                  <th style={{ width: 28 }} />
                  <th>Name</th>
                  <th>Email</th>
                  <th>Phone</th>
                  <th style={{ width: 150 }}>Role</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {checked.map((row, i) => (
                  <tr key={row.key} className={row.problems.length ? "bad" : undefined}>
                    <td className="muted">{i + 1}</td>
                    <td>
                      <input
                        value={row.name}
                        placeholder="Ada Fielding"
                        onChange={(e) => setCell(row.key, "name", e.target.value)}
                      />
                    </td>
                    <td>
                      <input
                        value={row.email}
                        placeholder="ada@example.com"
                        onChange={(e) => setCell(row.key, "email", e.target.value)}
                      />
                    </td>
                    <td>
                      <input
                        value={row.phone}
                        placeholder="+447700900123"
                        onChange={(e) => setCell(row.key, "phone", e.target.value)}
                      />
                    </td>
                    <td>
                      <select
                        value={row.role}
                        onChange={(e) => setCell(row.key, "role", e.target.value)}
                      >
                        {CLUB_ROLES.map((r) => (
                          <option key={r.value} value={r.value}>{r.label}</option>
                        ))}
                      </select>
                    </td>
                    <td className="muted">
                      {row.failed ? <span className="error">{row.failed}</span>
                        : row.done ? row.done
                        : row.problems.length ? row.problems.join("; ")
                        : ""}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <p className="muted" style={{ marginTop: 12 }}>
            An invite goes to the address; they set their own password. Roles above the
            invite are applied once they accept — a role cannot be given to someone who is
            not a member yet.
          </p>

          <button className="btn primary" onClick={invite} disabled={!ready.length || running} style={{ marginTop: 8 }}>
            {running && progress
              ? `Inviting ${progress.at} of ${progress.of}…`
              : `Invite ${ready.length || ""} ${ready.length === 1 ? "person" : "people"}`.trim()}
          </button>

          {pending.length > 0 && (
            <>
              <h2 style={{ marginTop: 32 }}>Pending invites ({pending.length})</h2>
              <ul className="card-list">
                {pending.map((i) => (
                  <li key={i.id} style={{ display: "flex", gap: 12, alignItems: "center" }}>
                    <span>{i.invited_email ?? "by link"}</span>
                    <button
                      className="btn ghost sm"
                      onClick={() => void copyText(`${location.origin}/invite/${i.token}`)}
                    >
                      Copy link
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}
        </section>
      ) : (
        <section>
          <div className="roster-grid">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Email</th>
                  <th>Phone</th>
                  <th style={{ width: 150 }}>Role</th>
                  <th style={{ width: 90 }} />
                </tr>
              </thead>
              <tbody>
                {members.map((m) => (
                  <tr key={m.user_id}>
                    <td>{m.name}</td>
                    <td className="muted">{m.email ?? "—"}</td>
                    <td className="muted">{m.phone ?? "—"}</td>
                    <td>
                      <select
                        value={ROLE_VALUES.includes(m.role) ? m.role : "member"}
                        onChange={(e) => void changeRole(m.user_id, e.target.value)}
                      >
                        {CLUB_ROLES.map((r) => (
                          <option key={r.value} value={r.value}>{r.label}</option>
                        ))}
                      </select>
                    </td>
                    <td>
                      <button className="btn ghost sm" onClick={() => void remove(m.user_id, m.name)}>
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted" style={{ marginTop: 12 }}>
            {members.length} member{members.length === 1 ? "" : "s"}. Changing a role takes
            effect immediately; {roleLabel("club_admin")} is the only role that can manage this page.
          </p>
        </section>
      )}
    </main>
  );
}
