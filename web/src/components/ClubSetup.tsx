"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Icon, type IconName } from "@/components/Icon";
import { Spotlight } from "@/components/Spotlight";
import type { ClubMemberRow, Team, Venue } from "@/lib/api";

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
      title: "Add your players",
      body: "By email or mobile number, or from a profile link a player sends you.",
      done: members.length > 1,
      cta: "Add players",
      icon: "users",
      target: "add-players",
      tour: {
        title: "Add your first players",
        body: "Type a player's email or mobile number. Already on Fishers? Press Add. Not yet? Press Invite instead and send them the link.",
      },
    },
    {
      key: "team",
      title: "Add a team",
      body: "A 1st XI, a Sunday side, the juniors — each keeps its own squad.",
      done: teams.length > 0,
      cta: "Add a team",
      icon: "shield",
      target: "add-team",
      tour: { title: "Name your first team", body: "Give it a name, pick the sport and press Create. You can add more any time." },
    },
    {
      key: "captain",
      title: "Name a captain",
      body: "Captains pick the side and run the scorebook on match day.",
      done: members.some((m) => m.role === "team_captain"),
      cta: "Choose a captain",
      icon: "trophy",
      target: "members-table",
      tour: { title: "Pick your captain", body: "Change a member's role to Captain here. Vice captains can help pick the side too." },
    },
    {
      key: "ground",
      title: "Add your ground",
      body: "So every fixture says where to turn up.",
      done: venues.length > 0,
      cta: "Add a ground",
      icon: "pin",
      target: "grounds",
      tour: { title: "Where do you play?", body: "Add your ground and it can be picked whenever a fixture is scheduled." },
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
        <p className="gs-eyebrow">Club created</p>
        <h2 id="cw-title">{clubName} is ready</h2>
        <p className="muted">
          You&apos;re its secretary. Bring your players in next — then a team, a captain and a
          ground, and you&apos;re set for your first fixture.
        </p>
        <ol className="cw-steps">
          <li className="done">
            <span className="cw-num"><Icon name="check" size={14} /></span>
            <strong>Create your club</strong>
          </li>
          {steps.map((s, i) => (
            <li key={s.key} className={i === 0 ? "current" : undefined}>
              <span className="cw-num">{i + 2}</span>
              <div>
                <strong>{s.title}</strong>
                {i === 0 && <p>{s.body}</p>}
              </div>
            </li>
          ))}
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
            <Icon name="users" size={16} /> Add players
          </button>
        </div>
      </dialog>

      {!hidden && current && (
        <section className="panel cs" aria-labelledby="cs-title">
          <div className="gs-head">
            <div>
              <p className="gs-eyebrow"><Icon name="sparkle" size={14} /> Club setup</p>
              <h2 id="cs-title">Get {clubName} ready for its first match</h2>
              <p className="muted">
                {doneCount} of {total} done — {total - doneCount} to go.
              </p>
            </div>
            <button className="btn ghost sm" type="button" onClick={hide}>Hide</button>
          </div>
          <div
            className="gs-progress"
            role="progressbar"
            aria-valuenow={doneCount}
            aria-valuemin={0}
            aria-valuemax={total}
            aria-label="Club setup progress"
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
