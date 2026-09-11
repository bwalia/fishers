"use client";

import Link from "next/link";
import { type ReactNode, useCallback, useEffect, useMemo, useState } from "react";
import {
  api,
  saveUser,
  type Club,
  type ClubMemberRow,
  type PublicUser,
  type RoleIntent,
  type Team,
  type VerificationStatus,
} from "@/lib/api";
import { Icon, type IconName } from "@/components/Icon";
import { ShareProfile, sharedKey } from "@/components/ShareProfile";
import { Spotlight } from "@/components/Spotlight";
import { VerifyContact } from "@/components/VerifyContact";

type Step = {
  key: string;
  title: string;
  body: string;
  done: boolean;
  cta?: { label: string; href: string; icon: IconName };
  /// Rendered in place of a button when the step can be done right here.
  inline?: ReactNode;
  /// What the spotlight points at, when it is not this step's own button.
  target?: string;
  tour: { title: string; body: string };
};

const read = (k: string) => {
  try {
    return localStorage.getItem(k);
  } catch {
    return null;
  }
};
const write = (k: string, v: string) => {
  try {
    localStorage.setItem(k, v);
  } catch {
    /* private window: the tour just shows again */
  }
};

/// The first-run guide: the steps for the role somebody chose, in order, with
/// the next one spotlit the first time it comes up.
///
/// Each step is worked out from real state — a club that exists, a team with
/// a name, a member with the captain role — never from "they clicked the
/// button", so it cannot tick something off that did not happen.
export function GettingStarted({
  user,
  clubs,
  eventsCount,
  invitesCount,
  onUserChange,
}: {
  user: PublicUser;
  clubs: Club[];
  eventsCount: number;
  invitesCount: number;
  onUserChange: (u: PublicUser) => void;
}) {
  const role: RoleIntent = user.role_intent ?? "player";
  const [verification, setVerification] = useState<VerificationStatus | null>(null);
  const [teams, setTeams] = useState<Team[] | null>(null);
  const [members, setMembers] = useState<ClubMemberRow[] | null>(null);
  const [sharedOnce, setSharedOnce] = useState(false);
  const [tourOpen, setTourOpen] = useState(false);

  const ownClub = clubs.find((c) => c.owner_id === user.id) ?? null;

  useEffect(() => {
    setSharedOnce(read(sharedKey(user.id)) === "1");
    api<VerificationStatus>("GET", "/me/verification")
      .then(setVerification)
      .catch(() => setVerification(null));
  }, [user.id, user.email_verified, user.phone_verified]);

  useEffect(() => {
    if (!ownClub) return;
    Promise.all([
      api<Team[]>("GET", `/clubs/${ownClub.id}/teams`).catch(() => [] as Team[]),
      api<ClubMemberRow[]>("GET", `/clubs/${ownClub.id}/members`).catch(() => [] as ClubMemberRow[]),
    ]).then(([t, m]) => {
      setTeams(t);
      setMembers(m);
    });
  }, [ownClub?.id]);

  const verified = !!(user.email_verified || user.phone_verified);
  // Only a step when the server asks for confirmation AND can send a code.
  const canVerify =
    !!verification?.enabled && (verification.email.available || verification.phone.available);

  const steps = useMemo<Step[]>(() => {
    const verify: Step[] = canVerify
      ? [
          {
            key: "verify",
            title: `Confirm your ${verification!.email.available ? "email" : "phone number"}`,
            body: "Proves it's really you. Clubs are only started, and invites only accepted, by confirmed accounts.",
            done: verified,
            inline: (
              <VerifyContact
                status={verification!}
                compact
                onVerified={(u) => {
                  saveUser(u);
                  onUserChange(u);
                }}
              />
            ),
            tour: {
              title: "First, confirm it's you",
              body: "We've sent you a 6-digit code. Type it here — it takes a few seconds, and it keeps fake accounts out of your club.",
            },
          },
        ]
      : [];

    if (role === "secretary") {
      const clubPage = ownClub ? `/clubs/${ownClub.id}` : "/clubs";
      return [
        ...verify,
        {
          key: "club",
          title: "Start your club",
          body: "Its name and sport. You become the secretary — you run the teams, fixtures and who's in.",
          done: !!ownClub,
          cta: { label: "Start your club", href: "/clubs?new=1", icon: "plus" },
          tour: {
            title: "Start your club here",
            body: "Give it a name and pick the sport. You'll be its secretary — everything else hangs off the club.",
          },
        },
        {
          key: "team",
          title: "Add your first team",
          body: "A 1st XI, a Sunday side, the juniors — each team gets its own squad and fixtures.",
          done: (teams?.length ?? 0) > 0,
          cta: { label: "Add a team", href: `${clubPage}#teams`, icon: "users" },
          tour: { title: "Now add a team", body: "Most clubs start with one — you can add more any time." },
        },
        {
          key: "players",
          title: "Invite your players",
          body: "Send the invite link to your club's WhatsApp group, or add people by email or phone.",
          done: (members?.length ?? 0) > 1,
          cta: { label: "Invite players", href: `${clubPage}#members`, icon: "send" },
          tour: {
            title: "Bring your players in",
            body: "An invite link in the club WhatsApp group is the quickest way. Players who sent you their profile link can be invited straight from it.",
          },
        },
        {
          key: "captain",
          title: "Name a captain",
          body: "Give one member the captain role — they pick the sides and can run the scorebook.",
          done: (members ?? []).some((m) => m.role === "captain"),
          cta: { label: "Choose a captain", href: `${clubPage}#members`, icon: "trophy" },
          tour: { title: "Pick your captain", body: "Change a member's role to Captain. You can have one per team." },
        },
        {
          key: "fixture",
          title: "Schedule your first fixture",
          body: "Who, where and when. Players mark themselves available and the captain picks the side.",
          done: eventsCount > 0,
          cta: { label: "Schedule a match", href: "/events?new=1", icon: "calendar" },
          tour: { title: "Last one — your first fixture", body: "Once it's in, your players get asked if they can play." },
        },
      ];
    }

    return [
      ...verify,
      {
        key: "profile",
        title: "Complete your profile",
        body: "A photo, what you play and your position. It's what a captain sees on the team sheet.",
        done: !!user.profile_complete,
        cta: { label: "Complete your profile", href: "/profile", icon: "book" },
        tour: {
          title: "Set up your player profile",
          body: "Add a photo and what you play. Your secretary sees this when you send them your link.",
        },
      },
      {
        key: "share",
        title: "Send your profile to your club secretary",
        body: "They open your link and invite you in. No need for them to type your details.",
        done: sharedOnce || invitesCount > 0 || clubs.length > 0,
        inline: <ShareProfile userId={user.id} onShared={() => setSharedOnce(true)} />,
        tour: {
          title: "Send your profile to your secretary",
          body: "Get your link and drop it in the club's WhatsApp group or message your secretary directly.",
        },
      },
      {
        key: "join",
        title: "Accept your club's invite",
        body: "It appears at the top of this page. Been sent an invite link or QR code? Open it and you're in.",
        done: clubs.length > 0,
        // Point at the invite itself once there is one; before that, at this
        // step — never at an empty space.
        target: invitesCount > 0 ? "pending-invites" : "gs-step-join",
        tour:
          invitesCount > 0
            ? { title: "Your invite is here", body: "Check it's your club, then press Accept — you're straight in." }
            : {
                title: "Watch for your invite",
                body: "When your secretary invites you, it appears at the top of this page, ready to accept.",
              },
      },
    ];
  }, [role, canVerify, verification, verified, ownClub, teams, members, eventsCount, user, sharedOnce, invitesCount, clubs.length, onUserChange]);

  const current = steps.find((s) => !s.done) ?? null;
  // Seen-once per step AND per thing it points at: when an invite arrives on
  // the last step, "your invite is here" deserves its own first showing.
  const seenId = current ? `${current.key}:${current.target ?? "cta"}` : "";
  const doneCount = steps.filter((s) => s.done).length;
  const tourKey = (step: string) => `fishers:tour:${user.id}:${step}`;
  const skippedKey = `fishers:tour:${user.id}:skipped`;

  // The first time a step becomes the current one, point at it.
  useEffect(() => {
    if (!current || verification === null && canVerify) return;
    if (read(skippedKey) || read(tourKey(seenId))) return;
    const t = setTimeout(() => setTourOpen(true), 450);
    return () => clearTimeout(t);
  }, [seenId]); // eslint-disable-line react-hooks/exhaustive-deps

  const closeTour = useCallback(() => {
    if (seenId) write(tourKey(seenId), "1");
    setTourOpen(false);
  }, [seenId]); // eslint-disable-line react-hooks/exhaustive-deps

  const skipTour = useCallback(() => {
    write(skippedKey, "1");
    setTourOpen(false);
  }, [skippedKey]);

  if (!current) return null;

  const index = steps.indexOf(current);
  const pct = Math.round((doneCount / steps.length) * 100);

  return (
    <section className="panel gs" aria-labelledby="gs-title">
      <div className="gs-head">
        <div>
          <p className="gs-eyebrow">
            <Icon name="sparkle" size={14} /> Getting started · {role === "secretary" ? "Club secretary" : "Player"}
          </p>
          <h2 id="gs-title">
            {role === "secretary" ? "Let's set up your club" : "Let's get you into your club"}
          </h2>
          <p className="muted">
            {doneCount} of {steps.length} done — {steps.length - doneCount} to go.
          </p>
        </div>
        <button className="btn ghost sm" type="button" onClick={() => setTourOpen(true)}>
          <Icon name="help" size={16} /> Show me around
        </button>
      </div>

      <div
        className="gs-progress"
        role="progressbar"
        aria-valuenow={doneCount}
        aria-valuemin={0}
        aria-valuemax={steps.length}
        aria-label="Setup progress"
      >
        <span style={{ width: `${pct}%` }} />
      </div>

      <ol className="gs-steps">
        {steps.map((s, i) => {
          const state = s.done ? "done" : s === current ? "current" : "upcoming";
          return (
            <li
              key={s.key}
              id={`gs-step-${s.key}`}
              className={`gs-step ${state}`}
              aria-current={state === "current" ? "step" : undefined}
            >
              <span className="gs-marker" aria-hidden="true">
                {s.done ? <Icon name="check" size={16} /> : state === "upcoming" ? <Icon name="lock" size={14} /> : i + 1}
              </span>
              <div className="gs-body">
                <h3>
                  {s.title}
                  {s.done && <span className="sr-only"> — done</span>}
                </h3>
                {state === "current" && <p className="muted">{s.body}</p>}
                {state === "current" && (s.inline || s.cta) && (
                  <div className="gs-action" id={`gs-cta-${s.key}`}>
                    {s.inline ??
                      (s.cta && (
                        <Link className="btn primary" href={s.cta.href}>
                          <Icon name={s.cta.icon} size={16} /> {s.cta.label}
                        </Link>
                      ))}
                  </div>
                )}
              </div>
            </li>
          );
        })}
      </ol>

      {role === "secretary" ? (
        <p className="gs-switch subtle">
          Here to play, not to run a club? <SwitchRole to="player" onUserChange={onUserChange} />
        </p>
      ) : (
        <p className="gs-switch subtle">
          Running a club instead? <SwitchRole to="secretary" onUserChange={onUserChange} />
        </p>
      )}

      {tourOpen && (
        <Spotlight
          targetId={current.target ?? `gs-cta-${current.key}`}
          step={index + 1}
          of={steps.length}
          title={current.tour.title}
          body={current.tour.body}
          onClose={closeTour}
          onSkip={skipTour}
        />
      )}
    </section>
  );
}

function SwitchRole({ to, onUserChange }: { to: RoleIntent; onUserChange: (u: PublicUser) => void }) {
  return (
    <button
      type="button"
      className="linkish"
      onClick={async () => {
        const u = await api<PublicUser>("PATCH", "/me", { role_intent: to });
        saveUser(u);
        onUserChange(u);
      }}
    >
      Switch to the {to === "player" ? "player" : "secretary"} guide
    </button>
  );
}
