"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Icon } from "@/components/Icon";
import { readErr } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import {
  adminFindUsers,
  adminOverview,
  bytes,
  money,
  type AdminOverview,
  type AdminUser,
  type Growth,
} from "@/lib/admin";

/// The whole system on one page.
///
/// Ordered the way somebody reads it when something is wrong: what is broken
/// first, then how big everything is, then what just happened. The counts are
/// the reassuring part and they go in the middle, because nobody opens this at
/// eleven at night to admire the number of clubs.
export default function AdminPage() {
  const authed = useRequireAuth();
  const [data, setData] = useState<AdminOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setData(await adminOverview());
      setError(null);
    } catch (err) {
      // The API answers 404 rather than 403 to anybody not on the list, so
      // "not found" here means "not you" — say that rather than the literal.
      setError(readErr(err, "Could not load the system view"));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (authed) load();
  }, [authed, load]);

  if (!authed) return <main id="main" />;

  if (loading && !data)
    return (
      <main id="main" className="adm">
        <div className="skeleton" style={{ height: 280, borderRadius: "var(--radius)" }} />
      </main>
    );

  if (error)
    return (
      <main id="main" className="adm">
        <div className="panel">
          <h1>System</h1>
          <p className="error">{error}</p>
          <p className="muted">
            This page is for whoever runs the service. If that is you, your address has to be
            in <code>PLATFORM_ADMIN_EMAILS</code> and confirmed.
          </p>
        </div>
      </main>
    );

  if (!data) return <main id="main" className="adm" />;

  const { people, clubs, cricket, money: takings, health, recent } = data;
  const problems = countProblems(data);

  return (
    <main id="main" className="adm">
      <header className="adm-head">
        <div>
          <h1>System</h1>
          <p className="muted">
            Taken {new Date(data.taken_at).toLocaleString()} ·{" "}
            <button type="button" className="linkish" onClick={load} disabled={loading}>
              {loading ? "Refreshing…" : "Refresh"}
            </button>
          </p>
        </div>
        <span className={problems === 0 ? "tag" : "tag warn"}>
          {problems === 0 ? "Nothing needs you" : `${problems} to look at`}
        </span>
      </header>

      <Health health={health} money={takings} />

      <section className="adm-grid" aria-label="How big the system is">
        <Figure label="People" value={people.users.total} growth={people.users} />
        <Figure label="Clubs" value={clubs.clubs.total} growth={clubs.clubs} />
        <Figure label="Matches" value={cricket.matches.total} growth={cricket.matches} />
        <Figure label="Balls scored" value={cricket.scoring_events} />
      </section>

      <div className="adm-cols">
        <Panel title="People" icon="users">
          <Row label="Registered" value={people.users.total} />
          <Row label="Email confirmed" value={people.email_verified} of={people.users.total} />
          <Row label="Phone confirmed" value={people.phone_verified} of={people.users.total} />
          <Row label="Signed in somewhere" value={people.active_sessions} />
          <Row label="Devices taking push" value={people.push_devices} />
          <Row label="Deleted accounts" value={people.deleted} muted />
        </Panel>

        <Panel title="Clubs" icon="shield">
          <Row label="Clubs" value={clubs.clubs.total} />
          <Row label="Teams" value={clubs.teams} />
          <Row label="Memberships" value={clubs.memberships} />
          <Row label="With nobody but the owner" value={clubs.empty} muted />
          {clubs.by_sport.length > 0 && (
            <div className="adm-chips">
              {clubs.by_sport.map((s) => (
                <span key={s.sport} className="chip">
                  {s.sport} <b>{s.clubs}</b>
                </span>
              ))}
            </div>
          )}
        </Panel>

        <Panel title="Cricket" icon="bat">
          <Row label="Fixtures ahead" value={cricket.fixtures_ahead} />
          <Row label="Balls scored" value={cricket.scoring_events} />
          {cricket.by_status.length > 0 && (
            <div className="adm-chips">
              {cricket.by_status.map((s) => (
                <span key={s.status} className="chip">
                  {s.status.replace(/_/g, " ")} <b>{s.count}</b>
                </span>
              ))}
            </div>
          )}
        </Panel>

        <Panel title="Money" icon="shop">
          {takings.taken.length === 0 ? (
            <p className="muted">Nothing taken yet.</p>
          ) : (
            takings.taken.map((t) => (
              <Row
                key={t.currency}
                label={`Taken (${t.currency.toUpperCase()})`}
                text={`${money(t.amount_cents, t.currency)} · ${t.payments} payments`}
              />
            ))
          )}
          <Row label="Payments" value={takings.payments.total} />
          <Row label="Failed this week" value={takings.failed_7d} bad={takings.failed_7d > 0} />
          <Row label="Ordered, not paid" value={takings.unpaid_orders} />
        </Panel>
      </div>

      <FindSomebody />

      <section className="panel">
        <h2>
          <Icon name="clock" size={18} /> What just happened
        </h2>
        {recent.length === 0 ? (
          <p className="muted">Nothing recorded yet.</p>
        ) : (
          <ul className="adm-feed">
            {recent.map((e) => (
              <li key={e.id}>
                <code>{e.event_type}</code>
                {e.club_name && <span className="muted"> · {e.club_name}</span>}
                <time dateTime={e.occurred_at}>{new Date(e.occurred_at).toLocaleString()}</time>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

/// How many things are worth a look. Drives the one word at the top, which is
/// the only part read from across the room.
function countProblems(d: AdminOverview): number {
  const h = d.health;
  return (
    (h.migrations_failed > 0 ? 1 : 0) +
    (h.webhooks_unprocessed > 0 ? 1 : 0) +
    (h.agent_failures_7d > 0 ? 1 : 0) +
    (d.money.failed_7d > 0 ? 1 : 0)
  );
}

function Health({
  health,
  money: takings,
}: {
  health: AdminOverview["health"];
  money: AdminOverview["money"];
}) {
  const checks = [
    {
      label: "Schema",
      text: `migration ${health.migration}`,
      bad: health.migrations_failed > 0,
      badText: `${health.migrations_failed} migration failed — the API is running against a schema it does not expect`,
    },
    {
      label: "Stripe webhooks",
      text: "all processed",
      bad: health.webhooks_unprocessed > 0,
      badText: `${health.webhooks_unprocessed} received and not processed — payments may look unpaid`,
    },
    {
      label: "Payments",
      text: "none failed this week",
      bad: takings.failed_7d > 0,
      badText: `${takings.failed_7d} failed this week`,
    },
    {
      label: "Assistant",
      text: "no errors this week",
      bad: health.agent_failures_7d > 0,
      badText: `${health.agent_failures_7d} runs failed${
        health.agent_last_error ? ` — last: ${health.agent_last_error}` : ""
      }`,
    },
  ];

  return (
    <section className="panel adm-health" aria-label="What might be wrong">
      <ul>
        {checks.map((c) => (
          <li key={c.label} className={c.bad ? "bad" : "ok"}>
            <Icon name={c.bad ? "help" : "check"} size={16} />
            <strong>{c.label}</strong>
            <span>{c.bad ? c.badText : c.text}</span>
          </li>
        ))}
      </ul>
      <p className="muted adm-health-foot">
        Codes waiting {health.codes_pending} · Notifications 24h {health.notifications_24h} (
        {health.notifications_unread} unread) · Database {bytes(health.database_bytes)}
      </p>
    </section>
  );
}

function Figure({ label, value, growth }: { label: string; value: number; growth?: Growth }) {
  return (
    <div className="adm-figure">
      <strong>{value.toLocaleString()}</strong>
      <span className="muted">{label}</span>
      {growth && (
        <span className="adm-delta">
          +{growth.last_7d} this week · +{growth.last_30d} this month
        </span>
      )}
    </div>
  );
}

function Panel({
  title,
  icon,
  children,
}: {
  title: string;
  icon: "users" | "shield" | "bat" | "shop";
  children: React.ReactNode;
}) {
  return (
    <section className="panel">
      <h2>
        <Icon name={icon} size={18} /> {title}
      </h2>
      {children}
    </section>
  );
}

function Row({
  label,
  value,
  text,
  of,
  muted,
  bad,
}: {
  label: string;
  value?: number;
  text?: string;
  /// Shows "12 of 40" — a count that only means something against a total.
  of?: number;
  muted?: boolean;
  bad?: boolean;
}) {
  return (
    <p className={`adm-row${muted ? " muted" : ""}${bad ? " bad" : ""}`}>
      <span>{label}</span>
      <b>
        {text ?? value?.toLocaleString()}
        {of !== undefined && value !== undefined && of > 0 && (
          <em> of {of.toLocaleString()}</em>
        )}
      </b>
    </p>
  );
}

/// Look somebody up, because most of what goes wrong arrives as "I cannot log
/// in" from one person rather than as a number on a dashboard.
function FindSomebody() {
  const [q, setQ] = useState("");
  const [results, setResults] = useState<AdminUser[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const search = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      setResults(await adminFindUsers(q));
    } catch (err) {
      setError(readErr(err, "Could not search"));
      setResults(null);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel">
      <h2>
        <Icon name="search" size={18} /> Find somebody
      </h2>
      <form className="adm-search" onSubmit={search}>
        <label className="sr-only" htmlFor="adm-q">
          Name, email or phone number
        </label>
        <input
          id="adm-q"
          value={q}
          placeholder="Name, email or phone"
          onChange={(e) => setQ(e.target.value)}
        />
        <button className="btn primary" disabled={busy || q.trim().length < 2}>
          {busy ? "Looking…" : "Search"}
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      {results && results.length === 0 && <p className="muted">Nobody matches that.</p>}
      {results && results.length > 0 && (
        <ul className="adm-people">
          {results.map((u) => (
            <li key={u.id} className={u.deleted_at ? "gone" : ""}>
              <div>
                <strong>{u.name}</strong>
                {u.deleted_at && <span className="tag">Deleted</span>}
                <span className="muted">
                  {u.email ?? "no email"}
                  {u.email && !u.email_verified && " (unconfirmed)"}
                  {u.phone ? ` · ${u.phone}` : ""}
                  {u.phone && !u.phone_verified && " (unconfirmed)"}
                </span>
              </div>
              <span className="muted adm-people-meta">
                {u.clubs} {u.clubs === 1 ? "club" : "clubs"} · {u.active_sessions} signed in ·
                joined {new Date(u.created_at).toLocaleDateString()}
              </span>
            </li>
          ))}
        </ul>
      )}
      <p className="muted">
        Shows contact details, which no other page does.{" "}
        <Link href="/privacy">What we hold, and why</Link>.
      </p>
    </section>
  );
}
