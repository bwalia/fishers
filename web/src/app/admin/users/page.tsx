"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Icon } from "@/components/Icon";
import { readErr } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import { adminUsers, type AdminUserPage, type AdminUserRow } from "@/lib/admin";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n";

/// Labels are keys, resolved at render. They used to be a mix of keys and bare
/// English, so the first two options printed "le.newest" at the reader.
const SORTS: { key: string; label: Key }[] = [
  { key: "newest", label: "le.newest" },
  { key: "oldest", label: "le.oldest" },
  { key: "name", label: "rest.name" },
  { key: "matches", label: "rest.matches" },
  { key: "clubs", label: "rest.clubs" },
  { key: "last_seen", label: "rest.last_seen" },
];

/// Everybody, as a table somebody can actually work down.
///
/// No search term shows the whole table, because the commonest reason to open
/// this is not looking for one person — it is wanting to see who is here.
export default function AdminUsersPage() {
  const t = useT();
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
      setError(readErr(err, t("le.could_not_load_the_people")));
    } finally {
      setLoading(false);
    }
  }, [applied, sort, page, t]);

  useEffect(() => {
    if (authed) load();
  }, [authed, load]);

  if (!authed) return <main id="main" />;

  const pages = data ? Math.max(1, Math.ceil(data.total / data.per_page)) : 1;

  return (
    <main id="main" className="adm">
      <header className="adm-head">
        <div>
          <h1>{t("rest.people")}</h1>
          <p className="muted">
            <Link href="/admin">← System</Link>
            {data && t("rest.in_total", { n: data.total.toLocaleString() })}
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
        <label className="sr-only" htmlFor="adm-users-q">{t("rest.name_email_or_phone")}</label>
        <input
          id="adm-users-q"
          value={q}
          placeholder={t("rest.name_email_or_phone_blank_for_everybod")}
          onChange={(e) => setQ(e.target.value)}
        />
        <button className="btn primary">{t("rest.search")}</button>
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
            {t("rest.clear")}
          </button>
        )}
        <select
          aria-label={t("rest.sort_by")}
          value={sort}
          onChange={(e) => {
            setSort(e.target.value);
            setPage(1);
          }}
        >
          {SORTS.map((s) => (
            <option key={s.key} value={s.key}>{t(s.label)}</option>
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
                  <th scope="col">{t("rest.name")}</th>
                  <th scope="col">{t("rest.contact")}</th>
                  <th scope="col">{t("rest.plays")}</th>
                  <th scope="col" className="num">{t("rest.clubs")}</th>
                  <th scope="col" className="num">{t("rest.matches")}</th>
                  <th scope="col">{t("rest.joined")}</th>
                  <th scope="col">{t("rest.last_seen")}</th>
                </tr>
              </thead>
              <tbody>
                {data.rows.map((u) => <Row key={u.id} u={u} />)}
              </tbody>
            </table>
          </div>

          {data.rows.length === 0 && <p className="muted">{t("rest.nobody_matches_that")}</p>}

          {pages > 1 && (
            <nav className="adm-pager" aria-label={t("rest.pages")}>
              <button className="btn" disabled={page <= 1} onClick={() => setPage(page - 1)}>
                {t("rest.previous")}
              </button>
              <span className="muted">
                {t("rest.page_of", { page: data.page, pages })}
              </span>
              <button className="btn" disabled={page >= pages} onClick={() => setPage(page + 1)}>
                {t("rest.next")}
              </button>
            </nav>
          )}
        </>
      )}
    </main>
  );
}

function Row({ u }: { u: AdminUserRow }) {
  const t = useT();
  return (
    <tr className={u.deleted_at ? "gone" : undefined}>
      <th scope="row">
        <Link href={`/admin/users/${u.id}`}>{u.name}</Link>
        {u.deleted_at && <span className="tag">{t("rest.deleted")}</span>}
      </th>
      <td>
        <span className="adm-contact">
          {u.email ?? <em className="muted">{t("rest.no_email")}</em>}
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
      <td>{u.last_seen ? new Date(u.last_seen).toLocaleDateString() : <span className="muted">{t("rest.never")}</span>}</td>
    </tr>
  );
}

/// Never colour alone: an icon and a word, because "unconfirmed" is the thing
/// somebody is scanning for when a person says they cannot log in.
function Unconfirmed() {
  const t = useT();
  return (
    <span className="adm-unconfirmed" title={t("rest.not_confirmed")}>
      <Icon name="help" size={13} /> {t("rest.unconfirmed")}
    </span>
  );
}
