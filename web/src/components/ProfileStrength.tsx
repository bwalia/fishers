"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { PublicUser } from "@/lib/api";
import { enablePush, pushState, type PushState } from "@/lib/push";
import { useT } from "@/lib/i18n/provider";

/// "Your profile is 35% complete" — the few things worth adding next, a way
/// to add them, and a way to be reminded instead. Gone at 100%.
///
/// The reminder itself is sent by the server a day after signing up and once
/// more a few days later; it lands in the bell either way. "Remind me" only
/// turns on push for this browser, so it can reach them with the tab closed —
/// and it asks the browser only when pressed.
export function ProfileStrength({ user, onProfilePage = false }: { user: PublicUser; onProfilePage?: boolean }) {
  const t = useT();
  const strength = user.profile_strength;
  const [push, setPush] = useState<PushState | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!onProfilePage) pushState().then(setPush, () => setPush("unsupported"));
  }, [onProfilePage]);

  if (!strength || strength.percent >= 100) return null;

  return (
    <section className="panel strength" aria-labelledby="strength-title">
      <div
        className="strength-ring"
        role="img"
        aria-label={t("le.profile_percent_complete", { n: strength.percent })}
        style={{ ["--pct" as string]: `${strength.percent}%` }}
      >
        <span>{strength.percent}%</span>
      </div>
      <div className="strength-body">
        <h2 id="strength-title">{t("fin.profile_pct_complete", { percent: strength.percent })}</h2>
        <p className="muted">{strength.next_up} so captains and clubs can see who they&apos;re picking.</p>
        <div className="strength-actions">
          {!onProfilePage && (
            <Link className="btn primary sm" href="/profile">
              {t("rest.complete_profile")}
            </Link>
          )}
          {push === "off" && (
            <button
              className="btn sm"
              type="button"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                setPush(await enablePush().catch(() => "denied" as PushState));
                setBusy(false);
              }}
            >
              {t("rest.remind_me_later")}
            </button>
          )}
          {push === "on" && <span className="subtle">We&apos;ll remind you if it&apos;s still not done.</span>}
        </div>
      </div>
    </section>
  );
}
