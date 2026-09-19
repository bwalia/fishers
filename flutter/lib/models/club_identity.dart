import 'package:flutter/foundation.dart';

import 'json.dart';

/// A port of `ios/Fishers/Models/ClubIdentity.swift`.

/// A club or team as its QR code identifies it.
///
/// Deliberately thin: a scanned code tells you who you are playing and nothing
/// else — no roster, no fixtures, no contact details.
@immutable
class ClubIdentity {
  const ClubIdentity({
    required this.id,
    required this.name,
    required this.qrToken,
    required this.kind,
    required this.clubId,
    required this.clubName,
    this.sport,
  });

  final String id;
  final String name;
  final String qrToken;

  /// `club` or `team`.
  final String kind;
  final String clubId;
  final String clubName;
  final String? sport;

  factory ClubIdentity.fromJson(JsonMap json) => ClubIdentity(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    qrToken: asString(json['qr_token'], key: 'qr_token'),
    kind: asString(json['kind'], key: 'kind'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    clubName: asString(json['club_name'], key: 'club_name'),
    sport: asStringOrNull(json['sport'], key: 'sport'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'qr_token': qrToken,
    'kind': kind,
    'club_id': clubId,
    'club_name': clubName,
    'sport': sport,
  };

  bool get isTeam => kind == 'team';

  /// "Hemel Hempstead CC — 2nd XI" when it is a team, just the club otherwise.
  String get displayName => isTeam && clubName != name ? '$clubName — $name' : name;

  @override
  bool operator ==(Object other) =>
      other is ClubIdentity &&
      other.id == id &&
      other.name == name &&
      other.qrToken == qrToken &&
      other.kind == kind &&
      other.clubId == clubId &&
      other.clubName == clubName &&
      other.sport == sport;

  @override
  int get hashCode => Object.hash(id, name, qrToken, kind, clubId, clubName, sport);
}

/// A club's own code, with the string that goes into the image.
///
/// The identity is decoded from the *same* object, not a nested one — iOS
/// writes `ClubIdentity(from: decoder)` beside its own keyed container.
@immutable
class ClubQrCode {
  const ClubQrCode({required this.identity, required this.payload});

  final ClubIdentity identity;
  final String payload;

  factory ClubQrCode.fromJson(JsonMap json) => ClubQrCode(
    identity: ClubIdentity.fromJson(json),
    payload: asString(json['payload'], key: 'payload'),
  );

  JsonMap toJson() => <String, dynamic>{...identity.toJson(), 'payload': payload};

  @override
  bool operator ==(Object other) =>
      other is ClubQrCode && other.identity == identity && other.payload == payload;

  @override
  int get hashCode => Object.hash(identity, payload);
}

/// An umpire or scorer appointed to a match. Either may control the scoring.
@immutable
class MatchOfficialRow {
  const MatchOfficialRow({required this.userId, required this.name, required this.role});

  final String userId;
  final String name;

  /// `umpire` or `scorer`.
  final String role;

  String get id => userId;

  factory MatchOfficialRow.fromJson(JsonMap json) => MatchOfficialRow(
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asString(json['name'], key: 'name'),
    role: asString(json['role'], key: 'role'),
  );

  JsonMap toJson() => <String, dynamic>{'user_id': userId, 'name': name, 'role': role};

  bool get isUmpire => role == 'umpire';

  String get label => isUmpire ? 'Umpire' : 'Scorer';

  @override
  bool operator ==(Object other) =>
      other is MatchOfficialRow &&
      other.userId == userId &&
      other.name == name &&
      other.role == role;

  @override
  int get hashCode => Object.hash(userId, name, role);
}

/// One change of hands in the scoring book.
@immutable
class ScorerHandover {
  const ScorerHandover({
    required this.toName,
    required this.reason,
    required this.actedByName,
    required this.createdAt,
    this.fromName,
  });

  final String? fromName;
  final String toName;

  /// `handover` · `override` · `claim`
  final String reason;
  final String actedByName;
  final DateTime createdAt;

  String get id => '${createdAt.millisecondsSinceEpoch / 1000}-$toName';

  factory ScorerHandover.fromJson(JsonMap json) => ScorerHandover(
    fromName: asStringOrNull(json['from_name'], key: 'from_name'),
    toName: asString(json['to_name'], key: 'to_name'),
    reason: asString(json['reason'], key: 'reason'),
    actedByName: asString(json['acted_by_name'], key: 'acted_by_name'),
    createdAt: asDate(json['created_at'], key: 'created_at'),
  );

  JsonMap toJson() => <String, dynamic>{
    'from_name': fromName,
    'to_name': toName,
    'reason': reason,
    'acted_by_name': actedByName,
    'created_at': encodeDate(createdAt),
  };

  /// "Ravi handed the book to Sam", or the blunter version.
  String get summary => switch (reason) {
    'override' => '$actedByName took the book${fromName == null ? "" : " from $fromName"}',
    'claim' => '$toName picked up the book',
    _ => '${fromName ?? "Someone"} handed the book to $toName',
  };

  bool get isOverride => reason == 'override';

  @override
  bool operator ==(Object other) =>
      other is ScorerHandover &&
      other.fromName == fromName &&
      other.toName == toName &&
      other.reason == reason &&
      other.actedByName == actedByName &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(fromName, toName, reason, actedByName, createdAt);
}

/// What the API's commentary endpoint replies with.
///
/// `line` is optional on purpose: no model configured, or one that contradicted
/// the ball and was thrown away, both come back as nothing — and the caller
/// keeps the line the app already wrote from the log.
@immutable
class BallCommentary {
  const BallCommentary({this.line, this.model});

  final String? line;
  final String? model;

  factory BallCommentary.fromJson(JsonMap json) => BallCommentary(
    line: asStringOrNull(json['line'], key: 'line'),
    model: asStringOrNull(json['model'], key: 'model'),
  );

  JsonMap toJson() => <String, dynamic>{'line': line, 'model': model};

  @override
  bool operator ==(Object other) =>
      other is BallCommentary && other.line == line && other.model == model;

  @override
  int get hashCode => Object.hash(line, model);
}

/// One name a captain may put on the sheet, and where they stand for this
/// fixture: picked, a reserve, available, or just a club member.
@immutable
class SquadPlayer {
  const SquadPlayer({
    required this.id,
    required this.name,
    required this.standing,
    required this.batsLeft,
    this.isCaptain,
  });

  final String id;
  final String name;
  final String standing;
  final bool batsLeft;

  /// Captains this side, so the sheet can start with them marked.
  final bool? isCaptain;

  factory SquadPlayer.fromJson(JsonMap json) => SquadPlayer(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    standing: asString(json['standing'], key: 'standing'),
    batsLeft: asBool(json['bats_left'], key: 'bats_left'),
    isCaptain: asBoolOrNull(json['is_captain'], key: 'is_captain'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'standing': standing,
    'bats_left': batsLeft,
    'is_captain': isCaptain,
  };

  String get standingLabel => switch (standing) {
    'selected' => 'picked',
    'reserve' => 'reserve',
    'available' => 'available',
    'unavailable' => 'said no',
    _ => 'member',
  };

  @override
  bool operator ==(Object other) =>
      other is SquadPlayer &&
      other.id == id &&
      other.name == name &&
      other.standing == standing &&
      other.batsLeft == batsLeft &&
      other.isCaptain == isCaptain;

  @override
  int get hashCode => Object.hash(id, name, standing, batsLeft, isCaptain);
}

@immutable
class SideSquad {
  const SideSquad({
    required this.side,
    required this.teamName,
    required this.canPick,
    required this.submitted,
    required this.players,
    this.clubId,
  });

  final String side;
  final String teamName;

  /// Null when this side is not a club in Fishers — the scorer names them.
  final String? clubId;
  final bool canPick;
  final bool submitted;
  final List<SquadPlayer> players;

  factory SideSquad.fromJson(JsonMap json) => SideSquad(
    side: asString(json['side'], key: 'side'),
    teamName: asString(json['team_name'], key: 'team_name'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    canPick: asBool(json['can_pick'], key: 'can_pick'),
    submitted: asBool(json['submitted'], key: 'submitted'),
    players: asList(json['players'], (Object? v) => SquadPlayer.fromJson(asMap(v, key: 'players'))),
  );

  JsonMap toJson() => <String, dynamic>{
    'side': side,
    'team_name': teamName,
    'club_id': clubId,
    'can_pick': canPick,
    'submitted': submitted,
    'players': players.map((SquadPlayer p) => p.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is SideSquad &&
      other.side == side &&
      other.teamName == teamName &&
      other.clubId == clubId &&
      other.canPick == canPick &&
      other.submitted == submitted &&
      listEquals(other.players, players);

  @override
  int get hashCode =>
      Object.hash(side, teamName, clubId, canPick, submitted, Object.hashAll(players));
}

@immutable
class MatchSquads {
  const MatchSquads({required this.home, required this.away});

  final SideSquad home;
  final SideSquad away;

  factory MatchSquads.fromJson(JsonMap json) => MatchSquads(
    home: SideSquad.fromJson(asMap(json['home'], key: 'home')),
    away: SideSquad.fromJson(asMap(json['away'], key: 'away')),
  );

  JsonMap toJson() => <String, dynamic>{'home': home.toJson(), 'away': away.toJson()};

  @override
  bool operator ==(Object other) =>
      other is MatchSquads && other.home == home && other.away == away;

  @override
  int get hashCode => Object.hash(home, away);
}
