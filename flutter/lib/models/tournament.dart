import 'package:flutter/foundation.dart';

import 'json.dart';

/// A port of `ios/Fishers/Models/Tournament.swift`.

enum TournamentFormat {
  none('none'),
  roundRobin('round_robin'),
  groupsKnockout('groups_knockout'),
  knockout('knockout'),
  ladder('ladder');

  const TournamentFormat(this.wire);

  final String wire;

  String get label => switch (this) {
    TournamentFormat.none => 'No structure',
    TournamentFormat.roundRobin => 'Round robin',
    TournamentFormat.groupsKnockout => 'Groups + knockout',
    TournamentFormat.knockout => 'Straight knockout',
    TournamentFormat.ladder => 'Ladder',
  };

  static TournamentFormat fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(TournamentFormat.values, raw, (TournamentFormat f) => f.wire, key: key);

  String toJson() => wire;
}

@immutable
class FixtureBlock {
  const FixtureBlock({
    required this.id,
    required this.clubId,
    required this.name,
    required this.kind,
    this.teamId,
    this.startsOn,
    this.endsOn,
  });

  final String id;
  final String clubId;
  final String? teamId;
  final String name;

  /// `block` | `tour` | `tournament` | `season`
  final String kind;

  /// Calendar days, `YYYY-MM-DD` — not instants.
  final String? startsOn;
  final String? endsOn;

  factory FixtureBlock.fromJson(JsonMap json) => FixtureBlock(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    teamId: asUuidOrNull(json['team_id'], key: 'team_id'),
    name: asString(json['name'], key: 'name'),
    kind: asString(json['kind'], key: 'kind'),
    startsOn: asStringOrNull(json['starts_on'], key: 'starts_on'),
    endsOn: asStringOrNull(json['ends_on'], key: 'ends_on'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'team_id': teamId,
    'name': name,
    'kind': kind,
    'starts_on': startsOn,
    'ends_on': endsOn,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureBlock &&
      other.id == id &&
      other.clubId == clubId &&
      other.teamId == teamId &&
      other.name == name &&
      other.kind == kind &&
      other.startsOn == startsOn &&
      other.endsOn == endsOn;

  @override
  int get hashCode => Object.hash(id, clubId, teamId, name, kind, startsOn, endsOn);
}

@immutable
class TournamentEntrant {
  const TournamentEntrant({
    required this.id,
    required this.blockId,
    required this.name,
    required this.withdrawn,
    this.seed,
    this.groupLabel,
    this.contactName,
    this.contactEmail,
  });

  final String id;
  final String blockId;
  final String name;
  final int? seed;
  final String? groupLabel;
  final String? contactName;
  final String? contactEmail;
  final bool withdrawn;

  factory TournamentEntrant.fromJson(JsonMap json) => TournamentEntrant(
    id: asUuid(json['id'], key: 'id'),
    blockId: asUuid(json['block_id'], key: 'block_id'),
    name: asString(json['name'], key: 'name'),
    seed: asIntOrNull(json['seed'], key: 'seed'),
    groupLabel: asStringOrNull(json['group_label'], key: 'group_label'),
    contactName: asStringOrNull(json['contact_name'], key: 'contact_name'),
    contactEmail: asStringOrNull(json['contact_email'], key: 'contact_email'),
    withdrawn: asBool(json['withdrawn'], key: 'withdrawn'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'block_id': blockId,
    'name': name,
    'seed': seed,
    'group_label': groupLabel,
    'contact_name': contactName,
    'contact_email': contactEmail,
    'withdrawn': withdrawn,
  };

  @override
  bool operator ==(Object other) =>
      other is TournamentEntrant &&
      other.id == id &&
      other.blockId == blockId &&
      other.name == name &&
      other.seed == seed &&
      other.groupLabel == groupLabel &&
      other.contactName == contactName &&
      other.contactEmail == contactEmail &&
      other.withdrawn == withdrawn;

  @override
  int get hashCode =>
      Object.hash(id, blockId, name, seed, groupLabel, contactName, contactEmail, withdrawn);
}

/// One fixture in a running tournament, as the app lists it.
@immutable
class ScheduleRow {
  const ScheduleRow({
    required this.eventId,
    required this.title,
    required this.startsAt,
    required this.status,
    this.courtLabel,
    this.stage,
    this.round,
    this.groupLabel,
    this.homeName,
    this.awayName,
    this.homeScore,
    this.awayScore,
    this.homeResult,
  });

  final String eventId;
  final String title;
  final DateTime startsAt;
  final String? courtLabel;

  /// `group` | `knockout`
  final String? stage;
  final int? round;
  final String? groupLabel;
  final String? homeName;
  final String? awayName;
  final int? homeScore;
  final int? awayScore;
  final String? homeResult;
  final String status;

  String get id => eventId;

  factory ScheduleRow.fromJson(JsonMap json) => ScheduleRow(
    eventId: asUuid(json['event_id'], key: 'event_id'),
    title: asString(json['title'], key: 'title'),
    startsAt: asDate(json['starts_at'], key: 'starts_at'),
    courtLabel: asStringOrNull(json['court_label'], key: 'court_label'),
    stage: asStringOrNull(json['stage'], key: 'stage'),
    round: asIntOrNull(json['round'], key: 'round'),
    groupLabel: asStringOrNull(json['group_label'], key: 'group_label'),
    homeName: asStringOrNull(json['home_name'], key: 'home_name'),
    awayName: asStringOrNull(json['away_name'], key: 'away_name'),
    homeScore: asIntOrNull(json['home_score'], key: 'home_score'),
    awayScore: asIntOrNull(json['away_score'], key: 'away_score'),
    homeResult: asStringOrNull(json['home_result'], key: 'home_result'),
    status: asString(json['status'], key: 'status'),
  );

  JsonMap toJson() => <String, dynamic>{
    'event_id': eventId,
    'title': title,
    'starts_at': encodeDate(startsAt),
    'court_label': courtLabel,
    'stage': stage,
    'round': round,
    'group_label': groupLabel,
    'home_name': homeName,
    'away_name': awayName,
    'home_score': homeScore,
    'away_score': awayScore,
    'home_result': homeResult,
    'status': status,
  };

  bool get isPlayed => homeResult != null;

  String? get scoreLine =>
      homeScore == null || awayScore == null ? null : '$homeScore – $awayScore';

  String get fixtureLine => '${homeName ?? "TBC"} v ${awayName ?? "TBC"}';

  @override
  bool operator ==(Object other) =>
      other is ScheduleRow &&
      other.eventId == eventId &&
      other.title == title &&
      other.startsAt == startsAt &&
      other.courtLabel == courtLabel &&
      other.stage == stage &&
      other.round == round &&
      other.groupLabel == groupLabel &&
      other.homeName == homeName &&
      other.awayName == awayName &&
      other.homeScore == homeScore &&
      other.awayScore == awayScore &&
      other.homeResult == homeResult &&
      other.status == status;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    eventId,
    title,
    startsAt,
    courtLabel,
    stage,
    round,
    groupLabel,
    homeName,
    awayName,
    homeScore,
    awayScore,
    homeResult,
    status,
  ]);
}

@immutable
class Standing {
  const Standing({
    required this.entrantId,
    required this.name,
    required this.played,
    required this.won,
    required this.lost,
    required this.drawn,
    required this.noResult,
    required this.points,
    required this.scored,
    required this.conceded,
    this.groupLabel,
  });

  final String entrantId;
  final String name;
  final String? groupLabel;
  final int played;
  final int won;
  final int lost;
  final int drawn;
  final int noResult;
  final int points;
  final int scored;
  final int conceded;

  String get id => entrantId;

  factory Standing.fromJson(JsonMap json) => Standing(
    entrantId: asUuid(json['entrant_id'], key: 'entrant_id'),
    name: asString(json['name'], key: 'name'),
    groupLabel: asStringOrNull(json['group_label'], key: 'group_label'),
    played: asInt(json['played'], key: 'played'),
    won: asInt(json['won'], key: 'won'),
    lost: asInt(json['lost'], key: 'lost'),
    drawn: asInt(json['drawn'], key: 'drawn'),
    noResult: asInt(json['no_result'], key: 'no_result'),
    points: asInt(json['points'], key: 'points'),
    scored: asInt(json['scored'], key: 'scored'),
    conceded: asInt(json['conceded'], key: 'conceded'),
  );

  JsonMap toJson() => <String, dynamic>{
    'entrant_id': entrantId,
    'name': name,
    'group_label': groupLabel,
    'played': played,
    'won': won,
    'lost': lost,
    'drawn': drawn,
    'no_result': noResult,
    'points': points,
    'scored': scored,
    'conceded': conceded,
  };

  int get difference => scored - conceded;

  @override
  bool operator ==(Object other) =>
      other is Standing &&
      other.entrantId == entrantId &&
      other.name == name &&
      other.groupLabel == groupLabel &&
      other.played == played &&
      other.won == won &&
      other.lost == lost &&
      other.drawn == drawn &&
      other.noResult == noResult &&
      other.points == points &&
      other.scored == scored &&
      other.conceded == conceded;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    entrantId,
    name,
    groupLabel,
    played,
    won,
    lost,
    drawn,
    noResult,
    points,
    scored,
    conceded,
  ]);
}

@immutable
class EventTicket {
  const EventTicket({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.guests,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.name,
    this.guestNames,
    this.notes,
  });

  final String id;
  final String eventId;
  final String userId;
  final String? name;
  final int guests;
  final String? guestNames;
  final int amountCents;
  final String currency;

  /// `reserved` | `paid` | `cancelled`
  final String status;
  final String? notes;

  factory EventTicket.fromJson(JsonMap json) => EventTicket(
    id: asUuid(json['id'], key: 'id'),
    eventId: asUuid(json['event_id'], key: 'event_id'),
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asStringOrNull(json['name'], key: 'name'),
    guests: asInt(json['guests'], key: 'guests'),
    guestNames: asStringOrNull(json['guest_names'], key: 'guest_names'),
    amountCents: asInt(json['amount_cents'], key: 'amount_cents'),
    currency: asString(json['currency'], key: 'currency'),
    status: asString(json['status'], key: 'status'),
    notes: asStringOrNull(json['notes'], key: 'notes'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'event_id': eventId,
    'user_id': userId,
    'name': name,
    'guests': guests,
    'guest_names': guestNames,
    'amount_cents': amountCents,
    'currency': currency,
    'status': status,
    'notes': notes,
  };

  bool get isPaid => status == 'paid';

  int get places => 1 + guests;

  @override
  bool operator ==(Object other) =>
      other is EventTicket &&
      other.id == id &&
      other.eventId == eventId &&
      other.userId == userId &&
      other.name == name &&
      other.guests == guests &&
      other.guestNames == guestNames &&
      other.amountCents == amountCents &&
      other.currency == currency &&
      other.status == status &&
      other.notes == notes;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    eventId,
    userId,
    name,
    guests,
    guestNames,
    amountCents,
    currency,
    status,
    notes,
  ]);
}

@immutable
class TicketSummary {
  const TicketSummary({
    required this.eventId,
    required this.title,
    required this.bookings,
    required this.headcount,
    required this.collectedCents,
    required this.outstandingCents,
    this.ticketCapacity,
    this.ticketPriceCents,
    this.guestsAllowed,
  });

  final String eventId;
  final String title;
  final int? ticketCapacity;
  final int? ticketPriceCents;

  /// How many guests one member may bring; zero means members only. Optional
  /// only so an API that predates it still decodes.
  final int? guestsAllowed;
  final int bookings;
  final int headcount;
  final int collectedCents;
  final int outstandingCents;

  factory TicketSummary.fromJson(JsonMap json) => TicketSummary(
    eventId: asUuid(json['event_id'], key: 'event_id'),
    title: asString(json['title'], key: 'title'),
    ticketCapacity: asIntOrNull(json['ticket_capacity'], key: 'ticket_capacity'),
    ticketPriceCents: asIntOrNull(json['ticket_price_cents'], key: 'ticket_price_cents'),
    guestsAllowed: asIntOrNull(json['guests_allowed'], key: 'guests_allowed'),
    bookings: asInt(json['bookings'], key: 'bookings'),
    headcount: asInt(json['headcount'], key: 'headcount'),
    collectedCents: asInt(json['collected_cents'], key: 'collected_cents'),
    outstandingCents: asInt(json['outstanding_cents'], key: 'outstanding_cents'),
  );

  JsonMap toJson() => <String, dynamic>{
    'event_id': eventId,
    'title': title,
    'ticket_capacity': ticketCapacity,
    'ticket_price_cents': ticketPriceCents,
    'guests_allowed': guestsAllowed,
    'bookings': bookings,
    'headcount': headcount,
    'collected_cents': collectedCents,
    'outstanding_cents': outstandingCents,
  };

  int? get placesLeft {
    final int? capacity = ticketCapacity;
    if (capacity == null) return null;
    final int left = capacity - headcount;
    return left > 0 ? left : 0;
  }

  @override
  bool operator ==(Object other) =>
      other is TicketSummary &&
      other.eventId == eventId &&
      other.title == title &&
      other.ticketCapacity == ticketCapacity &&
      other.ticketPriceCents == ticketPriceCents &&
      other.guestsAllowed == guestsAllowed &&
      other.bookings == bookings &&
      other.headcount == headcount &&
      other.collectedCents == collectedCents &&
      other.outstandingCents == outstandingCents;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    eventId,
    title,
    ticketCapacity,
    ticketPriceCents,
    guestsAllowed,
    bookings,
    headcount,
    collectedCents,
    outstandingCents,
  ]);
}

@immutable
class TicketBooking {
  const TicketBooking({required this.summary, required this.tickets});

  final TicketSummary summary;
  final List<EventTicket> tickets;

  factory TicketBooking.fromJson(JsonMap json) => TicketBooking(
    summary: TicketSummary.fromJson(asMap(json['summary'], key: 'summary')),
    tickets: asList(json['tickets'], (Object? v) => EventTicket.fromJson(asMap(v, key: 'tickets'))),
  );

  JsonMap toJson() => <String, dynamic>{
    'summary': summary.toJson(),
    'tickets': tickets.map((EventTicket t) => t.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is TicketBooking && other.summary == summary && listEquals(other.tickets, tickets);

  @override
  int get hashCode => Object.hash(summary, Object.hashAll(tickets));
}

/// A cricket fixture with its match state already joined on.
///
/// The scoring list and the Home overview both want the same thing: what is
/// happening, with enough on the row to decide whether to open it. `score` and
/// `result` arrive already formatted by the API, because a half-built innings
/// reads differently from a finished one and the server is the side that knows.
@immutable
class CricketFixtureRow {
  const CricketFixtureRow({
    required this.eventId,
    required this.clubId,
    required this.title,
    required this.startAt,
    required this.eventStatus,
    required this.hasScorer,
    this.matchId,
    this.matchStatus,
    this.homeName,
    this.awayName,
    this.score,
    this.result,
  });

  final String eventId;
  final String clubId;
  final String title;
  final DateTime startAt;
  final String eventStatus;

  /// Absent until a match is created on the fixture.
  final String? matchId;

  /// `setup`, `live` or `complete`.
  final String? matchStatus;
  final String? homeName;
  final String? awayName;

  /// Somebody is scoring it — not necessarily you.
  final bool hasScorer;

  /// "20/1 (2.0 ov)", as the API formats it.
  final String? score;
  final String? result;

  /// The fixture is the identity: there is at most one match on it, and rows
  /// without a match yet still need to be listed.
  String get id => eventId;

  /// "London Lords v Watford", falling back to the fixture's own title before a
  /// match names the sides.
  String get sides => homeName == null || awayName == null ? title : '$homeName v $awayName';

  factory CricketFixtureRow.fromJson(JsonMap json) => CricketFixtureRow(
    eventId: asUuid(json['event_id'], key: 'event_id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    title: asString(json['title'], key: 'title'),
    startAt: asDate(json['start_at'], key: 'start_at'),
    eventStatus: asString(json['event_status'], key: 'event_status'),
    matchId: asUuidOrNull(json['match_id'], key: 'match_id'),
    matchStatus: asStringOrNull(json['match_status'], key: 'match_status'),
    homeName: asStringOrNull(json['home_name'], key: 'home_name'),
    awayName: asStringOrNull(json['away_name'], key: 'away_name'),
    hasScorer: asBool(json['has_scorer'], key: 'has_scorer'),
    score: asStringOrNull(json['score'], key: 'score'),
    result: asStringOrNull(json['result'], key: 'result'),
  );

  JsonMap toJson() => <String, dynamic>{
    'event_id': eventId,
    'club_id': clubId,
    'title': title,
    'start_at': encodeDate(startAt),
    'event_status': eventStatus,
    'match_id': matchId,
    'match_status': matchStatus,
    'home_name': homeName,
    'away_name': awayName,
    'has_scorer': hasScorer,
    'score': score,
    'result': result,
  };

  @override
  bool operator ==(Object other) =>
      other is CricketFixtureRow &&
      other.eventId == eventId &&
      other.clubId == clubId &&
      other.title == title &&
      other.startAt == startAt &&
      other.eventStatus == eventStatus &&
      other.matchId == matchId &&
      other.matchStatus == matchStatus &&
      other.homeName == homeName &&
      other.awayName == awayName &&
      other.hasScorer == hasScorer &&
      other.score == score &&
      other.result == result;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    eventId,
    clubId,
    title,
    startAt,
    eventStatus,
    matchId,
    matchStatus,
    homeName,
    awayName,
    hasScorer,
    score,
    result,
  ]);
}
