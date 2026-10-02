import Link from "next/link";
import { BrandMark } from "@/components/BrandMark";
import { Icon, type IconName } from "@/components/Icon";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// Signed-out `/`: brand, what Fishers does, and how a club gets going.
/// Everything named here is a screen that exists in the app.
export function Landing() {
  const t = useT();
  return (
    <main id="main" className="lp">
      <section className="lp-hero">
        <div className="lp-hero-inner">
          <div className="lp-hero-copy">
            <p className="lp-brand">
              <BrandMark size={40} />
              <span>{brand.name}</span>
            </p>
            <h1>{t("rest.run_the_club_score_the_match")}</h1>
            <p className="lp-lead">
              {t("rest.the_multi_sport_club_app_for_fixtures")}
            </p>
            <div className="lp-actions">
              <Link className="btn primary lp-btn" href="/register?as=secretary">
                <Icon name="plus" size={18} /> {t("rest.start_your_club")}
              </Link>
              <Link className="btn lp-btn" href="/register?as=player">
                {t("lp.i_play_for_a_club")}
              </Link>
            </div>
            <p className="lp-fine">
              {t("rest.google_email_or_mobile_already_in")} <Link href="/login">{t("lp.sign_in")}</Link>
            </p>
            <p className="lp-fine">
              {t("rest.rather_see_it_first")} <Link href="/tour">{t("rest.watch_the_20_minute_tour")}</Link>{" "}
              {t("lp.season_on_a_phone_tail")}
            </p>
          </div>
          <Scoreboard />
        </div>
      </section>

      <section className="lp-section lp-sports" aria-labelledby="lp-sports">
        <p className="lp-kicker">{t("rest.built_for_club_sport")}</p>
        <h2 id="lp-sports">{t("rest.cricket_first_room_for_the_rest_of_the")}</h2>
        <p className="lp-sub">
          {t("lp.strongest_on_cricket", { brand: brand.name })}
        </p>
      </section>

      <section className="lp-section" id="features" aria-labelledby="lp-features">
        <p className="lp-kicker">{t("rest.features")}</p>
        <h2 id="lp-features">{t("rest.everything_a_club_season_needs")}</h2>
        <p className="lp-sub">
          {t("rest.one_place_instead_of_spreadsheets_grou")}
        </p>
        <ul className="lp-feature-list">
          {FEATURES.map((f) => (
            <li className="lp-feature-row" key={f.title}>
              <span className="lp-feature-icon" aria-hidden="true">
                <Icon name={f.icon} size={22} />
              </span>
              <div>
                <h3>{t(f.title)}</h3>
                <p>{t(f.body)}</p>
              </div>
            </li>
          ))}
        </ul>
      </section>

      <section className="lp-section" aria-labelledby="lp-how">
        <p className="lp-kicker">{t("rest.how_it_works")}</p>
        <h2 id="lp-how">{t("rest.from_sign_up_to_first_ball")}</h2>
        <ol className="lp-steps">
          {STEPS.map((s, i) => (
            <li className="lp-step" key={s.title}>
              <span className="lp-step-num" aria-hidden="true">
                {String(i + 1).padStart(2, "0")}
              </span>
              <h3>{t(s.title)}</h3>
              <p>{t(s.body)}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="lp-section" aria-labelledby="lp-who">
        <p className="lp-kicker">{t("lp.who_its_for")}</p>
        <h2 id="lp-who">{t("rest.secretaries_captains_and_players")}</h2>
        <div className="lp-roles">
          {ROLES.map((r) => (
            <article className="lp-role" key={r.name}>
              <h3>
                <Icon name={r.icon} size={20} /> {t(r.name)}
              </h3>
              <p className="lp-role-line">{t(r.line)}</p>
              <ul>
                {r.gets.map((g) => (
                  <li key={g}>
                    <Icon name="check" size={16} /> {t(g)}
                  </li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      </section>

      <section className="lp-cta" aria-labelledby="lp-cta">
        <h2 id="lp-cta">{t("rest.ready_for_the_new_season")}</h2>
        <p>{t("rest.set_the_club_up_tonight_and_drop_the_i")}</p>
        <div className="lp-actions">
          <Link className="btn primary lp-btn" href="/register?as=secretary">
            <Icon name="plus" size={18} /> {t("rest.start_your_club")}
          </Link>
          <Link className="btn lp-btn" href="/register?as=player">
            {t("rest.join_as_a_player")}
          </Link>
        </div>
      </section>
    </main>
  );
}

function Scoreboard() {
  const t = useT();
  return (
    <div
      className="lp-visual"
      role="img"
      aria-label={t("fin.scoreboard_example", { brand: brand.name })}
    >
      <div className="lp-board" aria-hidden="true">
        <div className="lp-board-head">
          <span className="tag live">{t("lp.live")}</span>
          <span>{t("lp.t20_sunday_league")}</span>
        </div>
        <div className="lp-board-team done">
          <span>{brand.name} CC</span>
          <strong>168/6</strong>
          <em>{t("lp.n_ov", { n: 20 })}</em>
        </div>
        <div className="lp-board-team">
          <span>{t("rest.riverside_cc")}</span>
          <strong>142/4</strong>
          <em>{t("lp.n_ov", { n: "18.4" })}</em>
        </div>
        <p className="lp-board-need">{t("rest.riverside_need_27_runs_from_8_balls")}</p>
        <div className="lp-board-over">
          <span>{t("rest.this_over")}</span>
          <div>
            {["1", "4", "W", "6"].map((b, i) => (
              <i key={i} className={`lp-ball b${b}`}>
                {b}
              </i>
            ))}
            <i className="lp-ball next lp-ball-pulse" />
            <i className="lp-ball next" />
          </div>
        </div>
        <div className="lp-board-bats">
          <p>
            <span>{t("rest.a_khan")}</span>
            <b>58*</b>
            <em>41</em>
          </p>
          <p>
            <span>{t("rest.j_patel")}</span>
            <b>12*</b>
            <em>9</em>
          </p>
        </div>
      </div>
    </div>
  );
}

// `title` and `body` are dictionary keys: the list is built once at module
// scope and read in whichever language the visitor chose.
const FEATURES: { icon: IconName; title: Key; body: Key }[] = [
  {
    icon: "calendar",
    title: "lp.fixtures_recurring_sessions",
    body: "lp.league_games_nets_socials_schedule_onc",
  },
  {
    icon: "clock",
    title: "lp.availability_rsvp",
    body: "lp.ask_who_can_play_usual_days_are_set_on",
  },
  {
    icon: "users",
    title: "lp.team_selection",
    body: "lp.captains_pick_the_eleven_from_who_is_a",
  },
  {
    icon: "bat",
    title: "lp.live_ball_by_ball_scoring",
    body: "lp.one_tap_a_ball_on_the_phone_at_the_bou",
  },
  {
    icon: "share",
    title: "lp.shareable_live_scoreboard",
    body: "lp.send_a_link_on_whatsapp_or_messages_fa",
  },
  {
    icon: "chart",
    title: "cl.season_stats",
    body: "lp.batting_bowling_and_results_update_as",
  },
  {
    icon: "chat",
    title: "lp.club_chat_notifications",
    body: "lp.message_a_teammate_a_team_or_the_club",
  },
  {
    icon: "link",
    title: "lp.invites_qr_codes",
    body: "lp.drop_a_link_in_the_group_chat_or_show",
  },
  {
    icon: "trophy",
    title: "lp.tournaments_public_club_page",
    body: "lp.run_knockout_days_and_give_the_club_a",
  },
  {
    icon: "shop",
    title: "lp.fees_club_shop",
    body: "lp.match_fees_and_kit_or_food_orders_with",
  },
  {
    icon: "book",
    title: "lp.player_profiles",
    body: "lp.sport_level_positions_and_reliability",
  },
  {
    icon: "shield",
    title: "lp.roles_that_match_the_club",
    body: "lp.secretaries_run_the_club_captains_pick",
  },
];

const STEPS: { title: Key; body: Key }[] = [
  {
    title: "rest.start_your_club",
    body: "lp.name_it_pick_your_sports_and_you_are_t",
  },
  {
    title: "lp.bring_your_players_in",
    body: "lp.share_the_invite_link_or_add_people_by",
  },
  {
    title: "lp.play_score_repeat",
    body: "lp.schedule_a_fixture_let_the_captain_pic",
  },
];

const ROLES: { icon: IconName; name: Key; line: Key; gets: Key[] }[] = [
  {
    icon: "shield",
    name: "lp.secretaries",
    line: "lp.run_the_club_without_chasing_anyone",
    gets: ["lp.teams_members_and_roles", "lp.invite_links_and_qr_codes", "lp.fixtures_tournaments_and_a_club_page"],
  },
  {
    icon: "trophy",
    name: "lp.captains",
    line: "lp.know_your_side_before_the_toss",
    gets: ["lp.availability_at_a_glance", "lp.pick_and_publish_the_squad", "lp.run_the_scorebook_on_match_day"],
  },
  {
    icon: "ball",
    name: "lp.players",
    line: "lp.your_club_life_in_your_pocket",
    gets: ["lp.say_whether_you_can_play_in_one_tap", "lp.follow_matches_live", "lp.your_season_stats_and_profile"],
  },
];
