import 'package:flutter/foundation.dart';

import 'json.dart';
import 'models.dart';

/// A port of `ios/Fishers/Models/Selection.swift`.

/// Where a player sits in the selection for one fixture.
enum SelectionState {
  pool('pool'),
  selected('selected'),
  reserve('reserve'),
  notSelected('not_selected'),
  confirmed('confirmed'),
  declined('declined'),
  dropped('dropped');

  const SelectionState(this.wire);

  final String wire;

  String get label => switch (this) {
    SelectionState.pool => 'Available pool',
    SelectionState.selected => 'Selected',
    SelectionState.reserve => 'Reserve',
    SelectionState.notSelected => 'Not selected',
    SelectionState.confirmed => 'Confirmed',
    SelectionState.declined => 'Declined',
    SelectionState.dropped => 'Dropped',
  };

  bool get isInSquad => this == SelectionState.selected || this == SelectionState.confirmed;

  static SelectionState fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(SelectionState.values, raw, (SelectionState s) => s.wire, key: key);

  String toJson() => wire;
}

@immutable
class SelectionCandidate {
  const SelectionCandidate({
    required this.userId,
    required this.name,
    required this.reliabilityScore,
    required this.reliabilityBand,
    required this.gamesMissedOut,
    required this.state,
    required this.isConfirmed,
    this.position,
    this.skillLevel,
    this.availability,
  });

  final String userId;
  final String name;
  final String? position;
  final String? skillLevel;
  final AvailabilityStatus? availability;
  final int reliabilityScore;
  final String reliabilityBand;

  /// Fixtures they were available for but left out of, last 60 days.
  final int gamesMissedOut;
  final SelectionState state;
  final bool isConfirmed;

  String get id => userId;

  factory SelectionCandidate.fromJson(JsonMap json) => SelectionCandidate(
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asString(json['name'], key: 'name'),
    position: asStringOrNull(json['position'], key: 'position'),
    skillLevel: asStringOrNull(json['skill_level'], key: 'skill_level'),
    availability: AvailabilityStatus.fromJsonOrNull(json['availability']),
    reliabilityScore: asInt(json['reliability_score'], key: 'reliability_score'),
    reliabilityBand: asString(json['reliability_band'], key: 'reliability_band'),
    gamesMissedOut: asInt(json['games_missed_out'], key: 'games_missed_out'),
    state: SelectionState.fromJson(json['state'], key: 'state'),
    isConfirmed: asBool(json['is_confirmed'], key: 'is_confirmed'),
  );

  JsonMap toJson() => <String, dynamic>{
    'user_id': userId,
    'name': name,
    'position': position,
    'skill_level': skillLevel,
    'availability': availability?.toJson(),
    'reliability_score': reliabilityScore,
    'reliability_band': reliabilityBand,
    'games_missed_out': gamesMissedOut,
    'state': state.toJson(),
    'is_confirmed': isConfirmed,
  };

  @override
  bool operator ==(Object other) =>
      other is SelectionCandidate &&
      other.userId == userId &&
      other.name == name &&
      other.position == position &&
      other.skillLevel == skillLevel &&
      other.availability == availability &&
      other.reliabilityScore == reliabilityScore &&
      other.reliabilityBand == reliabilityBand &&
      other.gamesMissedOut == gamesMissedOut &&
      other.state == state &&
      other.isConfirmed == isConfirmed;

  @override
  int get hashCode => Object.hash(
    userId,
    name,
    position,
    skillLevel,
    availability,
    reliabilityScore,
    reliabilityBand,
    gamesMissedOut,
    state,
    isConfirmed,
  );
}

@immutable
class RankedCandidate {
  const RankedCandidate({
    required this.userId,
    required this.name,
    required this.score,
    required this.reasons,
  });

  final String userId;
  final String name;
  final int score;

  /// Plain-English reasons, in the order the ranking applied them.
  final List<String> reasons;

  String get id => userId;

  factory RankedCandidate.fromJson(JsonMap json) => RankedCandidate(
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asString(json['name'], key: 'name'),
    score: asInt(json['score'], key: 'score'),
    reasons: asList(json['reasons'], (Object? v) => asString(v, key: 'reasons')),
  );

  JsonMap toJson() => <String, dynamic>{
    'user_id': userId,
    'name': name,
    'score': score,
    'reasons': reasons,
  };

  @override
  bool operator ==(Object other) =>
      other is RankedCandidate &&
      other.userId == userId &&
      other.name == name &&
      other.score == score &&
      listEquals(other.reasons, reasons);

  @override
  int get hashCode => Object.hash(userId, name, score, Object.hashAll(reasons));
}

@immutable
class PositionQuota {
  const PositionQuota({required this.position, required this.minimum});

  final String position;
  final int minimum;

  factory PositionQuota.fromJson(JsonMap json) => PositionQuota(
    position: asString(json['position'], key: 'position'),
    minimum: asInt(json['minimum'], key: 'minimum'),
  );

  JsonMap toJson() => <String, dynamic>{'position': position, 'minimum': minimum};

  @override
  bool operator ==(Object other) =>
      other is PositionQuota && other.position == position && other.minimum == minimum;

  @override
  int get hashCode => Object.hash(position, minimum);
}

@immutable
class SquadRequirements {
  const SquadRequirements({
    required this.size,
    required this.reserves,
    required this.positionQuotas,
  });

  final int size;
  final int reserves;
  final List<PositionQuota> positionQuotas;

  factory SquadRequirements.fromJson(JsonMap json) => SquadRequirements(
    size: asInt(json['size'], key: 'size'),
    reserves: asInt(json['reserves'], key: 'reserves'),
    positionQuotas: asList(
      json['position_quotas'],
      (Object? v) => PositionQuota.fromJson(asMap(v, key: 'position_quotas')),
    ),
  );

  JsonMap toJson() => <String, dynamic>{
    'size': size,
    'reserves': reserves,
    'position_quotas': positionQuotas.map((PositionQuota q) => q.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is SquadRequirements &&
      other.size == size &&
      other.reserves == reserves &&
      listEquals(other.positionQuotas, positionQuotas);

  @override
  int get hashCode => Object.hash(size, reserves, Object.hashAll(positionQuotas));
}

/// Everything the captain's selection screen needs in one call.
@immutable
class SelectionBoard {
  const SelectionBoard({
    required this.eventId,
    required this.title,
    required this.sport,
    required this.startsAt,
    required this.status,
    required this.requirements,
    required this.autonomy,
    required this.confirmLeadHours,
    required this.dropLeadHours,
    required this.candidates,
    required this.ranked,
    required this.selectedCount,
    required this.confirmedCount,
    this.statusNote,
  });

  final String eventId;
  final String title;
  final String sport;
  final DateTime startsAt;
  final String status;
  final String? statusNote;
  final SquadRequirements requirements;

  /// `off` | `suggest` | `auto_publish`
  final String autonomy;
  final int confirmLeadHours;
  final int dropLeadHours;
  final List<SelectionCandidate> candidates;
  final List<RankedCandidate> ranked;
  final int selectedCount;
  final int confirmedCount;

  factory SelectionBoard.fromJson(JsonMap json) => SelectionBoard(
    eventId: asUuid(json['event_id'], key: 'event_id'),
    title: asString(json['title'], key: 'title'),
    sport: asString(json['sport'], key: 'sport'),
    startsAt: asDate(json['starts_at'], key: 'starts_at'),
    status: asString(json['status'], key: 'status'),
    statusNote: asStringOrNull(json['status_note'], key: 'status_note'),
    requirements: SquadRequirements.fromJson(asMap(json['requirements'], key: 'requirements')),
    autonomy: asString(json['autonomy'], key: 'autonomy'),
    confirmLeadHours: asInt(json['confirm_lead_hours'], key: 'confirm_lead_hours'),
    dropLeadHours: asInt(json['drop_lead_hours'], key: 'drop_lead_hours'),
    candidates: asList(
      json['candidates'],
      (Object? v) => SelectionCandidate.fromJson(asMap(v, key: 'candidates')),
    ),
    ranked: asList(
      json['ranked'],
      (Object? v) => RankedCandidate.fromJson(asMap(v, key: 'ranked')),
    ),
    selectedCount: asInt(json['selected_count'], key: 'selected_count'),
    confirmedCount: asInt(json['confirmed_count'], key: 'confirmed_count'),
  );

  JsonMap toJson() => <String, dynamic>{
    'event_id': eventId,
    'title': title,
    'sport': sport,
    'starts_at': encodeDate(startsAt),
    'status': status,
    'status_note': statusNote,
    'requirements': requirements.toJson(),
    'autonomy': autonomy,
    'confirm_lead_hours': confirmLeadHours,
    'drop_lead_hours': dropLeadHours,
    'candidates': candidates.map((SelectionCandidate c) => c.toJson()).toList(growable: false),
    'ranked': ranked.map((RankedCandidate c) => c.toJson()).toList(growable: false),
    'selected_count': selectedCount,
    'confirmed_count': confirmedCount,
  };

  List<SelectionCandidate> candidatesIn(SelectionState state) =>
      candidates.where((SelectionCandidate c) => c.state == state).toList(growable: false);

  /// Ranked order, restricted to players not yet decided.
  List<SelectionCandidate> get pool {
    final Set<String> undecided = <String>{
      for (final SelectionCandidate c in candidates)
        if (c.state == SelectionState.pool) c.userId,
    };
    final List<SelectionCandidate> out = <SelectionCandidate>[];
    for (final RankedCandidate rank in ranked) {
      if (!undecided.contains(rank.userId)) continue;
      for (final SelectionCandidate candidate in candidates) {
        if (candidate.userId == rank.userId) {
          out.add(candidate);
          break;
        }
      }
    }
    return out;
  }

  List<String> reasonsFor(String userId) {
    for (final RankedCandidate rank in ranked) {
      if (rank.userId == userId) return rank.reasons;
    }
    return const <String>[];
  }

  bool get isAssistantAvailable => autonomy != 'off';

  @override
  bool operator ==(Object other) =>
      other is SelectionBoard &&
      other.eventId == eventId &&
      other.title == title &&
      other.sport == sport &&
      other.startsAt == startsAt &&
      other.status == status &&
      other.statusNote == statusNote &&
      other.requirements == requirements &&
      other.autonomy == autonomy &&
      other.confirmLeadHours == confirmLeadHours &&
      other.dropLeadHours == dropLeadHours &&
      listEquals(other.candidates, candidates) &&
      listEquals(other.ranked, ranked) &&
      other.selectedCount == selectedCount &&
      other.confirmedCount == confirmedCount;

  @override
  int get hashCode => Object.hash(
    eventId,
    title,
    sport,
    startsAt,
    status,
    statusNote,
    requirements,
    autonomy,
    confirmLeadHours,
    dropLeadHours,
    Object.hashAll(candidates),
    Object.hashAll(ranked),
    selectedCount,
    confirmedCount,
  );
}

/// A squad awaiting publish, from either the ranking or the assistant.
@immutable
class SquadProposal {
  const SquadProposal({
    required this.source,
    required this.selected,
    required this.reserves,
    required this.unmetQuotas,
    required this.published,
    this.announcement,
    this.concerns,
    this.confidence,
  });

  /// `ranking` or `assistant`
  final String source;
  final List<RankedCandidate> selected;
  final List<RankedCandidate> reserves;
  final List<String> unmetQuotas;
  final String? announcement;
  final String? concerns;
  final String? confidence;
  final bool published;

  factory SquadProposal.fromJson(JsonMap json) => SquadProposal(
    source: asString(json['source'], key: 'source'),
    selected: asList(
      json['selected'],
      (Object? v) => RankedCandidate.fromJson(asMap(v, key: 'selected')),
    ),
    reserves: asList(
      json['reserves'],
      (Object? v) => RankedCandidate.fromJson(asMap(v, key: 'reserves')),
    ),
    unmetQuotas: asList(json['unmet_quotas'], (Object? v) => asString(v, key: 'unmet_quotas')),
    announcement: asStringOrNull(json['announcement'], key: 'announcement'),
    concerns: asStringOrNull(json['concerns'], key: 'concerns'),
    confidence: asStringOrNull(json['confidence'], key: 'confidence'),
    published: asBool(json['published'], key: 'published'),
  );

  JsonMap toJson() => <String, dynamic>{
    'source': source,
    'selected': selected.map((RankedCandidate c) => c.toJson()).toList(growable: false),
    'reserves': reserves.map((RankedCandidate c) => c.toJson()).toList(growable: false),
    'unmet_quotas': unmetQuotas,
    'announcement': announcement,
    'concerns': concerns,
    'confidence': confidence,
    'published': published,
  };

  bool get isFromAssistant => source == 'assistant';

  @override
  bool operator ==(Object other) =>
      other is SquadProposal &&
      other.source == source &&
      listEquals(other.selected, selected) &&
      listEquals(other.reserves, reserves) &&
      listEquals(other.unmetQuotas, unmetQuotas) &&
      other.announcement == announcement &&
      other.concerns == concerns &&
      other.confidence == confidence &&
      other.published == published;

  @override
  int get hashCode => Object.hash(
    source,
    Object.hashAll(selected),
    Object.hashAll(reserves),
    Object.hashAll(unmetQuotas),
    announcement,
    concerns,
    confidence,
    published,
  );
}

@immutable
class OutstandingFee {
  const OutstandingFee({
    required this.userId,
    required this.name,
    required this.eventId,
    required this.fixture,
    required this.startAt,
    required this.currency,
    required this.remindersSent,
    this.amountCents,
  });

  final String userId;
  final String name;
  final String eventId;
  final String fixture;
  final DateTime startAt;
  final int? amountCents;
  final String currency;
  final int remindersSent;

  String get id => '$userId-$eventId';

  factory OutstandingFee.fromJson(JsonMap json) => OutstandingFee(
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asString(json['name'], key: 'name'),
    eventId: asUuid(json['event_id'], key: 'event_id'),
    fixture: asString(json['fixture'], key: 'fixture'),
    startAt: asDate(json['start_at'], key: 'start_at'),
    amountCents: asIntOrNull(json['amount_cents'], key: 'amount_cents'),
    currency: asString(json['currency'], key: 'currency'),
    remindersSent: asInt(json['reminders_sent'], key: 'reminders_sent'),
  );

  JsonMap toJson() => <String, dynamic>{
    'user_id': userId,
    'name': name,
    'event_id': eventId,
    'fixture': fixture,
    'start_at': encodeDate(startAt),
    'amount_cents': amountCents,
    'currency': currency,
    'reminders_sent': remindersSent,
  };

  @override
  bool operator ==(Object other) =>
      other is OutstandingFee &&
      other.userId == userId &&
      other.name == name &&
      other.eventId == eventId &&
      other.fixture == fixture &&
      other.startAt == startAt &&
      other.amountCents == amountCents &&
      other.currency == currency &&
      other.remindersSent == remindersSent;

  @override
  int get hashCode =>
      Object.hash(userId, name, eventId, fixture, startAt, amountCents, currency, remindersSent);
}

@immutable
class OutstandingFees {
  const OutstandingFees({required this.totalCents, required this.count, required this.owed});

  final int totalCents;
  final int count;
  final List<OutstandingFee> owed;

  factory OutstandingFees.fromJson(JsonMap json) => OutstandingFees(
    totalCents: asInt(json['total_cents'], key: 'total_cents'),
    count: asInt(json['count'], key: 'count'),
    owed: asList(json['owed'], (Object? v) => OutstandingFee.fromJson(asMap(v, key: 'owed'))),
  );

  JsonMap toJson() => <String, dynamic>{
    'total_cents': totalCents,
    'count': count,
    'owed': owed.map((OutstandingFee f) => f.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is OutstandingFees &&
      other.totalCents == totalCents &&
      other.count == count &&
      listEquals(other.owed, owed);

  @override
  int get hashCode => Object.hash(totalCents, count, Object.hashAll(owed));
}
