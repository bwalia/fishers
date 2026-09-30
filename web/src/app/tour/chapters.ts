import type { Key } from "@/lib/i18n/en";

// Generated from the film's own index by scripts/tour-page-data.py, so every timestamp
// here is the video's arithmetic rather than a second copy of it that can drift.
//
//   ./scripts/cut-tour-video.sh && ./scripts/tour-page-data.py

/// `text` is a dictionary key, like the chapter titles.
export type TourBeat = { at: number; stamp: string; text: Key };
export type TourChapter = {
  number: number;
  /// Dictionary keys — the film's chapter list is built once and read in
  /// whichever language the viewer chose.
  title: Key;
  subtitle: Key;
  at: number;
  stamp: string;
  beats: TourBeat[];
};

export const TOUR_VIDEO_ID = "AzYtyFYpedM";
export const TOUR_DURATION = "20:45";
export const TOUR_FOOTER = "lb.recorded_on_the_ios_simulator_against";

export const TOUR_CHAPTERS: TourChapter[] = [
  {
    number: 1,
    title: "lb.a_player_joins_a_club",
    subtitle: "lb.signing_up_confirming_and_being_picked",
    at: 5,
    stamp: "0:05",
    beats: [
      { at: 11, stamp: "0:11", text: "tour.opening" },
      { at: 46, stamp: "0:46", text: "tour.signing_up_asks_one_thing_first_whethe" },
      { at: 73, stamp: "1:13", text: "lb.the_quick_start_is_a_sport_and_a_mobil" },
      { at: 85, stamp: "1:25", text: "lb.new_players_are_not_searched_for_they" },
      { at: 98, stamp: "1:38", text: "lb.home_before_a_club_the_profile_is_part" },
      { at: 119, stamp: "1:59", text: "lb.a_club_is_somebody_s_real_membership_l" },
      { at: 143, stamp: "2:23", text: "tour.the_secretary_sends_the_invite_from_th" },
      { at: 156, stamp: "2:36", text: "lb.accepted_and_the_club_s_season_is_thei" },
      { at: 164, stamp: "2:44", text: "lb.the_profile_keeps_a_score_of_itself_wh" },
      { at: 178, stamp: "2:58", text: "lb.a_cricketer_s_profile_where_they_bat_w" },
    ],
  },
  {
    number: 2,
    title: "lb.can_you_play_on_saturday",
    subtitle: "lb.availability_from_both_ends",
    at: 187,
    stamp: "3:07",
    beats: [
      { at: 197, stamp: "3:17", text: "lb.the_fixtures_tab_is_every_fixture_of_e" },
      { at: 208, stamp: "3:28", text: "tour.three_taps_available_maybe_can_t_play" },
      { at: 220, stamp: "3:40", text: "lb.it_says_what_you_said_and_it_can_be_ch" },
      { at: 231, stamp: "3:51", text: "lb.the_calendar_is_the_other_way_round_ma" },
      { at: 246, stamp: "4:06", text: "lb.a_weekend_away_marked_once_rather_than" },
      { at: 253, stamp: "4:13", text: "lb.and_the_days_you_usually_play_so_the_s" },
      { at: 271, stamp: "4:31", text: "lb.inside_a_fixture_where_when_the_match" },
    ],
  },
  {
    number: 3,
    title: "ev.the_captain_picks_the_side",
    subtitle: "lb.availability_reliability_and_who_has_s",
    at: 279,
    stamp: "4:39",
    beats: [
      { at: 318, stamp: "5:18", text: "lb.the_captain_s_selection_board_for_satu" },
      { at: 328, stamp: "5:28", text: "lb.beside_each_name_what_they_said_what_t" },
      { at: 340, stamp: "5:40", text: "lb.the_assistant_can_suggest_a_side_from" },
      { at: 354, stamp: "5:54", text: "lb.eleven_picked_and_two_down_as_reserves" },
      { at: 362, stamp: "6:02", text: "lb.publishing_tells_everybody_at_once" },
      { at: 377, stamp: "6:17", text: "lb.the_squad_lands_in_the_club_chat_where" },
    ],
  },
  {
    number: 4,
    title: "lb.a_t20_ball_by_ball",
    subtitle: "lb.twenty_overs_a_side_scored_on_the_phon",
    at: 412,
    stamp: "6:52",
    beats: [
      { at: 427, stamp: "7:07", text: "lb.tonight_s_fixture_a_floodlit_t20_twent" },
      { at: 439, stamp: "7:19", text: "lb.before_a_ball_the_terms_both_captains" },
      { at: 461, stamp: "7:41", text: "lb.one_captain_proposes_and_the_other_agr" },
      { at: 475, stamp: "7:55", text: "lb.the_toss_recorded_before_the_team_shee" },
      { at: 538, stamp: "8:58", text: "lb.the_team_sheet_is_picked_from_the_club" },
      { at: 608, stamp: "10:08", text: "lb.openers_and_the_bowler_to_start_from_h" },
      { at: 635, stamp: "10:35", text: "lb.one_tap_a_ball_the_score_the_two_batte" },
      { at: 664, stamp: "11:04", text: "lb.a_boundary_asks_where_it_went_the_fiel" },
      { at: 673, stamp: "11:13", text: "lb.the_powerplay_is_on_the_screen_while_i" },
      { at: 700, stamp: "11:40", text: "lb.extras_are_the_arithmetic_the_app_does" },
      { at: 742, stamp: "12:22", text: "lb.a_wicket_takes_the_bowler_s_name_the_f" },
      { at: 765, stamp: "12:45", text: "lb.a_no_ball_sets_a_free_hit_while_it_sta" },
      { at: 792, stamp: "13:12", text: "tour.nobody_bowls_two_overs_in_a_row_and_no" },
      { at: 837, stamp: "13:57", text: "lb.twenty_overs_bowled_the_innings_closes" },
      { at: 852, stamp: "14:12", text: "tour.the_chase_with_the_target_the_rate_it" },
      { at: 921, stamp: "15:21", text: "lb.last_over_and_the_arithmetic_every_fie" },
      { at: 948, stamp: "15:48", text: "lb.the_result_from_the_log_rather_than_fr" },
      { at: 960, stamp: "16:00", text: "lb.player_of_the_match_and_the_game_is_fi" },
      { at: 970, stamp: "16:10", text: "lb.the_full_card_every_batter_every_bowle" },
    ],
  },
  {
    number: 5,
    title: "lb.the_rest_of_the_cricket",
    subtitle: "lb.the_card_the_wheel_the_season_and_the",
    at: 982,
    stamp: "16:22",
    beats: [
      { at: 998, stamp: "16:38", text: "lb.every_match_the_club_has_played_or_is" },
      { at: 1007, stamp: "16:47", text: "lb.a_finished_league_match_from_earlier_i" },
      { at: 1023, stamp: "17:03", text: "tour.the_wagon_wheel_is_built_from_the_same" },
      { at: 1036, stamp: "17:16", text: "lb.and_a_commentary_written_from_the_log" },
      { at: 1055, stamp: "17:35", text: "lb.the_2nd_xi_are_playing_at_the_same_tim" },
      { at: 1095, stamp: "18:15", text: "lb.what_else_the_book_can_do_correct_a_ba" },
      { at: 1110, stamp: "18:30", text: "tour.scorers_get_it_wrong_three_balls_back" },
      { at: 1128, stamp: "18:48", text: "lb.one_person_scores_at_a_time_the_book_m" },
      { at: 1156, stamp: "19:16", text: "tour.the_club_s_season_folded_up_out_of_tho" },
      { at: 1175, stamp: "19:35", text: "tour.the_club_s_public_page_record_top_play" },
      { at: 1195, stamp: "19:55", text: "lb.every_club_and_team_has_a_qr_code_at_t" },
      { at: 1219, stamp: "20:19", text: "lb.a_player_s_own_figures_and_the_record" },
      { at: 1230, stamp: "20:30", text: "lb.all_of_it_lands_back_on_home_what_is_i" },
    ],
  },
];
