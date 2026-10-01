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
import { useT } from "@/lib/i18n/provider";

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
  const t = useT();
  const role: RoleIntent = user.role_intent ?? "player";
  const [verification, setVerification] = useState<VerificationStatus | null>(null);
  const [teams, setTeams] = useState<Team[] | null>(null);
  const [members, setMembers] = useState<ClubMemberRow[] | null>(null);
  const [sharedOnce, setSharedOnce] = useState(false);
  const [tourOpen, setTourOpen] = useState(false);

  const ownClub = clubs.find((c) => c.owner_id === user.id) ?? null;
  // clubs.find() answers with a new object every render, so the effect below
  // depends on the id rather than the club: depending on the object would
  // refetch the teams and members on every render for ever.
  const ownClubId = ownClub?.id ?? null;

  useEffect(() => {
    setSharedOnce(read(sharedKey(user.id)) === "1");
    api<VerificationStatus>("GET", "/me/verification")
      .then(setVerification)
      .catch(() => setVerification(null));
  }, [user.id, user.email_verified, user.phone_verified]);

  useEffect(() => {
    if (!ownClubId) return;
    Promise.all([
      api<Team[]>("GET", `/clubs/${ownClubId}/teams`).catch(() => [] as Team[]),
      api<ClubMemberRow[]>("GET", `/clubs/${ownClubId}/members`).catch(() => [] as ClubMemberRow[]),
    ]).then(([t, m]) => {
      setTeams(t);
      setMembers(m);
    });
  }, [ownClubId]);

  const verified = !!(user.email_verified || user.phone_verified);
  // Only a step when the server asks for confirmation AND can send a code.
  const canVerify =
    !!verification?.enabled && (verification.email.available || verification.phone.available);

  const steps = useMemo<Step[]>(() => {
    const verify: Step[] = canVerify
      ? [
          {
            key: "verify",
            title: verification!.email.available ? t("le.confirm_your_email") : t("le.confirm_your_phone"),
            body: t("lb.proves_it_s_really_you_clubs_are_only"),
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
              title: t("lb.first_confirm_it_s_you"),
              body: t("lb.we_ve_sent_you_a_6_digit_code_type_it"),
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
          title: t("rest.start_your_club"),
          body: t("lb.its_name_and_sport_you_become_the_secr"),
          done: !!ownClub,
          cta: { label: t("rest.start_your_club"), href: "/clubs?new=1", icon: "plus" },
          tour: {
            title: t("lb.start_your_club_here"),
            body: t("lb.give_it_a_name_and_pick_the_sport_you"),
          },
        },
        {
          key: "team",
          title: t("lb.add_your_first_team"),
          body: t("lb.a_1st_xi_a_sunday_side_the_juniors_eac"),
          done: (teams?.length ?? 0) > 0,
          cta: { label: t("lb.add_a_team"), href: `${clubPage}#teams`, icon: "users" },
          tour: { title: t("lb.now_add_a_team"), body: t("lb.most_clubs_start_with_one_you_can_add") },
        },
        {
          key: "players",
          title: t("lb.invite_your_players"),
          body: t("lb.send_the_invite_link_to_your_club_s_wh"),
          done: (members?.length ?? 0) > 1,
          cta: { label: t("lb.invite_players"), href: `${clubPage}#members`, icon: "send" },
          tour: {
            title: t("lb.bring_your_players_in"),
            body: t("lb.an_invite_link_in_the_club_whatsapp_gr"),
          },
        },
        {
          key: "captain",
          title: t("lb.name_a_captain"),
          body: t("lb.give_one_member_the_captain_role_or_if"),
          done: (members ?? []).some((m) => m.role === "team_captain" || m.is_captain),
          cta: { label: t("lb.choose_a_captain"), href: `${clubPage}#members`, icon: "trophy" },
          tour: { title: t("lb.pick_your_captain"), body: t("lb.change_a_member_s_role_to_captain_you") },
        },
        {
          key: "fixture",
          title: t("lb.schedule_your_first_fixture"),
          body: t("lb.who_where_and_when_players_mark_themse"),
          done: eventsCount > 0,
          cta: { label: t("lb.schedule_a_match"), href: "/events?new=1", icon: "calendar" },
          tour: { title: t("lb.last_one_your_first_fixture"), body: t("lb.once_it_s_in_your_players_get_asked_if") },
        },
      ];
    }

    return [
      ...verify,
      {
        key: "share",
        title: t("lb.send_your_profile_to_your_club_secreta"),
        body: t("lb.they_open_your_link_and_invite_you_in"),
        done: sharedOnce || invitesCount > 0 || clubs.length > 0,
        inline: <ShareProfile userId={user.id} onShared={() => setSharedOnce(true)} />,
        tour: {
          title: t("lb.send_your_profile_to_your_secretary"),
          body: t("lb.get_your_link_and_drop_it_in_the_club"),
        },
      },
      {
        key: "join",
        title: t("lb.accept_your_club_s_invite"),
        body: t("lb.it_appears_at_the_top_of_this_page_bee"),
        done: clubs.length > 0,
        // Point at the invite itself once there is one; before that, at this
        // step — never at an empty space.
        target: invitesCount > 0 ? "pending-invites" : "gs-step-join",
        tour:
          invitesCount > 0
            ? { title: t("lb.your_invite_is_here"), body: t("lb.check_it_s_your_club_then_press_accept") }
            : {
                title: t("lb.watch_for_your_invite"),
                body: t("lb.when_your_secretary_invites_you_it_app"),
              },
      },
    ];
  }, [role, canVerify, verification, verified, ownClub, teams, members, eventsCount, user, sharedOnce, invitesCount, clubs.length, onUserChange, t]);

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
            <Icon name="sparkle" size={14} /> Getting started · {role === "secretary" ? t("lb.club_secretary") : "Player"}
          </p>
          <h2 id="gs-title">
            {role === "secretary" ? t("lb.let_s_set_up_your_club") : t("lb.let_s_get_you_into_your_club")}
          </h2>
          <p className="muted">
            {doneCount} of {steps.length} done — {steps.length - doneCount} to go.
          </p>
        </div>
        <button className="btn ghost sm" type="button" onClick={() => setTourOpen(true)}>
          <Icon name="help" size={16} /> {t("rest.show_me_around")}
        </button>
      </div>

      <div
        className="gs-progress"
        role="progressbar"
        aria-valuenow={doneCount}
        aria-valuemin={0}
        aria-valuemax={steps.length}
        aria-label={t("rest.setup_progress")}
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
          {t("rest.here_to_play_not_to_run_a_club")} <SwitchRole to="player" onUserChange={onUserChange} />
        </p>
      ) : (
        <p className="gs-switch subtle">
          {t("rest.running_a_club_instead")} <SwitchRole to="secretary" onUserChange={onUserChange} />
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
