import 'package:flutter/foundation.dart';

import 'cricket_types.dart';
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
    this.description,
    this.maxEntrants,
    this.entryDeadline,
    this.entryFeeCents,
    this.playersPerSide,
    this.guestPlayersAllowed,
    this.ageGroup,
    this.gender,
    this.conditions,
    this.rulesNotes,
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

  // What a tournament settles before anybody enters. All optional: a block
  // created before tournaments carried rules sends none of it, and a plain
  // block of fixtures never will.
  final String? description;

  /// How many sides fit. Null is no limit.
  final int? maxEntrants;
  final DateTime? entryDeadline;

  /// What a side pays to enter — not a spectator's ticket.
  final int? entryFeeCents;

  /// Eleven normally; six for sixes. Null only from an older API.
  final int? playersPerSide;

  /// 0 means every player must belong to the entering club.
  final int? guestPlayersAllowed;
  final String? ageGroup;
  final String? gender;

  /// Overs, ball, ground and the fielding restrictions every fixture in the
  /// tournament inherits. Null means the two captains agree their own.
  final MatchConditions? conditions;
  final String? rulesNotes;

  /// A side is eleven unless the tournament says otherwise.
  int get side => playersPerSide ?? 11;

  factory FixtureBlock.fromJson(JsonMap json) => FixtureBlock(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    teamId: asUuidOrNull(json['team_id'], key: 'team_id'),
    name: asString(json['name'], key: 'name'),
    kind: asString(json['kind'], key: 'kind'),
    startsOn: asStringOrNull(json['starts_on'], key: 'starts_on'),
    endsOn: asStringOrNull(json['ends_on'], key: 'ends_on'),
    description: asStringOrNull(json['description'], key: 'description'),
    maxEntrants: asIntOrNull(json['max_entrants'], key: 'max_entrants'),
    entryDeadline: asDateOrNull(json['entry_deadline'], key: 'entry_deadline'),
    entryFeeCents: asIntOrNull(json['entry_fee_cents'], key: 'entry_fee_cents'),
    playersPerSide: asIntOrNull(json['players_per_side'], key: 'players_per_side'),
    guestPlayersAllowed: asIntOrNull(json['guest_players_allowed'], key: 'guest_players_allowed'),
    ageGroup: asStringOrNull(json['age_group'], key: 'age_group'),
    gender: asStringOrNull(json['gender'], key: 'gender'),
    conditions: switch (asMapOrNull(json['conditions'], key: 'conditions')) {
      final JsonMap c => MatchConditions.fromJson(c),
      null => null,
    },
    rulesNotes: asStringOrNull(json['rules_notes'], key: 'rules_notes'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'team_id': teamId,
    'name': name,
    'kind': kind,
    'starts_on': startsOn,
    'ends_on': endsOn,
    'description': description,
    'max_entrants': maxEntrants,
    'entry_deadline': entryDeadline == null ? null : encodeDate(entryDeadline!),
    'entry_fee_cents': entryFeeCents,
    'players_per_side': playersPerSide,
    'guest_players_allowed': guestPlayersAllowed,
    'age_group': ageGroup,
    'gender': gender,
    'conditions': conditions?.toJson(),
    'rules_notes': rulesNotes,
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
      other.endsOn == endsOn &&
      other.description == description &&
      other.maxEntrants == maxEntrants &&
      other.entryDeadline == entryDeadline &&
      other.entryFeeCents == entryFeeCents &&
      other.playersPerSide == playersPerSide &&
      other.guestPlayersAllowed == guestPlayersAllowed &&
      other.ageGroup == ageGroup &&
      other.gender == gender &&
      other.conditions == conditions &&
      other.rulesNotes == rulesNotes;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    clubId,
    teamId,
    name,
    kind,
    startsOn,
    endsOn,
    description,
    maxEntrants,
    entryDeadline,
    entryFeeCents,
    playersPerSide,
    guestPlayersAllowed,
    ageGroup,
    gender,
    conditions,
    rulesNotes,
  ]);
}

/// Where a side is in the entry process.
///
/// A name an organiser typed in is `accepted` straight away — they are entering
/// it, not asking it. `invited` belongs to a real club that answers for itself,
/// and only accepted sides go into the draw.
enum EntryStatus {
  invited,
  accepted,
  declined,
  withdrawn;

  static EntryStatus parse(String raw) => switch (raw) {
    'invited' => EntryStatus.invited,
    'declined' => EntryStatus.declined,
    'withdrawn' => EntryStatus.withdrawn,
    _ => EntryStatus.accepted,
  };

  String get wire => name;

  String get label => switch (this) {
    EntryStatus.invited => 'Asked',
    EntryStatus.accepted => 'In',
    EntryStatus.declined => 'Declined',
    EntryStatus.withdrawn => 'Withdrawn',
  };
}

@immutable
class TournamentEntrant {
  const TournamentEntrant({
    required this.id,
    required this.blockId,
    required this.name,
    required this.withdrawn,
    this.clubId,
    this.seed,
    this.groupLabel,
    this.contactName,
    this.contactEmail,
    this.status,
    this.respondedAt,
    this.entryPaidAt,
    this.entryPaymentMethod,
  });

  final String id;
  final String blockId;
  final String name;
  final String? clubId;
  final int? seed;
  final String? groupLabel;
  final String? contactName;
  final String? contactEmail;

  /// Null only when talking to an API that predates entry invites.
  final EntryStatus? status;
  final DateTime? respondedAt;

  /// Set when the entry fee is settled, by card or by an organiser recording a
  /// cheque. Null when the tournament is free, or when they still owe.
  final DateTime? entryPaidAt;

  /// `card` | `cash` | `transfer` | `cheque`
  final String? entryPaymentMethod;
  final bool withdrawn;

  bool get entryPaid => entryPaidAt != null;

  /// What the row says, falling back to the old boolean.
  EntryStatus get entry => status ?? (withdrawn ? EntryStatus.withdrawn : EntryStatus.accepted);

  factory TournamentEntrant.fromJson(JsonMap json) => TournamentEntrant(
    id: asUuid(json['id'], key: 'id'),
    blockId: asUuid(json['block_id'], key: 'block_id'),
    name: asString(json['name'], key: 'name'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    seed: asIntOrNull(json['seed'], key: 'seed'),
    groupLabel: asStringOrNull(json['group_label'], key: 'group_label'),
    contactName: asStringOrNull(json['contact_name'], key: 'contact_name'),
    contactEmail: asStringOrNull(json['contact_email'], key: 'contact_email'),
    status: switch (asStringOrNull(json['status'], key: 'status')) {
      final String raw => EntryStatus.parse(raw),
      null => null,
    },
    respondedAt: asDateOrNull(json['responded_at'], key: 'responded_at'),
    entryPaidAt: asDateOrNull(json['entry_paid_at'], key: 'entry_paid_at'),
    entryPaymentMethod: asStringOrNull(json['entry_payment_method'], key: 'entry_payment_method'),
    withdrawn: asBool(json['withdrawn'], key: 'withdrawn'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'block_id': blockId,
    'name': name,
    'club_id': clubId,
    'seed': seed,
    'group_label': groupLabel,
    'contact_name': contactName,
    'contact_email': contactEmail,
    'status': status?.wire,
    'responded_at': respondedAt == null ? null : encodeDate(respondedAt!),
    'entry_paid_at': entryPaidAt == null ? null : encodeDate(entryPaidAt!),
    'entry_payment_method': entryPaymentMethod,
    'withdrawn': withdrawn,
  };

  @override
  bool operator ==(Object other) =>
      other is TournamentEntrant &&
      other.id == id &&
      other.blockId == blockId &&
      other.name == name &&
      other.clubId == clubId &&
      other.seed == seed &&
      other.groupLabel == groupLabel &&
      other.contactName == contactName &&
      other.contactEmail == contactEmail &&
      other.status == status &&
      other.respondedAt == respondedAt &&
      other.entryPaidAt == entryPaidAt &&
      other.entryPaymentMethod == entryPaymentMethod &&
      other.withdrawn == withdrawn;

  @override
  int get hashCode => Object.hash(
    id,
    blockId,
    name,
    clubId,
    seed,
    groupLabel,
    contactName,
    contactEmail,
    status,
    respondedAt,
    entryPaidAt,
    entryPaymentMethod,
    withdrawn,
  );
}

/// What came back from asking a side in.
///
/// `inviteLink` is set only for a side with no Fishers account: club email goes
/// to a shared inbox somebody checks on Sundays, so the organiser often passes
/// the link on themselves.
@immutable
class InviteEntrantResult {
  const InviteEntrantResult({required this.entrant, this.inviteLink});

  final TournamentEntrant entrant;
  final String? inviteLink;

  factory InviteEntrantResult.fromJson(JsonMap json) => InviteEntrantResult(
    entrant: TournamentEntrant.fromJson(asMap(json['entrant'], key: 'entrant')),
    inviteLink: asStringOrNull(json['invite_link'], key: 'invite_link'),
  );

  JsonMap toJson() => <String, dynamic>{'entrant': entrant.toJson(), 'invite_link': inviteLink};

  @override
  bool operator ==(Object other) =>
      other is InviteEntrantResult && other.entrant == entrant && other.inviteLink == inviteLink;

  @override
  int get hashCode => Object.hash(entrant, inviteLink);
}

/// A tournament somebody has asked your club into.
@immutable
class EntryInvitation {
  const EntryInvitation({
    required this.entrantId,
    required this.blockId,
    required this.blockName,
    required this.kind,
    required this.hostClubId,
    required this.hostClubName,
    required this.entrantName,
    required this.status,
    this.startsOn,
    this.endsOn,
    this.clubId,
    this.invitedByName,
    this.entryFeeCents,
    this.entryPaidAt,
  });

  final String entrantId;
  final String blockId;
  final String blockName;
  final String kind;
  final String? startsOn;
  final String? endsOn;
  final String hostClubId;
  final String hostClubName;
  final String entrantName;
  final String? clubId;
  final EntryStatus status;
  final String? invitedByName;

  /// What entering costs. Accepting without being told is how a club ends up
  /// owing £50 it never agreed to.
  final int? entryFeeCents;
  final DateTime? entryPaidAt;

  /// Said yes, still owes. Not in the draw until it is settled.
  bool get owesEntryFee => (entryFeeCents ?? 0) > 0 && entryPaidAt == null;

  factory EntryInvitation.fromJson(JsonMap json) => EntryInvitation(
    entrantId: asUuid(json['entrant_id'], key: 'entrant_id'),
    blockId: asUuid(json['block_id'], key: 'block_id'),
    blockName: asString(json['block_name'], key: 'block_name'),
    kind: asString(json['kind'], key: 'kind'),
    startsOn: asStringOrNull(json['starts_on'], key: 'starts_on'),
    endsOn: asStringOrNull(json['ends_on'], key: 'ends_on'),
    hostClubId: asUuid(json['host_club_id'], key: 'host_club_id'),
    hostClubName: asString(json['host_club_name'], key: 'host_club_name'),
    entrantName: asString(json['entrant_name'], key: 'entrant_name'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    status: EntryStatus.parse(asString(json['status'], key: 'status')),
    invitedByName: asStringOrNull(json['invited_by_name'], key: 'invited_by_name'),
    entryFeeCents: asIntOrNull(json['entry_fee_cents'], key: 'entry_fee_cents'),
    entryPaidAt: asDateOrNull(json['entry_paid_at'], key: 'entry_paid_at'),
  );

  JsonMap toJson() => <String, dynamic>{
    'entrant_id': entrantId,
    'block_id': blockId,
    'block_name': blockName,
    'kind': kind,
    'starts_on': startsOn,
    'ends_on': endsOn,
    'host_club_id': hostClubId,
    'host_club_name': hostClubName,
    'entrant_name': entrantName,
    'club_id': clubId,
    'status': status.wire,
    'invited_by_name': invitedByName,
    'entry_fee_cents': entryFeeCents,
    'entry_paid_at': entryPaidAt == null ? null : encodeDate(entryPaidAt!),
  };

  String? get dates {
    final String? from = startsOn;
    if (from == null) return null;
    final String? to = endsOn;
    if (to == null || to == from) return from;
    return '$from – $to';
  }

  @override
  bool operator ==(Object other) =>
      other is EntryInvitation &&
      other.entrantId == entrantId &&
      other.blockId == blockId &&
      other.blockName == blockName &&
      other.kind == kind &&
      other.startsOn == startsOn &&
      other.endsOn == endsOn &&
      other.hostClubId == hostClubId &&
      other.hostClubName == hostClubName &&
      other.entrantName == entrantName &&
      other.clubId == clubId &&
      other.status == status &&
      other.invitedByName == invitedByName &&
      other.entryFeeCents == entryFeeCents &&
      other.entryPaidAt == entryPaidAt;

  @override
  int get hashCode => Object.hash(
    entrantId,
    blockId,
    blockName,
    kind,
    startsOn,
    endsOn,
    hostClubId,
    hostClubName,
    entrantName,
    clubId,
    status,
    invitedByName,
    entryFeeCents,
    entryPaidAt,
  );
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
    this.ticketsPublic,
  });

  final String eventId;
  final String title;
  final int? ticketCapacity;
  final int? ticketPriceCents;

  /// How many guests one member may bring; zero means members only. Optional
  /// only so an API that predates it still decodes.
  final int? guestsAllowed;

  /// Anyone signed in may buy, not only members of the hosting club. Optional
  /// so an API that predates public sales still decodes.
  final bool? ticketsPublic;
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
    ticketsPublic: asBoolOrNull(json['tickets_public'], key: 'tickets_public'),
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
    'tickets_public': ticketsPublic,
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
  const TicketBooking({required this.summary, required this.tickets, this.canSeeEveryone});

  final TicketSummary summary;
  final List<EventTicket> tickets;

  /// False for a non-member at a public event: they get the headcount and
  /// their own booking, never the guest list. Optional for an older API.
  final bool? canSeeEveryone;

  /// Defaults to showing everything, which is what every event did before
  /// public sales existed and what every member still sees.
  bool get insider => canSeeEveryone ?? true;

  factory TicketBooking.fromJson(JsonMap json) => TicketBooking(
    summary: TicketSummary.fromJson(asMap(json['summary'], key: 'summary')),
    tickets: asList(json['tickets'], (Object? v) => EventTicket.fromJson(asMap(v, key: 'tickets'))),
    canSeeEveryone: asBoolOrNull(json['can_see_everyone'], key: 'can_see_everyone'),
  );

  JsonMap toJson() => <String, dynamic>{
    'summary': summary.toJson(),
    'tickets': tickets.map((EventTicket t) => t.toJson()).toList(growable: false),
    'can_see_everyone': canSeeEveryone,
  };

  @override
  bool operator ==(Object other) =>
      other is TicketBooking &&
      other.summary == summary &&
      other.canSeeEveryone == canSeeEveryone &&
      listEquals(other.tickets, tickets);

  @override
  int get hashCode => Object.hash(summary, canSeeEveryone, Object.hashAll(tickets));
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
