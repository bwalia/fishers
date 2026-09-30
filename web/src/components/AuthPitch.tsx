"use client";

import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

/// The same left-hand side on both auth screens, so signing in and signing up
/// feel like one place rather than two.
export function AuthPitch() {
  const t = useT();
  return (
    <section className="auth-pitch">
      <h1>{t("rest.score_the_game_not_the_paperwork")}</h1>
      <p>
        {t("rest.ball_by_ball_scoring_that_both_captain")}
      </p>
      <ul className="auth-points">
        <li>
          <Icon name="bat" size={20} />
          <div>
            <strong>{t("rest.one_tap_a_ball")}</strong>
            <span>{t("rest.the_shot_and_where_it_went_are_asked_a")}</span>
          </div>
        </li>
        <li>
          <Icon name="users" size={20} />
          <div>
            <strong>{t("rest.both_captains")}</strong>
            <span>{t("rest.each_names_their_own_eleven_from_their")}</span>
          </div>
        </li>
        <li>
          <Icon name="chart" size={20} />
          <div>
            <strong>{t("rest.season_figures_that_keep_themselves")}</strong>
            <span>{t("rest.batting_bowling_and_club_results_writt")}</span>
          </div>
        </li>
      </ul>
    </section>
  );
}
