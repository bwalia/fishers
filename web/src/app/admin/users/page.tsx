"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Icon } from "@/components/Icon";
import { readErr } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import { adminUsers, type AdminUserPage, type AdminUserRow } from "@/lib/admin";

const SORTS = [
  { key: "newest", label: "Newest" },
  { key: "oldest", label: "Oldest" },
  { key: "name", label: "Name" },
  { key: "matches", label: "Matches" },
  { key: "clubs", label: "Clubs" },
  { key: "last_seen", label: "Last seen" },
];

/// Everybody, as a table somebody can actually work down.
///
/// No search term shows the whole table, because the commonest reason to open
/// this is not looking for one person — it is wanting to see who is here.
export default function AdminUsersPage() {
  const authed = useRequireAuth();
  const [q, setQ] = useState("");
  const [applied, setApplied] = useState("");
  const [sort, setSort] = useState("newest");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<AdminUserPage | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setData(await adminUsers({ q: applied || undefined, sort, page, per_page: 50 }));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load the people"));
    } finally {
      setLoading(false);
    }
  }, [applied, sort, page]);

  useEffect(() => {
    if (authed) load();
  }, [authed, load]);

  if (!authed) return <main id="main" />;

  const pages = data ? Math.max(1, Math.ceil(data.total / data.per_page)) : 1;

  return (
    <main id="main" className="adm">
      <header className="adm-head">
        <div>
          <h1>People</h1>
          <p className="muted">
            <Link href="/admin">← System</Link>
            {data && ` · ${data.total.toLocaleString()} in total`}
          </p>
        </div>
      </header>

      <form
        className="adm-search"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setApplied(q.trim());
        }}
      >
        <label className="sr-only" htmlFor="adm-users-q">Name, email or phone</label>
        <input
          id="adm-users-q"
          value={q}
          placeholder="Name, email or phone — blank for everybody"
          onChange={(e) => setQ(e.target.value)}
        />
        <button className="btn primary">Search</button>
        {applied && (
          <button
            type="button"
            className="btn"
            onClick={() => {
              setQ("");
              setApplied("");
              setPage(1);
            }}
          >
            Clear
          </button>
        )}
        <select
          aria-label="Sort by"
          value={sort}
          onChange={(e) => {
            setSort(e.target.value);
            setPage(1);
          }}
        >
          {SORTS.map((s) => (
            <option key={s.key} value={s.key}>{s.label}</option>
          ))}
        </select>
      </form>

      {error && <p className="error">{error}</p>}
      {loading && !data && <div className="skeleton" style={{ height: 320 }} />}

      {data && (
        <>
          <div className="adm-table-wrap">
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">Name</th>
                  <th scope="col">Contact</th>
                  <th scope="col">Plays</th>
                  <th scope="col" className="num">Clubs</th>
                  <th scope="col" className="num">Matches</th>
                  <th scope="col">Joined</th>
                  <th scope="col">Last seen</th>
                </tr>
              </thead>
              <tbody>
                {data.rows.map((u) => <Row key={u.id} u={u} />)}
              </tbody>
            </table>
          </div>

          {data.rows.length === 0 && <p className="muted">Nobody matches that.</p>}

          {pages > 1 && (
            <nav className="adm-pager" aria-label="Pages">
              <button className="btn" disabled={page <= 1} onClick={() => setPage(page - 1)}>
                Previous
              </button>
              <span className="muted">
                Page {data.page} of {pages}
              </span>
              <button className="btn" disabled={page >= pages} onClick={() => setPage(page + 1)}>
                Next
              </button>
            </nav>
          )}
        </>
      )}
    </main>
  );
}

function Row({ u }: { u: AdminUserRow }) {
  return (
    <tr className={u.deleted_at ? "gone" : undefined}>
      <th scope="row">
        <Link href={`/admin/users/${u.id}`}>{u.name}</Link>
        {u.deleted_at && <span className="tag">Deleted</span>}
      </th>
      <td>
        <span className="adm-contact">
          {u.email ?? <em className="muted">no email</em>}
          {u.email && !u.email_verified && <Unconfirmed />}
        </span>
        {u.phone && (
          <span className="adm-contact">
            {u.phone}
            {!u.phone_verified && <Unconfirmed />}
          </span>
        )}
      </td>
      <td>
        {u.primary_sport ?? <span className="muted">—</span>}
        {u.position_role && <span className="muted"> · {u.position_role}</span>}
        {u.skill_level && <span className="muted"> · {u.skill_level}</span>}
      </td>
      <td className="num">{u.clubs}</td>
      <td className="num">{u.matches}</td>
      <td>{new Date(u.created_at).toLocaleDateString()}</td>
      <td>{u.last_seen ? new Date(u.last_seen).toLocaleDateString() : <span className="muted">never</span>}</td>
    </tr>
  );
}

/// Never colour alone: an icon and a word, because "unconfirmed" is the thing
/// somebody is scanning for when a person says they cannot log in.
function Unconfirmed() {
  return (
    <span className="adm-unconfirmed" title="Not confirmed">
      <Icon name="help" size={13} /> unconfirmed
    </span>
  );
}
