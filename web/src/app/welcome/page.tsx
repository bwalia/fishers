"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api,
  getAccessToken,
  getStoredUser,
  markQuickStartDone,
  readErr,
  saveUser,
  SPORTS,
  type Club,
  type PublicUser,
  type RoleIntent,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { RoleChooser } from "@/components/RoleChooser";
import { ShareProfile } from "@/components/ShareProfile";

/// The one screen between signing up and the dashboard: what you play, and a
/// number your captain can reach you on. Both can be skipped.
///
/// Everything else a profile holds — standard, position, photo — waits for a
/// quiet moment. The first minute is for getting somebody into a club and a
/// match, not for filling in a form.
export default function WelcomePage() {
  const router = useRouter();
  const [user, setUser] = useState<PublicUser | null>(null);
  const [role, setRole] = useState<RoleIntent | null>(null);
  const [sports, setSports] = useState<string[]>([]);
  const [phone, setPhone] = useState("");
  const [step, setStep] = useState<"questions" | "share">("questions");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      router.replace("/login");
      return;
    }
    const adopt = (u: PublicUser) => {
      setUser(u);
      setRole((r) => r ?? u.role_intent ?? null);
      setPhone((p) => p || u.phone || "");
    };
    const stored = getStoredUser();
    if (stored) adopt(stored);
    api<PublicUser>("GET", "/me")
      .then((u) => {
        saveUser(u);
        adopt(u);
      })
      .catch(() => {});
  }, [router]);

  if (!user) return <main id="main" />;

  const asksRole = !user.role_intent;
  const asksPhone = !user.phone;
  const first = user.name.split(" ")[0];

  /// On to what gets them playing: a club to start, or a link to send.
  /// Somebody already in a club goes straight to it.
  const handOff = async (u: PublicUser) => {
    markQuickStartDone(u.id);
    const clubs = await api<Club[]>("GET", "/clubs").catch(() => [] as Club[]);
    if (clubs.length > 0) return router.push("/");
    if (u.role_intent === "secretary") return router.push("/clubs?new=1");
    if (u.role_intent === "player") return setStep("share");
    router.push("/");
  };

  const save = async (withAnswers: boolean) => {
    setBusy(true);
    setError(null);
    try {
      const body: Record<string, unknown> = {};
      if (role && role !== user.role_intent) body.role_intent = role;
      if (withAnswers) {
        body.sport_profiles = sports.map((sport) => ({ sport }));
        body.sports_played = sports;
        body.primary_sport = sports[0];
        if (phone.trim() && phone.trim() !== user.phone) body.phone = phone.trim();
      }
      let updated = user;
      if (Object.keys(body).length > 0) {
        updated = await api<PublicUser>("PATCH", "/me", body);
        saveUser(updated);
        setUser(updated);
      }
      await handOff(updated);
    } catch (err) {
      setError(readErr(err, "Could not save that"));
    } finally {
      setBusy(false);
    }
  };

  if (step === "share") {
    return (
      <main id="main" className="qs">
        <section className="panel qs-card" aria-labelledby="qs-share-title">
          <span className="qs-badge" aria-hidden="true"><Icon name="send" size={26} /></span>
          <h1 id="qs-share-title">You&apos;re in. Now get picked.</h1>
          <p className="muted">
            Send your profile link to your club&apos;s secretary or captain — WhatsApp is fine. They add
            you in one tap, and your fixtures show up here.
          </p>
          <ShareProfile userId={user.id} />
          <div className="qs-actions">
            <button className="btn primary" type="button" onClick={() => router.push("/")}>
              Go to my dashboard
            </button>
          </div>
        </section>
      </main>
    );
  }

  return (
    <main id="main" className="qs">
      <section className="panel qs-card" aria-labelledby="qs-title">
        <p className="gs-eyebrow"><Icon name="sparkle" size={14} /> Quick start</p>
        <h1 id="qs-title">Hi {first}</h1>
        <p className="muted">Two quick things and you&apos;re in. Everything else can wait until you have a minute.</p>

        {asksRole && (
          <fieldset className="qs-question">
            <legend>I&apos;m here to…</legend>
            <RoleChooser compact value={role} onPicked={(_, r) => setRole(r)} />
          </fieldset>
        )}

        <fieldset className="qs-question">
          <legend>What do you play?</legend>
          <div className="chip-list" role="group">
            {SPORTS.map((sport) => {
              const on = sports.includes(sport);
              return (
                <button
                  key={sport}
                  type="button"
                  className={`chip${on ? " on" : ""}`}
                  aria-pressed={on}
                  onClick={() => setSports((prev) => (on ? prev.filter((s) => s !== sport) : [...prev, sport]))}
                >
                  {sport}
                </button>
              );
            })}
          </div>
          {sports.length > 1 && (
            <p className="subtle">
              <span className="qs-cap">{sports[0]}</span> is your main sport — the first one you picked.
            </p>
          )}
        </fieldset>

        {asksPhone && (
          <label className="qs-question">
            <span className="qs-legend">Your mobile number</span>
            <input
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+44 7700 900123"
            />
            <span className="subtle">So your captain can reach you on match day. Only your clubs see it.</span>
          </label>
        )}

        {error && <p className="error">{error}</p>}

        <div className="qs-actions">
          <button className="btn ghost" type="button" disabled={busy} onClick={() => save(false)}>
            Skip for now
          </button>
          <button
            className="btn primary"
            type="button"
            disabled={busy || sports.length === 0}
            onClick={() => save(true)}
          >
            {busy ? "Saving…" : "Continue"}
          </button>
        </div>
      </section>
    </main>
  );
}
