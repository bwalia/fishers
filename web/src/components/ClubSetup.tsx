"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Icon, type IconName } from "@/components/Icon";
import { Spotlight } from "@/components/Spotlight";
import type { ClubMemberRow, Team, Venue } from "@/lib/api";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

type Step = {
  key: string;
  title: string;
  body: string;
  done: boolean;
  cta: string;
  icon: IconName;
  /// The element on the club page the spotlight rings.
  target: string;
  tour: { title: string; body: string };
};

/// A new club's next steps, on the club's own page, for its secretary.
///
/// Straight after the club is made (`welcome`) a dialog says what comes next
/// and hands over to a spotlight on the thing to press. After that a
/// checklist stays at the top until it is done or hidden — ticked off from
/// what exists, members and teams and grounds, never from what was clicked.
export function ClubSetup({
  clubId,
  clubName,
  members,
  teams,
  venues,
  welcome,
}: {
  clubId: string;
  clubName: string;
  members: ClubMemberRow[];
  teams: Team[];
  venues: Venue[];
  welcome: boolean;
}) {
  const t = useT();
  const hiddenKey = `fishers:club-setup:${clubId}:hidden`;
  // Hidden until storage is read, so a hidden checklist never flashes up.
  const [hidden, setHidden] = useState(true);
  // By key: the steps are rebuilt every render, so an object would go stale.
  const [spotKey, setSpotKey] = useState<string | null>(null);
  const dialog = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    try {
      setHidden(localStorage.getItem(hiddenKey) === "1");
    } catch {
      setHidden(false);
    }
  }, [hiddenKey]);

  useEffect(() => {
    if (welcome) dialog.current?.showModal();
  }, [welcome]);

  const steps: Step[] = [
    {
      key: "players",
      title: t("ld.add_your_players"),
      body: t("ld.by_email_or_mobile_number_or_from_a_pr"),
      done: members.length > 1,
      cta: "Add players",
      icon: "users",
      target: "add-players",
      tour: {
        title: t("ld.add_your_first_players"),
        body: t("fin.type_email_or_mobile", { brand: brand.name }),
      },
    },
    {
      key: "team",
      title: "Add a team",
      body: t("ld.a_1st_xi_a_sunday_side_the_juniors_eac"),
      done: teams.length > 0,
      cta: "Add a team",
      icon: "shield",
      target: "add-team",
      tour: { title: t("ld.name_your_first_team"), body: t("ld.give_it_a_name_pick_the_sport_and_pres") },
    },
    {
      key: "captain",
      title: "Name a captain",
      body: t("ld.captains_pick_the_side_and_run_the_sco"),
      done: members.some((m) => m.role === "team_captain" || m.is_captain),
      cta: "Choose a captain",
      icon: "trophy",
      target: "members-table",
      tour: {
        title: "Pick your captain",
        body: t("ld.set_a_member_s_role_to_captain_here_or"),
      },
    },
    {
      key: "ground",
      title: t("ld.add_your_ground"),
      body: t("ld.so_every_fixture_says_where_to_turn_up"),
      done: venues.length > 0,
      cta: "Add a ground",
      icon: "pin",
      target: "grounds",
      tour: { title: t("ld.where_do_you_play"), body: t("ld.add_your_ground_and_it_can_be_picked_w") },
    },
  ];

  const current = steps.find((s) => !s.done) ?? null;
  // Creating the club is the first step, and it is always done here.
  const total = steps.length + 1;
  const doneCount = steps.filter((s) => s.done).length + 1;

  const spot = steps.find((s) => s.key === spotKey) ?? null;

  // Stable, because the spotlight re-runs its scroll-into-view when it changes.
  const spotTarget = spot?.target;
  const closeSpot = useCallback(() => {
    setSpotKey(null);
    // Land them in the field the note was about, ready to type.
    if (spotTarget) {
      document.getElementById(spotTarget)?.querySelector<HTMLElement>("input, select, button")?.focus();
    }
  }, [spotTarget]);

  const hide = () => {
    try {
      localStorage.setItem(hiddenKey, "1");
    } catch {
      /* private window: it shows again next time */
    }
    setHidden(true);
  };

  return (
    <>
      <dialog ref={dialog} className="cw" aria-labelledby="cw-title">
        <span className="cw-badge" aria-hidden="true"><Icon name="check" size={30} /></span>
        <p className="gs-eyebrow">{t("rest.club_created")}</p>
        <h2 id="cw-title">{clubName} is ready</h2>
        <p className="muted">
          You&apos;re its secretary. Add your players and you can start a match straight away —
          teams, a captain and a ground can come later.
        </p>
        <ol className="cw-steps">
          <li className="done">
            <span className="cw-num"><Icon name="check" size={14} /></span>
            <strong>{t("rest.create_your_club")}</strong>
          </li>
          <li className="current">
            <span className="cw-num">2</span>
            <div>
              <strong>{steps[0].title}</strong>
              <p>{steps[0].body}</p>
            </div>
          </li>
          <li>
            <span className="cw-num">3</span>
            <div>
              <strong>{t("rest.start_your_first_match")}</strong>
            </div>
          </li>
        </ol>
        <div className="cw-actions">
          <button className="btn ghost" type="button" onClick={() => dialog.current?.close()}>
            I&apos;ll do it later
          </button>
          <button
            className="btn primary"
            type="button"
            autoFocus
            onClick={() => {
              dialog.current?.close();
              setSpotKey(steps[0].key);
            }}
          >
            <Icon name="users" size={16} /> {t("rest.add_players")}
          </button>
        </div>
      </dialog>

      {!hidden && current && (
        <section className="panel cs" aria-labelledby="cs-title">
          <div className="gs-head">
            <div>
              <p className="gs-eyebrow"><Icon name="sparkle" size={14} /> {t("rest.club_setup")}</p>
              <h2 id="cs-title">Get {clubName} ready for its first match</h2>
              <p className="muted">
                {doneCount} of {total} done — {total - doneCount} to go.
              </p>
            </div>
            <button className="btn ghost sm" type="button" onClick={hide}>{t("rest.hide")}</button>
          </div>
          <div
            className="gs-progress"
            role="progressbar"
            aria-valuenow={doneCount}
            aria-valuemin={0}
            aria-valuemax={total}
            aria-label={t("rest.club_setup_progress")}
          >
            <span style={{ width: `${Math.round((doneCount / total) * 100)}%` }} />
          </div>
          <ol className="cs-steps">
            {steps.map((s) => {
              const state = s.done ? "done" : s === current ? "current" : "upcoming";
              return (
                <li key={s.key} className={`cs-step ${state}`} aria-current={state === "current" ? "step" : undefined}>
                  <span className="cs-icon" aria-hidden="true">
                    <Icon name={s.done ? "check" : s.icon} size={18} />
                  </span>
                  <strong>
                    {s.title}
                    {s.done && <span className="sr-only"> — done</span>}
                  </strong>
                  <p>{s.body}</p>
                  {!s.done && (
                    <button
                      className={`btn sm${state === "current" ? " primary" : ""}`}
                      type="button"
                      onClick={() => setSpotKey(s.key)}
                    >
                      {s.cta}
                    </button>
                  )}
                </li>
              );
            })}
          </ol>
        </section>
      )}

      {spot && (
        <Spotlight
          targetId={spot.target}
          step={steps.indexOf(spot) + 2}
          of={total}
          title={spot.tour.title}
          body={spot.tour.body}
          onClose={closeSpot}
          onSkip={closeSpot}
        />
      )}
    </>
  );
}
