import 'package:flutter/foundation.dart';

import 'json.dart';

/// A port of `ios/Fishers/Models/SeasonStats.swift`.

/// Canonical ECB Play-Cricket public site. Fabricated `/website/...` sample
/// paths do not resolve — always open the real homepage.
abstract final class PlayCricketLinks {
  static const String homeString = 'https://play-cricket.com/';
  static final Uri home = Uri.parse(homeString);

  /// Returns the Play-Cricket home URL when [raw] points at play-cricket.com
  /// (including legacy broken deep links), otherwise parses [raw] as-is.
  static Uri? resolve(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final String lowered = raw.toLowerCase();
    if (lowered.contains('play-cricket.com') || lowered.contains('playcricket.com')) {
      return home;
    }
    return Uri.tryParse(raw);
  }
}

// MARK: - Play-Cricket player link

@immutable
class PlayCricketPlayerLink {
  const PlayCricketPlayerLink({
    required this.id,
    required this.userId,
    required this.playCricketPlayerId,
    this.clubId,
    this.playCricketSiteId,
    this.displayName,
    this.profileUrl,
    this.linkedAt,
    this.lastSyncedAt,
  });

  final String id;
  final String userId;
  final String? clubId;
  final String playCricketPlayerId;
  final String? playCricketSiteId;
  final String? displayName;
  final String? profileUrl;

  /// Kept optional and lossy so fractional timestamps never fail the whole
  /// payload.
  final DateTime? linkedAt;
  final DateTime? lastSyncedAt;

  factory PlayCricketPlayerLink.fromJson(JsonMap json) => PlayCricketPlayerLink(
    id: asUuid(json['id'], key: 'id'),
    userId: asUuid(json['user_id'], key: 'user_id'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    playCricketPlayerId: asString(json['play_cricket_player_id'], key: 'play_cricket_player_id'),
    playCricketSiteId: asStringOrNull(json['play_cricket_site_id'], key: 'play_cricket_site_id'),
    displayName: asStringOrNull(json['display_name'], key: 'display_name'),
    profileUrl: asStringOrNull(json['profile_url'], key: 'profile_url'),
    linkedAt: tryDate(json['linked_at']),
    lastSyncedAt: tryDate(json['last_synced_at']),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'user_id': userId,
    'club_id': clubId,
    'play_cricket_player_id': playCricketPlayerId,
    'play_cricket_site_id': playCricketSiteId,
    'display_name': displayName,
    'profile_url': profileUrl,
    'linked_at': encodeDateOrNull(linkedAt),
    'last_synced_at': encodeDateOrNull(lastSyncedAt),
  };

  Uri? get profileUri => PlayCricketLinks.resolve(profileUrl);

  @override
  bool operator ==(Object other) =>
      other is PlayCricketPlayerLink &&
      other.id == id &&
      other.userId == userId &&
      other.clubId == clubId &&
      other.playCricketPlayerId == playCricketPlayerId &&
      other.playCricketSiteId == playCricketSiteId &&
      other.displayName == displayName &&
      other.profileUrl == profileUrl &&
      other.linkedAt == linkedAt &&
      other.lastSyncedAt == lastSyncedAt;

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    clubId,
    playCricketPlayerId,
    playCricketSiteId,
    displayName,
    profileUrl,
    linkedAt,
    lastSyncedAt,
  );
}

// MARK: - Player season row

@immutable
class PlayerSeasonStats {
  const PlayerSeasonStats({
    required this.id,
    required this.userId,
    required this.sport,
    required this.seasonYear,
    required this.source,
    required this.matches,
    required this.runs,
    required this.wickets,
    required this.battingInnings,
    required this.notOuts,
    required this.ballsFaced,
    required this.fours,
    required this.sixes,
    required this.oversBowled,
    required this.bowlingRuns,
    required this.maidens,
    required this.catches,
    required this.stumpings,
    this.clubId,
    this.teamId,
    this.highScore,
    this.playerName,
    this.clubName,
    this.playCricketProfileUrl,
    this.playCricketPlayerId,
    this.battingAverage,
    this.bowlingAverage,
    this.strikeRate,
  });

  final String id;
  final String userId;
  final String? clubId;
  final String? teamId;
  final String sport;
  final int seasonYear;
  final String source;
  final int matches;
  final int runs;
  final int wickets;
  final int battingInnings;
  final int notOuts;
  final int ballsFaced;
  final int fours;
  final int sixes;
  final int? highScore;
  final double oversBowled;
  final int bowlingRuns;
  final int maidens;
  final int catches;
  final int stumpings;
  final String? playerName;
  final String? clubName;
  final String? playCricketProfileUrl;
  final String? playCricketPlayerId;
  final double? battingAverage;
  final double? bowlingAverage;
  final double? strikeRate;

  factory PlayerSeasonStats.fromJson(JsonMap json) => PlayerSeasonStats(
    id: asUuid(json['id'], key: 'id'),
    userId: asUuid(json['user_id'], key: 'user_id'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    teamId: asUuidOrNull(json['team_id'], key: 'team_id'),
    sport: asString(json['sport'], key: 'sport'),
    seasonYear: asInt(json['season_year'], key: 'season_year'),
    source: asString(json['source'], key: 'source'),
    matches: asInt(json['matches'], key: 'matches'),
    runs: asInt(json['runs'], key: 'runs'),
    wickets: asInt(json['wickets'], key: 'wickets'),
    battingInnings: asInt(json['batting_innings'], key: 'batting_innings'),
    notOuts: asInt(json['not_outs'], key: 'not_outs'),
    ballsFaced: asInt(json['balls_faced'], key: 'balls_faced'),
    fours: asInt(json['fours'], key: 'fours'),
    sixes: asInt(json['sixes'], key: 'sixes'),
    highScore: asIntOrNull(json['high_score'], key: 'high_score'),
    oversBowled: asDouble(json['overs_bowled'], key: 'overs_bowled'),
    bowlingRuns: asInt(json['bowling_runs'], key: 'bowling_runs'),
    maidens: asInt(json['maidens'], key: 'maidens'),
    catches: asInt(json['catches'], key: 'catches'),
    stumpings: asInt(json['stumpings'], key: 'stumpings'),
    playerName: asStringOrNull(json['player_name'], key: 'player_name'),
    clubName: asStringOrNull(json['club_name'], key: 'club_name'),
    playCricketProfileUrl: asStringOrNull(
      json['play_cricket_profile_url'],
      key: 'play_cricket_profile_url',
    ),
    playCricketPlayerId: asStringOrNull(
      json['play_cricket_player_id'],
      key: 'play_cricket_player_id',
    ),
    battingAverage: asDoubleOrNull(json['batting_average'], key: 'batting_average'),
    bowlingAverage: asDoubleOrNull(json['bowling_average'], key: 'bowling_average'),
    strikeRate: asDoubleOrNull(json['strike_rate'], key: 'strike_rate'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'user_id': userId,
    'club_id': clubId,
    'team_id': teamId,
    'sport': sport,
    'season_year': seasonYear,
    'source': source,
    'matches': matches,
    'runs': runs,
    'wickets': wickets,
    'batting_innings': battingInnings,
    'not_outs': notOuts,
    'balls_faced': ballsFaced,
    'fours': fours,
    'sixes': sixes,
    'high_score': highScore,
    'overs_bowled': oversBowled,
    'bowling_runs': bowlingRuns,
    'maidens': maidens,
    'catches': catches,
    'stumpings': stumpings,
    'player_name': playerName,
    'club_name': clubName,
    'play_cricket_profile_url': playCricketProfileUrl,
    'play_cricket_player_id': playCricketPlayerId,
    'batting_average': battingAverage,
    'bowling_average': bowlingAverage,
    'strike_rate': strikeRate,
  };

  Uri? get playCricketUrl => PlayCricketLinks.resolve(playCricketProfileUrl);

  @override
  bool operator ==(Object other) =>
      other is PlayerSeasonStats &&
      other.id == id &&
      other.userId == userId &&
      other.clubId == clubId &&
      other.teamId == teamId &&
      other.sport == sport &&
      other.seasonYear == seasonYear &&
      other.source == source &&
      other.matches == matches &&
      other.runs == runs &&
      other.wickets == wickets &&
      other.battingInnings == battingInnings &&
      other.notOuts == notOuts &&
      other.ballsFaced == ballsFaced &&
      other.fours == fours &&
      other.sixes == sixes &&
      other.highScore == highScore &&
      other.oversBowled == oversBowled &&
      other.bowlingRuns == bowlingRuns &&
      other.maidens == maidens &&
      other.catches == catches &&
      other.stumpings == stumpings &&
      other.playerName == playerName &&
      other.clubName == clubName &&
      other.playCricketProfileUrl == playCricketProfileUrl &&
      other.playCricketPlayerId == playCricketPlayerId &&
      other.battingAverage == battingAverage &&
      other.bowlingAverage == bowlingAverage &&
      other.strikeRate == strikeRate;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    userId,
    clubId,
    teamId,
    sport,
    seasonYear,
    source,
    matches,
    runs,
    wickets,
    battingInnings,
    notOuts,
    ballsFaced,
    fours,
    sixes,
    highScore,
    oversBowled,
    bowlingRuns,
    maidens,
    catches,
    stumpings,
    playerName,
    clubName,
    playCricketProfileUrl,
    playCricketPlayerId,
    battingAverage,
    bowlingAverage,
    strikeRate,
  ]);
}

// MARK: - Achievements

@immutable
class UserAchievement {
  const UserAchievement({
    required this.id,
    required this.userId,
    required this.achievementCode,
    required this.title,
    this.clubId,
    this.seasonYear,
    this.awardedAt,
    this.description,
    this.icon,
  });

  final String id;
  final String userId;
  final String achievementCode;
  final String? clubId;
  final int? seasonYear;
  final DateTime? awardedAt;
  final String title;
  final String? description;
  final String? icon;

  factory UserAchievement.fromJson(JsonMap json) => UserAchievement(
    id: asUuid(json['id'], key: 'id'),
    userId: asUuid(json['user_id'], key: 'user_id'),
    achievementCode: asString(json['achievement_code'], key: 'achievement_code'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    seasonYear: asIntOrNull(json['season_year'], key: 'season_year'),
    awardedAt: tryDate(json['awarded_at']),
    title: asString(json['title'], key: 'title'),
    description: asStringOrNull(json['description'], key: 'description'),
    icon: asStringOrNull(json['icon'], key: 'icon'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'user_id': userId,
    'achievement_code': achievementCode,
    'club_id': clubId,
    'season_year': seasonYear,
    'awarded_at': encodeDateOrNull(awardedAt),
    'title': title,
    'description': description,
    'icon': icon,
  };

  @override
  bool operator ==(Object other) =>
      other is UserAchievement &&
      other.id == id &&
      other.userId == userId &&
      other.achievementCode == achievementCode &&
      other.clubId == clubId &&
      other.seasonYear == seasonYear &&
      other.awardedAt == awardedAt &&
      other.title == title &&
      other.description == description &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    achievementCode,
    clubId,
    seasonYear,
    awardedAt,
    title,
    description,
    icon,
  );
}

@immutable
class MeStatsResponse {
  const MeStatsResponse({required this.links, required this.seasons, required this.achievements});

  final List<PlayCricketPlayerLink> links;
  final List<PlayerSeasonStats> seasons;
  final List<UserAchievement> achievements;

  factory MeStatsResponse.fromJson(JsonMap json) => MeStatsResponse(
    links: asList(
      json['links'],
      (Object? v) => PlayCricketPlayerLink.fromJson(asMap(v, key: 'links')),
    ),
    seasons: asList(
      json['seasons'],
      (Object? v) => PlayerSeasonStats.fromJson(asMap(v, key: 'seasons')),
    ),
    achievements: asList(
      json['achievements'],
      (Object? v) => UserAchievement.fromJson(asMap(v, key: 'achievements')),
    ),
  );

  JsonMap toJson() => <String, dynamic>{
    'links': links.map((PlayCricketPlayerLink l) => l.toJson()).toList(growable: false),
    'seasons': seasons.map((PlayerSeasonStats s) => s.toJson()).toList(growable: false),
    'achievements': achievements.map((UserAchievement a) => a.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is MeStatsResponse &&
      listEquals(other.links, links) &&
      listEquals(other.seasons, seasons) &&
      listEquals(other.achievements, achievements);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(links), Object.hashAll(seasons), Object.hashAll(achievements));
}

// MARK: - Club board

@immutable
class PlayCricketClubSite {
  const PlayCricketClubSite({
    required this.clubId,
    required this.siteId,
    this.siteName,
    this.publicUrl,
    this.lastSyncedAt,
  });

  final String clubId;
  final String siteId;
  final String? siteName;
  final String? publicUrl;
  final DateTime? lastSyncedAt;

  factory PlayCricketClubSite.fromJson(JsonMap json) => PlayCricketClubSite(
    clubId: asUuid(json['club_id'], key: 'club_id'),
    siteId: asString(json['site_id'], key: 'site_id'),
    siteName: asStringOrNull(json['site_name'], key: 'site_name'),
    publicUrl: asStringOrNull(json['public_url'], key: 'public_url'),
    lastSyncedAt: tryDate(json['last_synced_at']),
  );

  JsonMap toJson() => <String, dynamic>{
    'club_id': clubId,
    'site_id': siteId,
    'site_name': siteName,
    'public_url': publicUrl,
    'last_synced_at': encodeDateOrNull(lastSyncedAt),
  };

  Uri? get publicUri => PlayCricketLinks.resolve(publicUrl);

  @override
  bool operator ==(Object other) =>
      other is PlayCricketClubSite &&
      other.clubId == clubId &&
      other.siteId == siteId &&
      other.siteName == siteName &&
      other.publicUrl == publicUrl &&
      other.lastSyncedAt == lastSyncedAt;

  @override
  int get hashCode => Object.hash(clubId, siteId, siteName, publicUrl, lastSyncedAt);
}

@immutable
class ClubSeasonStats {
  const ClubSeasonStats({
    required this.id,
    required this.clubId,
    required this.seasonYear,
    required this.source,
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.noResults,
    required this.runsFor,
    required this.runsAgainst,
    required this.wicketsTaken,
    required this.wicketsLost,
  });

  final String id;
  final String clubId;
  final int seasonYear;
  final String source;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int noResults;
  final int runsFor;
  final int runsAgainst;
  final int wicketsTaken;
  final int wicketsLost;

  factory ClubSeasonStats.fromJson(JsonMap json) => ClubSeasonStats(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    seasonYear: asInt(json['season_year'], key: 'season_year'),
    source: asString(json['source'], key: 'source'),
    matchesPlayed: asInt(json['matches_played'], key: 'matches_played'),
    wins: asInt(json['wins'], key: 'wins'),
    losses: asInt(json['losses'], key: 'losses'),
    draws: asInt(json['draws'], key: 'draws'),
    noResults: asInt(json['no_results'], key: 'no_results'),
    runsFor: asInt(json['runs_for'], key: 'runs_for'),
    runsAgainst: asInt(json['runs_against'], key: 'runs_against'),
    wicketsTaken: asInt(json['wickets_taken'], key: 'wickets_taken'),
    wicketsLost: asInt(json['wickets_lost'], key: 'wickets_lost'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'season_year': seasonYear,
    'source': source,
    'matches_played': matchesPlayed,
    'wins': wins,
    'losses': losses,
    'draws': draws,
    'no_results': noResults,
    'runs_for': runsFor,
    'runs_against': runsAgainst,
    'wickets_taken': wicketsTaken,
    'wickets_lost': wicketsLost,
  };

  String get recordLabel => '$wins–$losses–$draws';

  @override
  bool operator ==(Object other) =>
      other is ClubSeasonStats &&
      other.id == id &&
      other.clubId == clubId &&
      other.seasonYear == seasonYear &&
      other.source == source &&
      other.matchesPlayed == matchesPlayed &&
      other.wins == wins &&
      other.losses == losses &&
      other.draws == draws &&
      other.noResults == noResults &&
      other.runsFor == runsFor &&
      other.runsAgainst == runsAgainst &&
      other.wicketsTaken == wicketsTaken &&
      other.wicketsLost == wicketsLost;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    clubId,
    seasonYear,
    source,
    matchesPlayed,
    wins,
    losses,
    draws,
    noResults,
    runsFor,
    runsAgainst,
    wicketsTaken,
    wicketsLost,
  ]);
}

@immutable
class ClubSeasonBoard {
  const ClubSeasonBoard({
    required this.club,
    required this.topBatters,
    required this.topBowlers,
    this.playCricket,
  });

  final ClubSeasonStats club;
  final PlayCricketClubSite? playCricket;
  final List<PlayerSeasonStats> topBatters;
  final List<PlayerSeasonStats> topBowlers;

  factory ClubSeasonBoard.fromJson(JsonMap json) => ClubSeasonBoard(
    club: ClubSeasonStats.fromJson(asMap(json['club'], key: 'club')),
    playCricket: json['play_cricket'] == null
        ? null
        : PlayCricketClubSite.fromJson(asMap(json['play_cricket'], key: 'play_cricket')),
    topBatters: asList(
      json['top_batters'],
      (Object? v) => PlayerSeasonStats.fromJson(asMap(v, key: 'top_batters')),
    ),
    topBowlers: asList(
      json['top_bowlers'],
      (Object? v) => PlayerSeasonStats.fromJson(asMap(v, key: 'top_bowlers')),
    ),
  );

  JsonMap toJson() => <String, dynamic>{
    'club': club.toJson(),
    'play_cricket': playCricket?.toJson(),
    'top_batters': topBatters.map((PlayerSeasonStats s) => s.toJson()).toList(growable: false),
    'top_bowlers': topBowlers.map((PlayerSeasonStats s) => s.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is ClubSeasonBoard &&
      other.club == club &&
      other.playCricket == playCricket &&
      listEquals(other.topBatters, topBatters) &&
      listEquals(other.topBowlers, topBowlers);

  @override
  int get hashCode =>
      Object.hash(club, playCricket, Object.hashAll(topBatters), Object.hashAll(topBowlers));
}
