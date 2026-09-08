"use client";

import { Icon } from "@/components/Icon";

/// The same left-hand side on both auth screens, so signing in and signing up
/// feel like one place rather than two.
export function AuthPitch() {
  return (
    <section className="auth-pitch">
      <h1>Score the game, not the paperwork</h1>
      <p>
        Ball-by-ball scoring that both captains can see, squads picked from who
        actually turned up, and a scorecard worth reading afterwards.
      </p>
      <ul className="auth-points">
        <li>
          <Icon name="bat" size={20} />
          <div>
            <strong>One tap a ball</strong>
            <span>The shot and where it went are asked after, and can be skipped.</span>
          </div>
        </li>
        <li>
          <Icon name="users" size={20} />
          <div>
            <strong>Both captains</strong>
            <span>Each names their own eleven, from their own phone.</span>
          </div>
        </li>
        <li>
          <Icon name="chart" size={20} />
          <div>
            <strong>Season figures that keep themselves</strong>
            <span>Batting, bowling and club results, written as matches finish.</span>
          </div>
        </li>
      </ul>
    </section>
  );
}
