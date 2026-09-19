import 'package:flutter/foundation.dart';

import 'json.dart';
import 'models.dart';

/// A port of `ios/Fishers/Models/Fixtures.swift`.

/// "Can you play?" — the three answers, saved as an RSVP.
enum FixtureAnswer {
  going('going'),
  maybe('maybe'),
  notGoing('not_going');

  const FixtureAnswer(this.wire);

  final String wire;

  String get label => switch (this) {
    FixtureAnswer.going => 'Available',
    FixtureAnswer.maybe => 'Maybe',
    FixtureAnswer.notGoing => "Can't play",
  };

  /// What the card says back.
  String get said => switch (this) {
    FixtureAnswer.going => "You're available",
    FixtureAnswer.maybe => 'You said maybe',
    FixtureAnswer.notGoing => "You can't play",
  };

  RsvpStatus get rsvp => switch (this) {
    FixtureAnswer.going => RsvpStatus.going,
    FixtureAnswer.maybe => RsvpStatus.maybe,
    FixtureAnswer.notGoing => RsvpStatus.notGoing,
  };

  static FixtureAnswer? fromJsonOrNull(Object? raw) => raw == null
      ? null
      : enumFromRaw(FixtureAnswer.values, raw as String?, (FixtureAnswer a) => a.wire);

  String toJson() => wire;
}

/// One of your fixtures with your answer to it (`GET /events/mine`). The list
/// and the calendar both read this, so they cannot disagree about whether you
/// are playing.
@immutable
class MyFixture {
  const MyFixture({
    required this.eventId,
    required this.title,
    required this.sport,
    required this.eventSubtype,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.clubId,
    required this.clubName,
    this.opponentClubId,
    this.opponentClubName,
    this.venueName,
    this.matchId,
    this.myAnswer,
    this.feeAmountCents,
    this.ticketPriceCents,
  });

  final String eventId;
  final String title;
  final String sport;
  final String eventSubtype;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final String clubId;
  final String clubName;
  final String? opponentClubId;
  final String? opponentClubName;
  final String? venueName;
  final String? matchId;
  final FixtureAnswer? myAnswer;
  final int? feeAmountCents;
  final int? ticketPriceCents;

  String get id => eventId;

  factory MyFixture.fromJson(JsonMap json) => MyFixture(
    eventId: asUuid(json['event_id'], key: 'event_id'),
    title: asString(json['title'], key: 'title'),
    sport: asString(json['sport'], key: 'sport'),
    eventSubtype: asString(json['event_subtype'], key: 'event_subtype'),
    status: asString(json['status'], key: 'status'),
    startAt: asDate(json['start_at'], key: 'start_at'),
    endAt: asDate(json['end_at'], key: 'end_at'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    clubName: asString(json['club_name'], key: 'club_name'),
    opponentClubId: asUuidOrNull(json['opponent_club_id'], key: 'opponent_club_id'),
    opponentClubName: asStringOrNull(json['opponent_club_name'], key: 'opponent_club_name'),
    venueName: asStringOrNull(json['venue_name'], key: 'venue_name'),
    matchId: asUuidOrNull(json['match_id'], key: 'match_id'),
    myAnswer: FixtureAnswer.fromJsonOrNull(json['my_answer']),
    feeAmountCents: asIntOrNull(json['fee_amount_cents'], key: 'fee_amount_cents'),
    ticketPriceCents: asIntOrNull(json['ticket_price_cents'], key: 'ticket_price_cents'),
  );

  JsonMap toJson() => <String, dynamic>{
    'event_id': eventId,
    'title': title,
    'sport': sport,
    'event_subtype': eventSubtype,
    'status': status,
    'start_at': encodeDate(startAt),
    'end_at': encodeDate(endAt),
    'club_id': clubId,
    'club_name': clubName,
    'opponent_club_id': opponentClubId,
    'opponent_club_name': opponentClubName,
    'venue_name': venueName,
    'match_id': matchId,
    'my_answer': myAnswer?.toJson(),
    'fee_amount_cents': feeAmountCents,
    'ticket_price_cents': ticketPriceCents,
  };

  String get saidLabel => myAnswer?.said ?? 'Not answered yet';

  bool get isCancelled => status == 'cancelled';
  bool get isPostponed => status == 'postponed';

  @override
  bool operator ==(Object other) =>
      other is MyFixture &&
      other.eventId == eventId &&
      other.title == title &&
      other.sport == sport &&
      other.eventSubtype == eventSubtype &&
      other.status == status &&
      other.startAt == startAt &&
      other.endAt == endAt &&
      other.clubId == clubId &&
      other.clubName == clubName &&
      other.opponentClubId == opponentClubId &&
      other.opponentClubName == opponentClubName &&
      other.venueName == venueName &&
      other.matchId == matchId &&
      other.myAnswer == myAnswer &&
      other.feeAmountCents == feeAmountCents &&
      other.ticketPriceCents == ticketPriceCents;

  @override
  int get hashCode => Object.hash(
    eventId,
    title,
    sport,
    eventSubtype,
    status,
    startAt,
    endAt,
    clubId,
    clubName,
    opponentClubId,
    opponentClubName,
    venueName,
    matchId,
    myAnswer,
    feeAmountCents,
    ticketPriceCents,
  );
}

/// The grouping and clash rules the fixtures list and the calendar share.
abstract final class FixtureList {
  /// Fixtures by the local calendar day they start on, days in order.
  static List<({DateTime day, List<MyFixture> fixtures})> byDay(List<MyFixture> fixtures) {
    final Map<DateTime, List<MyFixture>> grouped = <DateTime, List<MyFixture>>{};
    for (final MyFixture fixture in fixtures) {
      final DateTime local = fixture.startAt.toLocal();
      final DateTime day = DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(day, () => <MyFixture>[]).add(fixture);
    }
    final List<DateTime> days = grouped.keys.toList()..sort();
    return <({DateTime day, List<MyFixture> fixtures})>[
      for (final DateTime day in days)
        (
          day: day,
          fixtures: grouped[day]!
            ..sort((MyFixture a, MyFixture b) => a.startAt.compareTo(b.startAt)),
        ),
    ];
  }

  /// Fixtures you have said yes to that overlap another you said yes to.
  static Set<String> clashes(List<MyFixture> fixtures) {
    final List<MyFixture> yes = fixtures
        .where((MyFixture f) => f.myAnswer == FixtureAnswer.going)
        .toList(growable: false);
    final Set<String> out = <String>{};
    for (final MyFixture a in yes) {
      for (final MyFixture b in yes) {
        if (a.eventId != b.eventId && a.startAt.isBefore(b.endAt) && b.startAt.isBefore(a.endAt)) {
          out.add(a.eventId);
        }
      }
    }
    return out;
  }

  /// Every date in [month] that falls on [weekday] (1 = Sunday … 7 = Saturday,
  /// matching Foundation's `Calendar` numbering, which is not Dart's).
  static List<DateTime> datesIn(DateTime month, {required int weekday}) {
    final DateTime first = DateTime(month.year, month.month);
    final DateTime nextMonth = DateTime(month.year, month.month + 1);
    final int days = nextMonth.difference(first).inDays;
    return <DateTime>[
      for (int i = 0; i < days; i++)
        if (_foundationWeekday(DateTime(month.year, month.month, i + 1)) == weekday)
          DateTime(month.year, month.month, i + 1),
    ];
  }

  /// Dart numbers Monday 1 … Sunday 7; Foundation numbers Sunday 1 … Saturday 7.
  static int _foundationWeekday(DateTime date) => date.weekday % 7 + 1;
}
