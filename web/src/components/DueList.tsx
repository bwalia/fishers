"use client";

/// The lines of "You owe": sessions, pass charges ("Monthly nets — December
/// 2026") and group fees ("Match balls, by Sun 6 Dec") all read the same way.
/// A line links to its session only when it has one. A covered line says why,
/// with a tick, and shows no amount: there is nothing to pay and nothing to
/// tap. `label` names somebody else's lines (a parent's junior), which read
/// "Covered by a pass" rather than "your pass".

import Link from "next/link";
import { money } from "@/lib/api";
import { shareStateTag, shareTag, shareWhen, type Share } from "@/lib/payments";
import { useT } from "@/lib/i18n/provider";

export function DueList({ shares, label }: { shares: Share[]; label?: string }) {
  const t = useT();
  if (shares.length === 0) return null;
  return (
    <ul className="pay-list due-list" aria-label={label}>
      {shares.map((s) => {
        const covered = s.state === "covered";
        const notes = [
          shareWhen(s, t),
          s.state === "waiting" ? t("pay.waiting_for_the_club") : "",
          s.state === "part_paid"
            ? t("pay.paid_of", { paid: money(s.paid_cents, s.currency), amount: money(s.amount_cents, s.currency) })
            : "",
        ].filter(Boolean);
        return (
          <li key={s.id} className={covered ? "is-covered" : undefined}>
            <div>
              {s.event_id ? <Link href={`/events/${s.event_id}#money`}>{s.title}</Link> : <strong>{s.title}</strong>}
              {notes.length > 0 && <div className="muted">{notes.join(" · ")}</div>}
            </div>
            <div className="pay-list-end">
              {!covered && <span className="num">{money(s.amount_cents, s.currency)}</span>}
              <span className={shareStateTag(s.state)}>{shareTag(s, t, !label)}</span>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
