"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Icon } from "@/components/Icon";
import { readErr } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import {
  adminOverview,
  bytes,
  money,
  type AdminOverview,
  type Growth,
} from "@/lib/admin";
import { useT } from "@/lib/i18n/provider";

/// The whole system on one page.
///
/// Ordered the way somebody reads it when something is wrong: what is broken
/// first, then how big everything is, then what just happened. The counts are
/// the reassuring part and they go in the middle, because nobody opens this at
/// eleven at night to admire the number of clubs.
export default function AdminPage() {
  const t = useT();
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
      setError(readErr(err, t("le.could_not_load_the_system_view")));
    } finally {
      setLoading(false);
    }
  }, [t]);

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
          <h1>{t("rest.system")}</h1>
          <p className="error">{error}</p>
          <p className="muted">
            {t("rest.this_page_is_for_whoever_runs_the_serv")} <code>PLATFORM_ADMIN_EMAILS</code> {t("rest.and_confirmed")}
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
          <h1>{t("rest.system")}</h1>
          <p className="muted">
            {t("rest.taken_at", { when: new Date(data.taken_at).toLocaleString() })} ·{" "}
            <button type="button" className="linkish" onClick={load} disabled={loading}>
              {loading ? t("le.refreshing") : t("rest.refresh")}
            </button>
          </p>
        </div>
        <span className={problems === 0 ? "tag" : "tag warn"}>
          {problems === 0 ? t("le.nothing_needs_you") : t("rest.n_to_look_at", { n: problems })}
        </span>
      </header>

      <Health health={health} money={takings} />

      <section className="adm-grid" aria-label={t("rest.how_big_the_system_is")}>
        <Figure label={t("rest.people")} value={people.users.total} growth={people.users} />
        <Figure label={t("rest.clubs")} value={clubs.clubs.total} growth={clubs.clubs} />
        <Figure label={t("rest.matches")} value={cricket.matches.total} growth={cricket.matches} />
        <Figure label={t("rest.balls_scored")} value={cricket.scoring_events} />
      </section>

      <div className="adm-cols">
        <Panel title={t("rest.people")} icon="users">
          <Row label={t("rest.registered")} value={people.users.total} />
          <Row label={t("rest.email_confirmed")} value={people.email_verified} of={people.users.total} />
          <Row label={t("rest.phone_confirmed")} value={people.phone_verified} of={people.users.total} />
          <Row label={t("rest.signed_in_somewhere")} value={people.active_sessions} />
          <Row label={t("rest.devices_taking_push")} value={people.push_devices} />
          <Row label={t("rest.deleted_accounts")} value={people.deleted} muted />
        </Panel>

        <Panel title={t("rest.clubs")} icon="shield">
          <Row label={t("rest.clubs")} value={clubs.clubs.total} />
          <Row label={t("rest.teams")} value={clubs.teams} />
          <Row label={t("rest.memberships")} value={clubs.memberships} />
          <Row label={t("rest.with_nobody_but_the_owner")} value={clubs.empty} muted />
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

        <Panel title={t("rest.cricket")} icon="bat">
          <Row label={t("rest.fixtures_ahead")} value={cricket.fixtures_ahead} />
          <Row label={t("rest.balls_scored")} value={cricket.scoring_events} />
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

        <Panel title={t("rest.money")} icon="shop">
          {takings.taken.length === 0 ? (
            <p className="muted">{t("rest.nothing_taken_yet")}</p>
          ) : (
            takings.taken.map((row) => (
              <Row
                key={row.currency}
                label={t("rest.taken_currency", { currency: row.currency.toUpperCase() })}
                text={t("rest.amount_and_payments", {
                  amount: money(row.amount_cents, row.currency),
                  n: row.payments,
                })}
              />
            ))
          )}
          <Row label={t("rest.payments")} value={takings.payments.total} />
          <Row label={t("rest.failed_this_week")} value={takings.failed_7d} bad={takings.failed_7d > 0} />
          <Row label={t("rest.ordered_not_paid")} value={takings.unpaid_orders} />
        </Panel>
      </div>

      <section className="panel">
        <h2>
          <Icon name="users" size={18} /> {t("rest.people")}
        </h2>
        <p className="muted">
          {t("rest.everybody_who_has_registered_what_they")}
        </p>
        <Link className="btn primary" href="/admin/users">
          <Icon name="search" size={16} /> {t("rest.open_the_people_table")}
        </Link>
      </section>

      <section className="panel">
        <h2>
          <Icon name="clock" size={18} /> {t("rest.what_just_happened")}
        </h2>
        {recent.length === 0 ? (
          <p className="muted">{t("rest.nothing_recorded_yet")}</p>
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
  const t = useT();
  const checks = [
    {
      label: t("le.schema"),
      text: t("rest.migration_n", { n: health.migration }),
      bad: health.migrations_failed > 0,
      badText: t("rest.migrations_failed_detail", { n: health.migrations_failed }),
    },
    {
      label: t("le.stripe_webhooks"),
      text: t("rest.all_processed"),
      bad: health.webhooks_unprocessed > 0,
      badText: t("rest.webhooks_unprocessed_detail", { n: health.webhooks_unprocessed }),
    },
    {
      label: t("rest.payments"),
      text: t("rest.none_failed_this_week"),
      bad: takings.failed_7d > 0,
      badText: t("rest.n_failed_this_week", { n: takings.failed_7d }),
    },
    {
      label: t("rest.assistant"),
      text: t("rest.no_errors_this_week"),
      bad: health.agent_failures_7d > 0,
      badText:
        t("rest.n_runs_failed", { n: health.agent_failures_7d }) +
        (health.agent_last_error ? t("rest.last_error", { error: health.agent_last_error }) : ""),
    },
  ];

  return (
    <section className="panel adm-health" aria-label={t("rest.what_might_be_wrong")}>
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
        {t("rest.health_foot", {
          codes: health.codes_pending,
          notifications: health.notifications_24h,
          unread: health.notifications_unread,
          db: bytes(health.database_bytes),
        })}
      </p>
    </section>
  );
}

function Figure({ label, value, growth }: { label: string; value: number; growth?: Growth }) {
  const t = useT();
  return (
    <div className="adm-figure">
      <strong>{value.toLocaleString()}</strong>
      <span className="muted">{label}</span>
      {growth && (
        <span className="adm-delta">
          {t("rest.growth_week_month", { week: growth.last_7d, month: growth.last_30d })}
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
  const t = useT();
  return (
    <p className={`adm-row${muted ? " muted" : ""}${bad ? " bad" : ""}`}>
      <span>{label}</span>
      <b>
        {text ?? value?.toLocaleString()}
        {of !== undefined && value !== undefined && of > 0 && (
          <em>{t("rest.of_total", { n: of.toLocaleString() })}</em>
        )}
      </b>
    </p>
  );
}
