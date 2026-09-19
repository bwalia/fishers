import 'package:flutter/foundation.dart';

import 'json.dart';

/// A port of `ios/Fishers/Cricket/CricketTypes.swift` — the wire format, which
/// matches the Rust backend's serde snake_case.
///
/// Scope note: this file carries the **types**. The fold that turns an event
/// log into a [MatchState] — `CricketEngine.swift`'s `replay` and `apply` — is
/// a later layer, and so are the mutating helpers that only the engine calls
/// (`swapStrike`, `ensureBowler`, `batterIndex`, `bowlerIndex`) and
/// `MatchState.history`, the local undo stack that is never serialised. The
/// read-only derivations that screens use are here, because they are here on
/// iOS too.

// MARK: - Enums

enum CricketMatchStatus {
  scheduled('scheduled'),
  preparing('preparing'),
  toss('toss'),
  selectingXi('selecting_xi'),
  ready('ready'),
  live('live'),
  inningsBreak('innings_break'),
  complete('complete'),
  published('published');

  const CricketMatchStatus(this.wire);

  final String wire;

  bool get isFinished =>
      this == CricketMatchStatus.complete || this == CricketMatchStatus.published;

  static CricketMatchStatus fromJson(Object? raw, {String? key}) => enumFromRawOrThrow(
    CricketMatchStatus.values,
    raw,
    (CricketMatchStatus s) => s.wire,
    key: key,
  );

  String toJson() => wire;
}

enum TossDecision {
  bat('bat'),
  bowl('bowl');

  const TossDecision(this.wire);

  final String wire;

  String get label => this == TossDecision.bat ? 'Bat' : 'Bowl';

  static TossDecision fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(TossDecision.values, raw, (TossDecision d) => d.wire, key: key);

  static TossDecision? fromJsonOrNull(Object? raw) => raw == null
      ? null
      : enumFromRaw(TossDecision.values, raw as String?, (TossDecision d) => d.wire);

  String toJson() => wire;
}

enum MatchSide {
  home('home'),
  away('away');

  const MatchSide(this.wire);

  final String wire;

  MatchSide get opposite => this == MatchSide.home ? MatchSide.away : MatchSide.home;

  static MatchSide fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(MatchSide.values, raw, (MatchSide s) => s.wire, key: key);

  static MatchSide? fromJsonOrNull(Object? raw) =>
      raw == null ? null : enumFromRaw(MatchSide.values, raw as String?, (MatchSide s) => s.wire);

  String toJson() => wire;
}

enum DismissalKind {
  bowled('bowled'),
  caught('caught'),
  lbw('lbw'),
  runOut('run_out'),
  stumped('stumped'),
  hitWicket('hit_wicket'),
  retired('retired'),
  retiredHurt('retired_hurt'),
  other('other');

  const DismissalKind(this.wire);

  final String wire;

  String get label => switch (this) {
    DismissalKind.bowled => 'Bowled',
    DismissalKind.caught => 'Caught',
    DismissalKind.lbw => 'LBW',
    DismissalKind.runOut => 'Run out',
    DismissalKind.stumped => 'Stumped',
    DismissalKind.hitWicket => 'Hit wicket',
    DismissalKind.retired => 'Retired out',
    DismissalKind.retiredHurt => 'Retired hurt',
    DismissalKind.other => 'Other',
  };

  /// Dismissals the bowler gets credit for.
  bool get creditsBowler => switch (this) {
    DismissalKind.bowled ||
    DismissalKind.caught ||
    DismissalKind.lbw ||
    DismissalKind.stumped ||
    DismissalKind.hitWicket => true,
    _ => false,
  };

  /// Retiring, either way, does not use up a delivery.
  bool get usesABall => this != DismissalKind.retired && this != DismissalKind.retiredHurt;

  /// Retired hurt costs a batter but not a wicket, and they may come back.
  bool get costsAWicket => this != DismissalKind.retiredHurt;

  /// The only ways out on a free hit.
  bool get allowedOnAFreeHit => switch (this) {
    DismissalKind.runOut ||
    DismissalKind.retired ||
    DismissalKind.retiredHurt ||
    DismissalKind.other => true,
    _ => false,
  };

  /// A dismissal that can land on a delivery already booked as an extra.
  bool get canFollowAnExtra => switch (this) {
    DismissalKind.stumped || DismissalKind.runOut || DismissalKind.other => true,
    _ => false,
  };

  /// Who took the catch, effected the run out, made the stumping.
  bool get needsFielder => switch (this) {
    DismissalKind.caught || DismissalKind.runOut || DismissalKind.stumped => true,
    _ => false,
  };

  /// Only a run out can take the batter at the non-striker's end.
  bool get canDismissNonStriker =>
      this == DismissalKind.runOut ||
      this == DismissalKind.retired ||
      this == DismissalKind.retiredHurt;

  /// Runs can be completed before a run out.
  bool get allowsCompletedRuns => this == DismissalKind.runOut;

  static DismissalKind fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(DismissalKind.values, raw, (DismissalKind k) => k.wire, key: key);

  static DismissalKind? fromJsonOrNull(Object? raw) => raw == null
      ? null
      : enumFromRaw(DismissalKind.values, raw as String?, (DismissalKind k) => k.wire);

  String toJson() => wire;
}

enum ExtraKind {
  wide('wide'),
  noBall('no_ball'),
  bye('bye'),
  legBye('leg_bye'),
  penalty('penalty');

  const ExtraKind(this.wire);

  final String wire;

  String get label => switch (this) {
    ExtraKind.wide => 'Wide',
    ExtraKind.noBall => 'No ball',
    ExtraKind.bye => 'Bye',
    ExtraKind.legBye => 'Leg bye',
    ExtraKind.penalty => 'Penalty',
  };

  String get shortLabel => switch (this) {
    ExtraKind.wide => 'wd',
    ExtraKind.noBall => 'nb',
    ExtraKind.bye => 'b',
    ExtraKind.legBye => 'lb',
    ExtraKind.penalty => 'p',
  };

  /// The runs field means "total including the extra itself" for wides and no
  /// balls, and "runs run" for byes and leg byes.
  String get footnote => switch (this) {
    ExtraKind.wide => '1 for the wide, plus any run.',
    ExtraKind.noBall => '1 for the no ball, plus runs off the bat.',
    ExtraKind.bye || ExtraKind.legBye => 'Counts as a legal ball.',
    ExtraKind.penalty => 'Five penalty runs, no ball bowled.',
  };

  static ExtraKind fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(ExtraKind.values, raw, (ExtraKind k) => k.wire, key: key);

  String toJson() => wire;
}

enum SyncStatus {
  saved('saved'),
  syncing('syncing'),
  offline('offline');

  const SyncStatus(this.wire);

  final String wire;

  static SyncStatus fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(SyncStatus.values, raw, (SyncStatus s) => s.wire, key: key);

  String toJson() => wire;
}

/// Where the game is being played.
enum GroundType {
  open('open'),
  boxed('boxed'),
  indoor('indoor');

  const GroundType(this.wire);

  final String wire;

  String get label => switch (this) {
    GroundType.open => 'Open ground',
    GroundType.boxed => 'Boxed / caged',
    GroundType.indoor => 'Indoor',
  };

  String get blurb => switch (this) {
    GroundType.open => 'Full boundary, normal outfield.',
    GroundType.boxed => 'Caged or netted — walls are in play.',
    GroundType.indoor => 'Indoor centre rules.',
  };

  static GroundType fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(GroundType.values, raw, (GroundType g) => g.wire, key: key);

  String toJson() => wire;
}

/// What they are bowling with.
enum BallType {
  red('red'),
  white('white'),
  pink('pink'),
  tennis('tennis'),
  tape('tape');

  const BallType(this.wire);

  final String wire;

  String get label => switch (this) {
    BallType.red => 'Red leather',
    BallType.white => 'White leather',
    BallType.pink => 'Pink leather',
    BallType.tennis => 'Tennis',
    BallType.tape => 'Tape ball',
  };

  String get shortLabel => switch (this) {
    BallType.red => 'Red',
    BallType.white => 'White',
    BallType.pink => 'Pink',
    BallType.tennis => 'Tennis',
    BallType.tape => 'Tape',
  };

  static BallType fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(BallType.values, raw, (BallType b) => b.wire, key: key);

  String toJson() => wire;
}

/// How the shot was played. Enough to write a line of commentary from.
enum ShotKind {
  drive('drive'),
  cut('cut'),
  pull('pull'),
  hook('hook'),
  sweep('sweep'),
  reverseSweep('reverse_sweep'),
  glance('glance'),
  flick('flick'),
  loft('loft'),
  defence('defence'),
  edge('edge'),
  leave('leave'),
  other('other');

  const ShotKind(this.wire);

  final String wire;

  String get label => switch (this) {
    ShotKind.drive => 'Drive',
    ShotKind.cut => 'Cut',
    ShotKind.pull => 'Pull',
    ShotKind.hook => 'Hook',
    ShotKind.sweep => 'Sweep',
    ShotKind.reverseSweep => 'Reverse sweep',
    ShotKind.glance => 'Glance',
    ShotKind.flick => 'Flick',
    ShotKind.loft => 'Loft',
    ShotKind.defence => 'Defence',
    ShotKind.edge => 'Edge',
    ShotKind.leave => 'Leave',
    ShotKind.other => 'Other',
  };

  /// The verb a commentator would use.
  String get verb => switch (this) {
    ShotKind.drive => 'driven',
    ShotKind.cut => 'cut',
    ShotKind.pull => 'pulled',
    ShotKind.hook => 'hooked',
    ShotKind.sweep => 'swept',
    ShotKind.reverseSweep => 'reverse-swept',
    ShotKind.glance => 'glanced',
    ShotKind.flick => 'flicked',
    ShotKind.loft => 'lofted',
    ShotKind.defence => 'defended',
    ShotKind.edge => 'edged',
    ShotKind.leave => 'left alone',
    ShotKind.other => 'worked away',
  };

  /// The shots most likely for a given number of runs, offered first.
  static List<ShotKind> likely({required int runs}) => switch (runs) {
    0 => const <ShotKind>[
      ShotKind.defence,
      ShotKind.leave,
      ShotKind.edge,
      ShotKind.drive,
      ShotKind.cut,
      ShotKind.pull,
      ShotKind.other,
    ],
    4 => const <ShotKind>[
      ShotKind.drive,
      ShotKind.cut,
      ShotKind.pull,
      ShotKind.sweep,
      ShotKind.glance,
      ShotKind.flick,
      ShotKind.edge,
      ShotKind.loft,
    ],
    6 => const <ShotKind>[
      ShotKind.loft,
      ShotKind.pull,
      ShotKind.hook,
      ShotKind.drive,
      ShotKind.sweep,
    ],
    _ => const <ShotKind>[
      ShotKind.drive,
      ShotKind.flick,
      ShotKind.glance,
      ShotKind.cut,
      ShotKind.pull,
      ShotKind.sweep,
      ShotKind.other,
    ],
  };

  static ShotKind fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(ShotKind.values, raw, (ShotKind k) => k.wire, key: key);

  String toJson() => wire;
}

/// The eight sectors of a wagon wheel, named as the batter's own field.
String cricketRegion({required int angle, required bool batsLeft}) {
  final int raw = angle % 360;
  final int a = batsLeft ? (360 - raw) % 360 : raw;
  if (a <= 44) return 'long on';
  if (a <= 89) return 'mid-wicket';
  if (a <= 134) return 'square leg';
  if (a <= 179) return 'fine leg';
  if (a <= 224) return 'third man';
  if (a <= 269) return 'point';
  if (a <= 314) return 'cover';
  return 'long off';
}

// MARK: - Team sheet

/// Who is standing and who is keeping the book.
@immutable
class MatchOfficials {
  const MatchOfficials({
    this.umpires = const <MatchPlayer>[],
    this.scorers = const <MatchPlayer>[],
  });

  final List<MatchPlayer> umpires;
  final List<MatchPlayer> scorers;

  factory MatchOfficials.fromJson(JsonMap json) => MatchOfficials(
    umpires: asListOrEmpty(
      json['umpires'],
      (Object? v) => MatchPlayer.fromJson(asMap(v, key: 'umpires')),
    ),
    scorers: asListOrEmpty(
      json['scorers'],
      (Object? v) => MatchPlayer.fromJson(asMap(v, key: 'scorers')),
    ),
  );

  JsonMap toJson() => <String, dynamic>{
    'umpires': umpires.map((MatchPlayer p) => p.toJson()).toList(growable: false),
    'scorers': scorers.map((MatchPlayer p) => p.toJson()).toList(growable: false),
  };

  bool get isEmpty => umpires.isEmpty && scorers.isEmpty;

  String get summary => <String>[
    if (umpires.isNotEmpty) 'Umpires: ${umpires.map((MatchPlayer p) => p.name).join(", ")}',
    if (scorers.isNotEmpty) 'Scorers: ${scorers.map((MatchPlayer p) => p.name).join(", ")}',
  ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is MatchOfficials &&
      listEquals(other.umpires, umpires) &&
      listEquals(other.scorers, scorers);

  @override
  int get hashCode => Object.hash(Object.hashAll(umpires), Object.hashAll(scorers));
}

/// The terms of the game, as the two captains settle them at the toss.
@immutable
class MatchConditions {
  const MatchConditions({
    required this.oversLimit,
    required this.oversPerBowler,
    required this.ground,
    required this.ball,
    this.powerplayOvers = 0,
    this.fieldersOutsidePowerplay = 2,
    this.fieldersOutsideNormal = 5,
    this.fieldersBehindSquareLeg = 2,
    this.targetOversPerHour = 0,
  });

  final int oversLimit;

  /// Most a single bowler may send down. 0 means no limit.
  final int oversPerBowler;
  final GroundType ground;
  final BallType ball;

  /// Overs of fielding restrictions at the start of an innings. 0 for none.
  final int powerplayOvers;

  /// Fielders allowed outside the circle during the powerplay.
  final int fieldersOutsidePowerplay;

  /// Fielders allowed outside the circle for the rest of the innings.
  final int fieldersOutsideNormal;

  /// Fielders allowed behind square on the leg side. Two, in every format.
  final int fieldersBehindSquareLeg;

  /// Overs a side is expected to bowl in an hour. 0 means nobody is counting.
  final int targetOversPerHour;

  factory MatchConditions.fromJson(JsonMap json) => MatchConditions(
    oversLimit: asInt(json['overs_limit'], key: 'overs_limit'),
    oversPerBowler: asInt(json['overs_per_bowler'], key: 'overs_per_bowler'),
    ground: GroundType.fromJson(json['ground'], key: 'ground'),
    ball: BallType.fromJson(json['ball'], key: 'ball'),
    powerplayOvers: asIntOrNull(json['powerplay_overs'], key: 'powerplay_overs') ?? 0,
    fieldersOutsidePowerplay:
        asIntOrNull(json['fielders_outside_powerplay'], key: 'fielders_outside_powerplay') ?? 2,
    fieldersOutsideNormal:
        asIntOrNull(json['fielders_outside_normal'], key: 'fielders_outside_normal') ?? 5,
    fieldersBehindSquareLeg:
        asIntOrNull(json['fielders_behind_square_leg'], key: 'fielders_behind_square_leg') ?? 2,
    targetOversPerHour:
        asIntOrNull(json['target_overs_per_hour'], key: 'target_overs_per_hour') ?? 0,
  );

  JsonMap toJson() => <String, dynamic>{
    'overs_limit': oversLimit,
    'overs_per_bowler': oversPerBowler,
    'ground': ground.toJson(),
    'ball': ball.toJson(),
    'powerplay_overs': powerplayOvers,
    'fielders_outside_powerplay': fieldersOutsidePowerplay,
    'fielders_outside_normal': fieldersOutsideNormal,
    'fielders_behind_square_leg': fieldersBehindSquareLeg,
    'target_overs_per_hour': targetOversPerHour,
  };

  /// How many fielders may be outside the circle right now.
  int fieldersAllowedOutside({required bool inPowerplay}) =>
      inPowerplay ? fieldersOutsidePowerplay : fieldersOutsideNormal;

  /// A fifth of the innings each, rounded up: 20 overs gives 4, 50 gives 10.
  static int standardOversPerBowler(int overs) {
    final int value = (overs + 4) ~/ 5;
    return value < 1 ? 1 : value;
  }

  /// The powerplay most competitions use at each length.
  static int standardPowerplay(int overs) {
    if (overs <= 5) return 0;
    if (overs <= 10) return 2;
    if (overs <= 20) return 6;
    if (overs <= 40) return 8;
    return 10;
  }

  static MatchConditions standard({required int overs}) {
    final int limit = overs < 1 ? 1 : overs;
    return MatchConditions(
      oversLimit: limit,
      oversPerBowler: standardOversPerBowler(limit),
      ground: GroundType.open,
      ball: BallType.white,
      powerplayOvers: standardPowerplay(limit),
    );
  }

  /// "20 overs · 4 per bowler · white leather · open ground"
  String get summary {
    final String perBowler = oversPerBowler == 0 ? 'no bowler limit' : '$oversPerBowler per bowler';
    final StringBuffer out = StringBuffer(
      '$oversLimit overs · $perBowler · ${ball.label.toLowerCase()} · '
      '${ground.label.toLowerCase()}',
    );
    if (powerplayOvers > 0) out.write(' · $powerplayOvers over powerplay');
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is MatchConditions &&
      other.oversLimit == oversLimit &&
      other.oversPerBowler == oversPerBowler &&
      other.ground == ground &&
      other.ball == ball &&
      other.powerplayOvers == powerplayOvers &&
      other.fieldersOutsidePowerplay == fieldersOutsidePowerplay &&
      other.fieldersOutsideNormal == fieldersOutsideNormal &&
      other.fieldersBehindSquareLeg == fieldersBehindSquareLeg &&
      other.targetOversPerHour == targetOversPerHour;

  @override
  int get hashCode => Object.hash(
    oversLimit,
    oversPerBowler,
    ground,
    ball,
    powerplayOvers,
    fieldersOutsidePowerplay,
    fieldersOutsideNormal,
    fieldersBehindSquareLeg,
    targetOversPerHour,
  );
}

/// A player on a team sheet — a Fishers member, or a guest with a name only.
@immutable
class MatchPlayer {
  const MatchPlayer({required this.id, required this.name, this.batsLeft = false});

  final String id;
  final String name;

  /// Left-handers mirror the field, so the wagon wheel has to know.
  final bool batsLeft;

  factory MatchPlayer.fromJson(JsonMap json) => MatchPlayer(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    batsLeft: asBoolOrNull(json['bats_left'], key: 'bats_left') ?? false,
  );

  JsonMap toJson() => <String, dynamic>{'id': id, 'name': name, 'bats_left': batsLeft};

  @override
  bool operator ==(Object other) =>
      other is MatchPlayer && other.id == id && other.name == name && other.batsLeft == batsLeft;

  @override
  int get hashCode => Object.hash(id, name, batsLeft);
}

/// Where the ball went. `angle` is degrees clockwise from straight down the
/// ground past the bowler, as struck.
@immutable
class ShotRecord {
  const ShotRecord({required this.angle, required this.kind, this.reach = 0.6});

  final int angle;
  final ShotKind kind;

  /// 0 at the stumps, 1 at the rope.
  final double reach;

  factory ShotRecord.fromJson(JsonMap json) => ShotRecord(
    angle: asInt(json['angle'], key: 'angle'),
    kind: ShotKind.fromJson(json['kind'], key: 'kind'),
    reach: asDoubleOrNull(json['reach'], key: 'reach') ?? 0.6,
  );

  JsonMap toJson() => <String, dynamic>{'angle': angle, 'kind': kind.toJson(), 'reach': reach};

  @override
  bool operator ==(Object other) =>
      other is ShotRecord && other.angle == angle && other.kind == kind && other.reach == reach;

  @override
  int get hashCode => Object.hash(angle, kind, reach);
}

// MARK: - Event kinds (internally tagged `type`, nested under ScoringEvent.kind)

/// One thing that happened, as the append-only log records it.
///
/// Swift models this as an enum with associated values and a hand-written
/// `Codable`; Dart gets a sealed class with the same `type` tag and the same
/// keys, so the two produce byte-identical payloads.
@immutable
sealed class ScoringEventKind {
  const ScoringEventKind();

  String get typeName;

  /// The keys this kind writes, beside `type`.
  JsonMap encodeFields();

  JsonMap toJson() => <String, dynamic>{'type': typeName, ...encodeFields()};

  factory ScoringEventKind.fromJson(JsonMap json) {
    final String type = asString(json['type'], key: 'type');
    return switch (type) {
      'match_prepared' => MatchPrepared(
        oversLimit: asInt(json['overs_limit'], key: 'overs_limit'),
        homeName: asString(json['home_name'], key: 'home_name'),
        awayName: asString(json['away_name'], key: 'away_name'),
      ),
      'toss_recorded' => TossRecorded(
        winner: MatchSide.fromJson(json['winner'], key: 'winner'),
        decision: TossDecision.fromJson(json['decision'], key: 'decision'),
      ),
      'xi_selected' => XiSelected(
        side: MatchSide.fromJson(json['side'], key: 'side'),
        players: asList(
          json['players'],
          (Object? v) => MatchPlayer.fromJson(asMap(v, key: 'players')),
        ),
        captainId: asUuidOrNull(json['captain_id'], key: 'captain_id'),
        keeperId: asUuidOrNull(json['keeper_id'], key: 'keeper_id'),
      ),
      'innings_started' => InningsStarted(
        inningsIndex: asInt(json['innings_index'], key: 'innings_index'),
        batting: MatchSide.fromJson(json['batting'], key: 'batting'),
        strikerId: asUuid(json['striker_id'], key: 'striker_id'),
        nonStrikerId: asUuid(json['non_striker_id'], key: 'non_striker_id'),
        bowlerId: asUuid(json['bowler_id'], key: 'bowler_id'),
        superOver: asBoolOrNull(json['super_over'], key: 'super_over') ?? false,
      ),
      'delivery_recorded' => DeliveryRecorded(
        runs: asInt(json['runs'], key: 'runs'),
        isLegal: asBool(json['is_legal'], key: 'is_legal'),
        isBoundaryFour: asBool(json['is_boundary_four'], key: 'is_boundary_four'),
        isBoundarySix: asBool(json['is_boundary_six'], key: 'is_boundary_six'),
        shot: json['shot'] == null ? null : ShotRecord.fromJson(asMap(json['shot'], key: 'shot')),
      ),
      'extras_recorded' => ExtrasRecorded(
        kind: ExtraKind.fromJson(json['kind'], key: 'kind'),
        runs: asIntOrNull(json['runs'], key: 'runs') ?? 0,
        boundary: asBoolOrNull(json['boundary'], key: 'boundary') ?? false,
        offTheBat: asBoolOrNull(json['off_the_bat'], key: 'off_the_bat') ?? false,
        shot: json['shot'] == null ? null : ShotRecord.fromJson(asMap(json['shot'], key: 'shot')),
      ),
      'overs_revised' => OversRevised(
        inningsIndex: asInt(json['innings_index'], key: 'innings_index'),
        overs: asInt(json['overs'], key: 'overs'),
      ),
      'conditions_proposed' => ConditionsProposed(
        conditions: MatchConditions.fromJson(asMap(json['conditions'], key: 'conditions')),
        by: MatchSide.fromJson(json['by'], key: 'by'),
        byName: asString(json['by_name'], key: 'by_name'),
      ),
      'conditions_agreed' => ConditionsAgreed(
        side: MatchSide.fromJson(json['side'], key: 'side'),
        captainName: asString(json['captain_name'], key: 'captain_name'),
      ),
      'officials_appointed' => OfficialsAppointed(
        officials: MatchOfficials.fromJson(asMap(json['officials'], key: 'officials')),
      ),
      'batter_resumed' => BatterResumed(
        batterId: asUuid(json['batter_id'], key: 'batter_id'),
        replacingId: asUuidOrNull(json['replacing_id'], key: 'replacing_id'),
      ),
      'player_of_the_match' => PlayerOfTheMatch(
        playerId: asUuid(json['player_id'], key: 'player_id'),
      ),
      'penalty_runs' => PenaltyRuns(
        runs: asInt(json['runs'], key: 'runs'),
        reason: asString(json['reason'], key: 'reason'),
        toSide: MatchSide.fromJsonOrNull(json['to_side']),
      ),
      'field_set' => FieldSet(
        outsideCircle: asInt(json['outside_circle'], key: 'outside_circle'),
        behindSquareLeg: asInt(json['behind_square_leg'], key: 'behind_square_leg'),
      ),
      'wicket_recorded' => WicketRecorded(
        batterId: asUuid(json['batter_id'], key: 'batter_id'),
        kind: DismissalKind.fromJson(json['kind'], key: 'kind'),
        fielderId: asUuidOrNull(json['fielder_id'], key: 'fielder_id'),
        newBatterId: asUuidOrNull(json['new_batter_id'], key: 'new_batter_id'),
        runs: asIntOrNull(json['runs'], key: 'runs') ?? 0,
        onExtra: asBoolOrNull(json['on_extra'], key: 'on_extra') ?? false,
      ),
      'bowler_changed' => BowlerChanged(bowlerId: asUuid(json['bowler_id'], key: 'bowler_id')),
      'innings_completed' => const InningsCompleted(),
      'match_completed' => MatchCompleted(
        winner: MatchSide.fromJsonOrNull(json['winner']),
        margin: asString(json['margin'], key: 'margin'),
      ),
      'match_abandoned' => MatchAbandoned(reason: asString(json['reason'], key: 'reason')),
      'undo_last' => const UndoLast(),
      _ => throw JsonDecodeException('Unknown event type $type', key: 'type', value: type),
    };
  }
}

@immutable
class MatchPrepared extends ScoringEventKind {
  const MatchPrepared({required this.oversLimit, required this.homeName, required this.awayName});

  final int oversLimit;
  final String homeName;
  final String awayName;

  @override
  String get typeName => 'match_prepared';

  @override
  JsonMap encodeFields() => <String, dynamic>{
    'overs_limit': oversLimit,
    'home_name': homeName,
    'away_name': awayName,
  };

  @override
  bool operator ==(Object other) =>
      other is MatchPrepared &&
      other.oversLimit == oversLimit &&
      other.homeName == homeName &&
      other.awayName == awayName;

  @override
  int get hashCode => Object.hash(typeName, oversLimit, homeName, awayName);
}

@immutable
class TossRecorded extends ScoringEventKind {
  const TossRecorded({required this.winner, required this.decision});

  final MatchSide winner;
  final TossDecision decision;

  @override
  String get typeName => 'toss_recorded';

  @override
  JsonMap encodeFields() => <String, dynamic>{
    'winner': winner.toJson(),
    'decision': decision.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is TossRecorded && other.winner == winner && other.decision == decision;

  @override
  int get hashCode => Object.hash(typeName, winner, decision);
}

@immutable
class XiSelected extends ScoringEventKind {
  const XiSelected({required this.side, required this.players, this.captainId, this.keeperId});

  final MatchSide side;
  final List<MatchPlayer> players;
  final String? captainId;
  final String? keeperId;

  @override
  String get typeName => 'xi_selected';

  /// `encodeIfPresent` on iOS: a nil captain leaves the key out entirely.
  @override
  JsonMap encodeFields() => compactJson(<String, dynamic>{
    'side': side.toJson(),
    'players': players.map((MatchPlayer p) => p.toJson()).toList(growable: false),
    'captain_id': captainId,
    'keeper_id': keeperId,
  });

  @override
  bool operator ==(Object other) =>
      other is XiSelected &&
      other.side == side &&
      listEquals(other.players, players) &&
      other.captainId == captainId &&
      other.keeperId == keeperId;

  @override
  int get hashCode => Object.hash(typeName, side, Object.hashAll(players), captainId, keeperId);
}

@immutable
class InningsStarted extends ScoringEventKind {
  const InningsStarted({
    required this.inningsIndex,
    required this.batting,
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    this.superOver = false,
  });

  final int inningsIndex;
  final MatchSide batting;
  final String strikerId;
  final String nonStrikerId;
  final String bowlerId;
  final bool superOver;

  @override
  String get typeName => 'innings_started';

  @override
  JsonMap encodeFields() => <String, dynamic>{
    'innings_index': inningsIndex,
    'batting': batting.toJson(),
    'striker_id': strikerId,
    'non_striker_id': nonStrikerId,
    'bowler_id': bowlerId,
    'super_over': superOver,
  };

  @override
  bool operator ==(Object other) =>
      other is InningsStarted &&
      other.inningsIndex == inningsIndex &&
      other.batting == batting &&
      other.strikerId == strikerId &&
      other.nonStrikerId == nonStrikerId &&
      other.bowlerId == bowlerId &&
      other.superOver == superOver;

  @override
  int get hashCode =>
      Object.hash(typeName, inningsIndex, batting, strikerId, nonStrikerId, bowlerId, superOver);
}

@immutable
class DeliveryRecorded extends ScoringEventKind {
  const DeliveryRecorded({
    required this.runs,
    required this.isLegal,
    required this.isBoundaryFour,
    required this.isBoundarySix,
    this.shot,
  });

  final int runs;
  final bool isLegal;
  final bool isBoundaryFour;
  final bool isBoundarySix;
  final ShotRecord? shot;

  @override
  String get typeName => 'delivery_recorded';

  @override
  JsonMap encodeFields() => compactJson(<String, dynamic>{
    'runs': runs,
    'is_legal': isLegal,
    'is_boundary_four': isBoundaryFour,
    'is_boundary_six': isBoundarySix,
    'shot': shot?.toJson(),
  });

  @override
  bool operator ==(Object other) =>
      other is DeliveryRecorded &&
      other.runs == runs &&
      other.isLegal == isLegal &&
      other.isBoundaryFour == isBoundaryFour &&
      other.isBoundarySix == isBoundarySix &&
      other.shot == shot;

  @override
  int get hashCode => Object.hash(typeName, runs, isLegal, isBoundaryFour, isBoundarySix, shot);
}

/// An extra plus whatever came of the ball. `runs` is what the batters ran (or
/// the boundary), on top of the one-run penalty a wide or no ball carries by
/// itself.
@immutable
class ExtrasRecorded extends ScoringEventKind {
  const ExtrasRecorded({
    required this.kind,
    required this.runs,
    required this.boundary,
    required this.offTheBat,
    this.shot,
  });

  final ExtraKind kind;
  final int runs;
  final bool boundary;
  final bool offTheBat;
  final ShotRecord? shot;

  @override
  String get typeName => 'extras_recorded';

  @override
  JsonMap encodeFields() => compactJson(<String, dynamic>{
    'kind': kind.toJson(),
    'runs': runs,
    'boundary': boundary,
    'off_the_bat': offTheBat,
    'shot': shot?.toJson(),
  });

  @override
  bool operator ==(Object other) =>
      other is ExtrasRecorded &&
      other.kind == kind &&
      other.runs == runs &&
      other.boundary == boundary &&
      other.offTheBat == offTheBat &&
      other.shot == shot;

  @override
  int get hashCode => Object.hash(typeName, kind, runs, boundary, offTheBat, shot);
}

@immutable
class OversRevised extends ScoringEventKind {
  const OversRevised({required this.inningsIndex, required this.overs});

  final int inningsIndex;
  final int overs;

  @override
  String get typeName => 'overs_revised';

  @override
  JsonMap encodeFields() => <String, dynamic>{'innings_index': inningsIndex, 'overs': overs};

  @override
  bool operator ==(Object other) =>
      other is OversRevised && other.inningsIndex == inningsIndex && other.overs == overs;

  @override
  int get hashCode => Object.hash(typeName, inningsIndex, overs);
}

/// One captain sets out the terms. A later proposal clears both agreements.
@immutable
class ConditionsProposed extends ScoringEventKind {
  const ConditionsProposed({required this.conditions, required this.by, required this.byName});

  final MatchConditions conditions;
  final MatchSide by;
  final String byName;

  @override
  String get typeName => 'conditions_proposed';

  @override
  JsonMap encodeFields() => <String, dynamic>{
    'conditions': conditions.toJson(),
    'by': by.toJson(),
    'by_name': byName,
  };

  @override
  bool operator ==(Object other) =>
      other is ConditionsProposed &&
      other.conditions == conditions &&
      other.by == by &&
      other.byName == byName;

  @override
  int get hashCode => Object.hash(typeName, conditions, by, byName);
}

/// A captain accepts the terms. The toss waits for both.
@immutable
class ConditionsAgreed extends ScoringEventKind {
  const ConditionsAgreed({required this.side, required this.captainName});

  final MatchSide side;
  final String captainName;

  @override
  String get typeName => 'conditions_agreed';

  @override
  JsonMap encodeFields() => <String, dynamic>{'side': side.toJson(), 'captain_name': captainName};

  @override
  bool operator ==(Object other) =>
      other is ConditionsAgreed && other.side == side && other.captainName == captainName;

  @override
  int get hashCode => Object.hash(typeName, side, captainName);
}

@immutable
class OfficialsAppointed extends ScoringEventKind {
  const OfficialsAppointed({required this.officials});

  final MatchOfficials officials;

  @override
  String get typeName => 'officials_appointed';

  @override
  JsonMap encodeFields() => <String, dynamic>{'officials': officials.toJson()};

  @override
  bool operator ==(Object other) => other is OfficialsAppointed && other.officials == officials;

  @override
  int get hashCode => Object.hash(typeName, officials);
}

/// A batter who retired hurt comes back in.
@immutable
class BatterResumed extends ScoringEventKind {
  const BatterResumed({required this.batterId, this.replacingId});

  final String batterId;
  final String? replacingId;

  @override
  String get typeName => 'batter_resumed';

  @override
  JsonMap encodeFields() =>
      compactJson(<String, dynamic>{'batter_id': batterId, 'replacing_id': replacingId});

  @override
  bool operator ==(Object other) =>
      other is BatterResumed && other.batterId == batterId && other.replacingId == replacingId;

  @override
  int get hashCode => Object.hash(typeName, batterId, replacingId);
}

@immutable
class PlayerOfTheMatch extends ScoringEventKind {
  const PlayerOfTheMatch({required this.playerId});

  final String playerId;

  @override
  String get typeName => 'player_of_the_match';

  @override
  JsonMap encodeFields() => <String, dynamic>{'player_id': playerId};

  @override
  bool operator ==(Object other) => other is PlayerOfTheMatch && other.playerId == playerId;

  @override
  int get hashCode => Object.hash(typeName, playerId);
}

/// Runs the umpire awards that nobody bowled or ran.
@immutable
class PenaltyRuns extends ScoringEventKind {
  const PenaltyRuns({required this.runs, required this.reason, this.toSide});

  final int runs;
  final String reason;
  final MatchSide? toSide;

  @override
  String get typeName => 'penalty_runs';

  @override
  JsonMap encodeFields() =>
      compactJson(<String, dynamic>{'runs': runs, 'reason': reason, 'to_side': toSide?.toJson()});

  @override
  bool operator ==(Object other) =>
      other is PenaltyRuns &&
      other.runs == runs &&
      other.reason == reason &&
      other.toSide == toSide;

  @override
  int get hashCode => Object.hash(typeName, runs, reason, toSide);
}

/// Where the field is set — the two counts the Laws restrict.
@immutable
class FieldSet extends ScoringEventKind {
  const FieldSet({required this.outsideCircle, required this.behindSquareLeg});

  final int outsideCircle;
  final int behindSquareLeg;

  @override
  String get typeName => 'field_set';

  @override
  JsonMap encodeFields() => <String, dynamic>{
    'outside_circle': outsideCircle,
    'behind_square_leg': behindSquareLeg,
  };

  @override
  bool operator ==(Object other) =>
      other is FieldSet &&
      other.outsideCircle == outsideCircle &&
      other.behindSquareLeg == behindSquareLeg;

  @override
  int get hashCode => Object.hash(typeName, outsideCircle, behindSquareLeg);
}

@immutable
class WicketRecorded extends ScoringEventKind {
  const WicketRecorded({
    required this.batterId,
    required this.kind,
    required this.runs,
    required this.onExtra,
    this.fielderId,
    this.newBatterId,
  });

  final String batterId;
  final DismissalKind kind;
  final String? fielderId;
  final String? newBatterId;
  final int runs;
  final bool onExtra;

  @override
  String get typeName => 'wicket_recorded';

  @override
  JsonMap encodeFields() => compactJson(<String, dynamic>{
    'batter_id': batterId,
    'kind': kind.toJson(),
    'fielder_id': fielderId,
    'new_batter_id': newBatterId,
    'runs': runs,
    'on_extra': onExtra,
  });

  @override
  bool operator ==(Object other) =>
      other is WicketRecorded &&
      other.batterId == batterId &&
      other.kind == kind &&
      other.fielderId == fielderId &&
      other.newBatterId == newBatterId &&
      other.runs == runs &&
      other.onExtra == onExtra;

  @override
  int get hashCode => Object.hash(typeName, batterId, kind, fielderId, newBatterId, runs, onExtra);
}

@immutable
class BowlerChanged extends ScoringEventKind {
  const BowlerChanged({required this.bowlerId});

  final String bowlerId;

  @override
  String get typeName => 'bowler_changed';

  @override
  JsonMap encodeFields() => <String, dynamic>{'bowler_id': bowlerId};

  @override
  bool operator ==(Object other) => other is BowlerChanged && other.bowlerId == bowlerId;

  @override
  int get hashCode => Object.hash(typeName, bowlerId);
}

@immutable
class InningsCompleted extends ScoringEventKind {
  const InningsCompleted();

  @override
  String get typeName => 'innings_completed';

  @override
  JsonMap encodeFields() => <String, dynamic>{};

  @override
  bool operator ==(Object other) => other is InningsCompleted;

  @override
  int get hashCode => typeName.hashCode;
}

@immutable
class MatchCompleted extends ScoringEventKind {
  const MatchCompleted({required this.margin, this.winner});

  final MatchSide? winner;
  final String margin;

  @override
  String get typeName => 'match_completed';

  @override
  JsonMap encodeFields() =>
      compactJson(<String, dynamic>{'winner': winner?.toJson(), 'margin': margin});

  @override
  bool operator ==(Object other) =>
      other is MatchCompleted && other.winner == winner && other.margin == margin;

  @override
  int get hashCode => Object.hash(typeName, winner, margin);
}

/// Called off, with no result. Distinct from [MatchCompleted]: a game stopped
/// by rain is not a win for anybody, and the scorecard has to say so rather
/// than inventing a margin.
@immutable
class MatchAbandoned extends ScoringEventKind {
  const MatchAbandoned({required this.reason});

  final String reason;

  @override
  String get typeName => 'match_abandoned';

  @override
  JsonMap encodeFields() => <String, dynamic>{'reason': reason};

  @override
  bool operator ==(Object other) => other is MatchAbandoned && other.reason == reason;

  @override
  int get hashCode => Object.hash(typeName, reason);
}

@immutable
class UndoLast extends ScoringEventKind {
  const UndoLast();

  @override
  String get typeName => 'undo_last';

  @override
  JsonMap encodeFields() => <String, dynamic>{};

  @override
  bool operator ==(Object other) => other is UndoLast;

  @override
  int get hashCode => typeName.hashCode;
}

@immutable
class ScoringEvent {
  const ScoringEvent({required this.clientEventId, required this.seq, required this.kind, this.at});

  final String clientEventId;
  final int seq;
  final ScoringEventKind kind;

  /// When the scorer tapped it. The over rate is only tracked for events that
  /// carry one, so an older log still replays without it.
  final DateTime? at;

  String get id => clientEventId;

  factory ScoringEvent.fromJson(JsonMap json) => ScoringEvent(
    clientEventId: asUuid(json['client_event_id'], key: 'client_event_id'),
    seq: asInt(json['seq'], key: 'seq'),
    kind: ScoringEventKind.fromJson(asMap(json['kind'], key: 'kind')),
    at: asDateOrNull(json['at'], key: 'at'),
  );

  JsonMap toJson() => compactJson(<String, dynamic>{
    'client_event_id': clientEventId,
    'seq': seq,
    'kind': kind.toJson(),
    'at': encodeDateOrNull(at),
  });

  @override
  bool operator ==(Object other) =>
      other is ScoringEvent &&
      other.clientEventId == clientEventId &&
      other.seq == seq &&
      other.kind == kind &&
      other.at == at;

  @override
  int get hashCode => Object.hash(clientEventId, seq, kind, at);
}

// MARK: - Stats / state

@immutable
class BatterStats {
  const BatterStats({
    required this.playerId,
    this.runs = 0,
    this.balls = 0,
    this.fours = 0,
    this.sixes = 0,
    this.out = false,
    this.dismissal,
    this.retiredHurt = false,
    this.bowlerId,
    this.fielderId,
  });

  final String playerId;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final bool out;
  final DismissalKind? dismissal;

  /// Off the field hurt, not out, and eligible to resume.
  final bool retiredHurt;
  final String? bowlerId;
  final String? fielderId;

  String get id => playerId;

  factory BatterStats.fromJson(JsonMap json) => BatterStats(
    playerId: asUuid(json['player_id'], key: 'player_id'),
    runs: asInt(json['runs'], key: 'runs'),
    balls: asInt(json['balls'], key: 'balls'),
    fours: asInt(json['fours'], key: 'fours'),
    sixes: asInt(json['sixes'], key: 'sixes'),
    out: asBool(json['out'], key: 'out'),
    dismissal: DismissalKind.fromJsonOrNull(json['dismissal']),
    retiredHurt: asBoolOrNull(json['retired_hurt'], key: 'retired_hurt') ?? false,
    bowlerId: asUuidOrNull(json['bowler_id'], key: 'bowler_id'),
    fielderId: asUuidOrNull(json['fielder_id'], key: 'fielder_id'),
  );

  JsonMap toJson() => <String, dynamic>{
    'player_id': playerId,
    'runs': runs,
    'balls': balls,
    'fours': fours,
    'sixes': sixes,
    'out': out,
    'dismissal': dismissal?.toJson(),
    'retired_hurt': retiredHurt,
    'bowler_id': bowlerId,
    'fielder_id': fielderId,
  };

  double get strikeRate => balls == 0 ? 0 : runs * 100.0 / balls;

  /// Leaves the rest of the order off the card as "did not bat".
  bool get hasBatted => balls > 0 || runs > 0 || out || retiredHurt;

  /// Can still come back to the crease.
  bool get canResume => retiredHurt && !out;

  @override
  bool operator ==(Object other) =>
      other is BatterStats &&
      other.playerId == playerId &&
      other.runs == runs &&
      other.balls == balls &&
      other.fours == fours &&
      other.sixes == sixes &&
      other.out == out &&
      other.dismissal == dismissal &&
      other.retiredHurt == retiredHurt &&
      other.bowlerId == bowlerId &&
      other.fielderId == fielderId;

  @override
  int get hashCode => Object.hash(
    playerId,
    runs,
    balls,
    fours,
    sixes,
    out,
    dismissal,
    retiredHurt,
    bowlerId,
    fielderId,
  );
}

@immutable
class BowlerStats {
  const BowlerStats({
    required this.playerId,
    this.balls = 0,
    this.runs = 0,
    this.wickets = 0,
    this.maidens = 0,
    this.currentOverRuns = 0,
    this.wides = 0,
    this.noBalls = 0,
  });

  final String playerId;
  final int balls;
  final int runs;
  final int wickets;
  final int maidens;
  final int currentOverRuns;
  final int wides;
  final int noBalls;

  String get id => playerId;

  factory BowlerStats.fromJson(JsonMap json) => BowlerStats(
    playerId: asUuid(json['player_id'], key: 'player_id'),
    balls: asInt(json['balls'], key: 'balls'),
    runs: asInt(json['runs'], key: 'runs'),
    wickets: asInt(json['wickets'], key: 'wickets'),
    maidens: asInt(json['maidens'], key: 'maidens'),
    currentOverRuns: asIntOrNull(json['current_over_runs'], key: 'current_over_runs') ?? 0,
    wides: asIntOrNull(json['wides'], key: 'wides') ?? 0,
    noBalls: asIntOrNull(json['no_balls'], key: 'no_balls') ?? 0,
  );

  JsonMap toJson() => <String, dynamic>{
    'player_id': playerId,
    'balls': balls,
    'runs': runs,
    'wickets': wickets,
    'maidens': maidens,
    'current_over_runs': currentOverRuns,
    'wides': wides,
    'no_balls': noBalls,
  };

  String get oversDisplay => '${balls ~/ 6}.${balls % 6}';

  double get economy => balls == 0 ? 0 : runs * 6.0 / balls;

  /// "4.0-1-22-2", the way a bowling card always reads.
  String get figures => '$oversDisplay-$maidens-$runs-$wickets';

  @override
  bool operator ==(Object other) =>
      other is BowlerStats &&
      other.playerId == playerId &&
      other.balls == balls &&
      other.runs == runs &&
      other.wickets == wickets &&
      other.maidens == maidens &&
      other.currentOverRuns == currentOverRuns &&
      other.wides == wides &&
      other.noBalls == noBalls;

  @override
  int get hashCode =>
      Object.hash(playerId, balls, runs, wickets, maidens, currentOverRuns, wides, noBalls);
}

@immutable
class FallOfWicket {
  const FallOfWicket({
    required this.score,
    required this.wickets,
    required this.batterId,
    required this.overBall,
    this.partnershipRuns = 0,
    this.partnershipBalls = 0,
  });

  final int score;
  final int wickets;
  final String batterId;
  final String overBall;
  final int partnershipRuns;
  final int partnershipBalls;

  factory FallOfWicket.fromJson(JsonMap json) => FallOfWicket(
    score: asInt(json['score'], key: 'score'),
    wickets: asInt(json['wickets'], key: 'wickets'),
    batterId: asUuid(json['batter_id'], key: 'batter_id'),
    overBall: asString(json['over_ball'], key: 'over_ball'),
    partnershipRuns: asIntOrNull(json['partnership_runs'], key: 'partnership_runs') ?? 0,
    partnershipBalls: asIntOrNull(json['partnership_balls'], key: 'partnership_balls') ?? 0,
  );

  JsonMap toJson() => <String, dynamic>{
    'score': score,
    'wickets': wickets,
    'batter_id': batterId,
    'over_ball': overBall,
    'partnership_runs': partnershipRuns,
    'partnership_balls': partnershipBalls,
  };

  @override
  bool operator ==(Object other) =>
      other is FallOfWicket &&
      other.score == score &&
      other.wickets == wickets &&
      other.batterId == batterId &&
      other.overBall == overBall &&
      other.partnershipRuns == partnershipRuns &&
      other.partnershipBalls == partnershipBalls;

  @override
  int get hashCode =>
      Object.hash(score, wickets, batterId, overBall, partnershipRuns, partnershipBalls);
}

@immutable
class DeliveryRecord {
  const DeliveryRecord({
    required this.over,
    required this.ballInOver,
    required this.label,
    required this.runs,
    required this.isLegal,
    required this.isWicket,
    this.batterId,
    this.bowlerId,
    this.shot,
  });

  final int over;
  final int ballInOver;
  final String label;
  final int runs;
  final bool isLegal;
  final bool isWicket;

  /// Who was on strike — the wagon wheel is drawn per batter.
  final String? batterId;
  final String? bowlerId;
  final ShotRecord? shot;

  String get id => '$over.$ballInOver-$label-$runs';

  factory DeliveryRecord.fromJson(JsonMap json) => DeliveryRecord(
    over: asInt(json['over'], key: 'over'),
    ballInOver: asInt(json['ball_in_over'], key: 'ball_in_over'),
    label: asString(json['label'], key: 'label'),
    runs: asInt(json['runs'], key: 'runs'),
    isLegal: asBool(json['is_legal'], key: 'is_legal'),
    isWicket: asBool(json['is_wicket'], key: 'is_wicket'),
    batterId: asUuidOrNull(json['batter_id'], key: 'batter_id'),
    bowlerId: asUuidOrNull(json['bowler_id'], key: 'bowler_id'),
    shot: json['shot'] == null ? null : ShotRecord.fromJson(asMap(json['shot'], key: 'shot')),
  );

  JsonMap toJson() => <String, dynamic>{
    'over': over,
    'ball_in_over': ballInOver,
    'label': label,
    'runs': runs,
    'is_legal': isLegal,
    'is_wicket': isWicket,
    'batter_id': batterId,
    'bowler_id': bowlerId,
    'shot': shot?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is DeliveryRecord &&
      other.over == over &&
      other.ballInOver == ballInOver &&
      other.label == label &&
      other.runs == runs &&
      other.isLegal == isLegal &&
      other.isWicket == isWicket &&
      other.batterId == batterId &&
      other.bowlerId == bowlerId &&
      other.shot == shot;

  @override
  int get hashCode =>
      Object.hash(over, ballInOver, label, runs, isLegal, isWicket, batterId, bowlerId, shot);
}

@immutable
class InningsState {
  const InningsState({
    this.index = 0,
    this.batting = MatchSide.home,
    this.bowling = MatchSide.away,
    this.runs = 0,
    this.wickets = 0,
    this.legalBalls = 0,
    this.extras = 0,
    this.batters = const <BatterStats>[],
    this.bowlers = const <BowlerStats>[],
    this.fall = const <FallOfWicket>[],
    this.deliveries = const <DeliveryRecord>[],
    this.strikerId,
    this.nonStrikerId,
    this.bowlerId,
    this.complete = false,
    this.ballsInCurrentOver = 0,
    this.wides = 0,
    this.noBalls = 0,
    this.byes = 0,
    this.legByes = 0,
    this.penalties = 0,
    this.partnershipRuns = 0,
    this.partnershipBalls = 0,
    this.wicketsAllowed = 10,
    this.oversAvailable = 0,
    this.lastOverBowler,
    this.freeHit = false,
    this.superOver = false,
    this.powerplayOvers = 0,
    this.fieldersOutside,
    this.fieldersBehindSquareLeg,
    this.penaltyRunsAwarded = 0,
    this.startedAt,
    this.lastBallAt,
  });

  final int index;
  final MatchSide batting;
  final MatchSide bowling;
  final int runs;
  final int wickets;
  final int legalBalls;
  final int extras;
  final List<BatterStats> batters;
  final List<BowlerStats> bowlers;
  final List<FallOfWicket> fall;
  final List<DeliveryRecord> deliveries;
  final String? strikerId;
  final String? nonStrikerId;
  final String? bowlerId;
  final bool complete;
  final int ballsInCurrentOver;
  final int wides;
  final int noBalls;
  final int byes;
  final int legByes;
  final int penalties;
  final int partnershipRuns;
  final int partnershipBalls;

  /// All out at this many wickets — one fewer than the team sheet.
  final int wicketsAllowed;

  /// Overs this innings actually gets, after any weather reduction.
  final int oversAvailable;

  /// Who bowled the over that just finished — nobody bowls two in a row.
  final String? lastOverBowler;

  /// The next legal delivery is a free hit: only a run out can get them.
  final bool freeHit;

  /// One over a side, two wickets, to break a tie.
  final bool superOver;

  /// Overs of fielding restrictions this innings gets.
  final int powerplayOvers;

  /// Fielders the scorer last recorded outside the circle.
  final int? fieldersOutside;
  final int? fieldersBehindSquareLeg;

  /// Runs added to this innings that nobody scored.
  final int penaltyRunsAwarded;

  /// When the innings started and when the last ball was bowled.
  final DateTime? startedAt;
  final DateTime? lastBallAt;

  factory InningsState.fromJson(JsonMap json) => InningsState(
    index: asInt(json['index'], key: 'index'),
    batting: MatchSide.fromJson(json['batting'], key: 'batting'),
    bowling: MatchSide.fromJson(json['bowling'], key: 'bowling'),
    runs: asInt(json['runs'], key: 'runs'),
    wickets: asInt(json['wickets'], key: 'wickets'),
    legalBalls: asInt(json['legal_balls'], key: 'legal_balls'),
    extras: asInt(json['extras'], key: 'extras'),
    batters: asList(json['batters'], (Object? v) => BatterStats.fromJson(asMap(v, key: 'batters'))),
    bowlers: asList(json['bowlers'], (Object? v) => BowlerStats.fromJson(asMap(v, key: 'bowlers'))),
    fall: asList(json['fall'], (Object? v) => FallOfWicket.fromJson(asMap(v, key: 'fall'))),
    deliveries: asList(
      json['deliveries'],
      (Object? v) => DeliveryRecord.fromJson(asMap(v, key: 'deliveries')),
    ),
    strikerId: asUuidOrNull(json['striker_id'], key: 'striker_id'),
    nonStrikerId: asUuidOrNull(json['non_striker_id'], key: 'non_striker_id'),
    bowlerId: asUuidOrNull(json['bowler_id'], key: 'bowler_id'),
    complete: asBool(json['complete'], key: 'complete'),
    ballsInCurrentOver: asInt(json['balls_in_current_over'], key: 'balls_in_current_over'),
    wides: asIntOrNull(json['wides'], key: 'wides') ?? 0,
    noBalls: asIntOrNull(json['no_balls'], key: 'no_balls') ?? 0,
    byes: asIntOrNull(json['byes'], key: 'byes') ?? 0,
    legByes: asIntOrNull(json['leg_byes'], key: 'leg_byes') ?? 0,
    penalties: asIntOrNull(json['penalties'], key: 'penalties') ?? 0,
    partnershipRuns: asIntOrNull(json['partnership_runs'], key: 'partnership_runs') ?? 0,
    partnershipBalls: asIntOrNull(json['partnership_balls'], key: 'partnership_balls') ?? 0,
    wicketsAllowed: asIntOrNull(json['wickets_allowed'], key: 'wickets_allowed') ?? 10,
    oversAvailable: asIntOrNull(json['overs_available'], key: 'overs_available') ?? 0,
    lastOverBowler: asUuidOrNull(json['last_over_bowler'], key: 'last_over_bowler'),
    freeHit: asBoolOrNull(json['free_hit'], key: 'free_hit') ?? false,
    superOver: asBoolOrNull(json['super_over'], key: 'super_over') ?? false,
    powerplayOvers: asIntOrNull(json['powerplay_overs'], key: 'powerplay_overs') ?? 0,
    fieldersOutside: asIntOrNull(json['fielders_outside'], key: 'fielders_outside'),
    fieldersBehindSquareLeg: asIntOrNull(
      json['fielders_behind_square_leg'],
      key: 'fielders_behind_square_leg',
    ),
    penaltyRunsAwarded: asIntOrNull(json['penalty_runs_awarded'], key: 'penalty_runs_awarded') ?? 0,
    startedAt: asDateOrNull(json['started_at'], key: 'started_at'),
    lastBallAt: asDateOrNull(json['last_ball_at'], key: 'last_ball_at'),
  );

  JsonMap toJson() => <String, dynamic>{
    'index': index,
    'batting': batting.toJson(),
    'bowling': bowling.toJson(),
    'runs': runs,
    'wickets': wickets,
    'legal_balls': legalBalls,
    'extras': extras,
    'batters': batters.map((BatterStats b) => b.toJson()).toList(growable: false),
    'bowlers': bowlers.map((BowlerStats b) => b.toJson()).toList(growable: false),
    'fall': fall.map((FallOfWicket f) => f.toJson()).toList(growable: false),
    'deliveries': deliveries.map((DeliveryRecord d) => d.toJson()).toList(growable: false),
    'striker_id': strikerId,
    'non_striker_id': nonStrikerId,
    'bowler_id': bowlerId,
    'complete': complete,
    'balls_in_current_over': ballsInCurrentOver,
    'wides': wides,
    'no_balls': noBalls,
    'byes': byes,
    'leg_byes': legByes,
    'penalties': penalties,
    'partnership_runs': partnershipRuns,
    'partnership_balls': partnershipBalls,
    'wickets_allowed': wicketsAllowed,
    'overs_available': oversAvailable,
    'last_over_bowler': lastOverBowler,
    'free_hit': freeHit,
    'super_over': superOver,
    'powerplay_overs': powerplayOvers,
    'fielders_outside': fieldersOutside,
    'fielders_behind_square_leg': fieldersBehindSquareLeg,
    'penalty_runs_awarded': penaltyRunsAwarded,
    'started_at': encodeDateOrNull(startedAt),
    'last_ball_at': encodeDateOrNull(lastBallAt),
  };

  /// How long the innings has been going, from the first ball to the last.
  int? get elapsedMinutes {
    final DateTime? from = startedAt;
    final DateTime? to = lastBallAt;
    if (from == null || to == null) return null;
    final int minutes = to.difference(from).inMinutes;
    return minutes > 0 ? minutes : null;
  }

  /// Overs actually bowled per hour so far.
  double? get oversPerHour {
    final int? minutes = elapsedMinutes;
    if (minutes == null) return null;
    return (legalBalls / 6.0) * 60.0 / minutes;
  }

  /// Overs behind the clock — negative when they are ahead of it.
  double? oversBehind({required int target}) {
    final int? minutes = elapsedMinutes;
    if (target <= 0 || minutes == null) return null;
    final double due = minutes / 60.0 * target;
    return due - legalBalls / 6.0;
  }

  /// What the field breaks, if anything. Empty when it is legal, or when the
  /// scorer has not said where the fielders are.
  List<String> fieldingBreaches(MatchConditions conditions) {
    final List<String> breaches = <String>[];
    if (fieldersOutside case final int outside) {
      final int allowed = conditions.fieldersAllowedOutside(inPowerplay: inPowerplay);
      if (outside > allowed) {
        breaches.add(
          '$outside outside the circle — $allowed allowed'
          '${inPowerplay ? " in the powerplay" : ""}',
        );
      }
    }
    if (fieldersBehindSquareLeg case final int behind
        when behind > conditions.fieldersBehindSquareLeg) {
      breaches.add(
        '$behind behind square on the leg side — '
        '${conditions.fieldersBehindSquareLeg} allowed',
      );
    }
    return breaches;
  }

  /// Inside the fielding restrictions.
  bool get inPowerplay => powerplayOvers > 0 && legalBalls < powerplayOvers * 6;

  /// Overs of powerplay still to come, for the banner.
  int get powerplayOversLeft {
    final int total = powerplayOvers * 6;
    if (total <= legalBalls) return 0;
    return (total - legalBalls + 5) ~/ 6;
  }

  /// Total balls this innings gets, or null when no limit is recorded. Zero
  /// means "not set", never "no overs left".
  int? get ballsAllowed => oversAvailable == 0 ? null : oversAvailable * 6;

  /// Balls left, given whatever overs this innings ended up with.
  int get ballsRemaining {
    final int? total = ballsAllowed;
    if (total == null) return 0;
    return total > legalBalls ? total - legalBalls : 0;
  }

  /// Every recorded shot, optionally for one batter — the wagon wheel.
  List<DeliveryRecord> shots({String? batter}) => deliveries
      .where((DeliveryRecord d) => d.shot != null)
      .where((DeliveryRecord d) => batter == null || d.batterId == batter)
      .toList(growable: false);

  String get oversDisplay => '${legalBalls ~/ 6}.${legalBalls % 6}';

  double get runRate => legalBalls == 0 ? 0 : runs * 6.0 / legalBalls;

  bool get isAllOut => wickets >= wicketsAllowed;

  /// The current over's balls, for the strip above the run buttons.
  List<DeliveryRecord> get currentOverBalls {
    final int over = legalBalls ~/ 6;
    final List<DeliveryRecord> fromThisOver = deliveries
        .where((DeliveryRecord d) => d.over == over)
        .toList(growable: false);
    // A maiden's worth is six entries; extras push it past that.
    final int take = fromThisOver.length < 10 ? fromThisOver.length : 10;
    return fromThisOver.sublist(fromThisOver.length - take);
  }

  @override
  bool operator ==(Object other) =>
      other is InningsState &&
      other.index == index &&
      other.batting == batting &&
      other.bowling == bowling &&
      other.runs == runs &&
      other.wickets == wickets &&
      other.legalBalls == legalBalls &&
      other.extras == extras &&
      listEquals(other.batters, batters) &&
      listEquals(other.bowlers, bowlers) &&
      listEquals(other.fall, fall) &&
      listEquals(other.deliveries, deliveries) &&
      other.strikerId == strikerId &&
      other.nonStrikerId == nonStrikerId &&
      other.bowlerId == bowlerId &&
      other.complete == complete &&
      other.ballsInCurrentOver == ballsInCurrentOver &&
      other.wides == wides &&
      other.noBalls == noBalls &&
      other.byes == byes &&
      other.legByes == legByes &&
      other.penalties == penalties &&
      other.partnershipRuns == partnershipRuns &&
      other.partnershipBalls == partnershipBalls &&
      other.wicketsAllowed == wicketsAllowed &&
      other.oversAvailable == oversAvailable &&
      other.lastOverBowler == lastOverBowler &&
      other.freeHit == freeHit &&
      other.superOver == superOver &&
      other.powerplayOvers == powerplayOvers &&
      other.fieldersOutside == fieldersOutside &&
      other.fieldersBehindSquareLeg == fieldersBehindSquareLeg &&
      other.penaltyRunsAwarded == penaltyRunsAwarded &&
      other.startedAt == startedAt &&
      other.lastBallAt == lastBallAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    index,
    batting,
    bowling,
    runs,
    wickets,
    legalBalls,
    extras,
    Object.hashAll(batters),
    Object.hashAll(bowlers),
    Object.hashAll(fall),
    Object.hashAll(deliveries),
    strikerId,
    nonStrikerId,
    bowlerId,
    complete,
    ballsInCurrentOver,
    wides,
    noBalls,
    byes,
    legByes,
    penalties,
    partnershipRuns,
    partnershipBalls,
    wicketsAllowed,
    oversAvailable,
    lastOverBowler,
    freeHit,
    superOver,
    powerplayOvers,
    fieldersOutside,
    fieldersBehindSquareLeg,
    penaltyRunsAwarded,
    startedAt,
    lastBallAt,
  ]);
}

@immutable
class MatchState {
  const MatchState({
    this.status = CricketMatchStatus.scheduled,
    this.oversLimit = 20,
    this.homeName = 'Home',
    this.awayName = 'Away',
    this.tossWinner,
    this.tossDecision,
    this.homeXi = const <String>[],
    this.awayXi = const <String>[],
    this.homeCaptain,
    this.awayCaptain,
    this.homeKeeper,
    this.awayKeeper,
    this.innings = const <InningsState>[],
    this.target,
    this.winner,
    this.margin,
    this.abandoned = false,
    this.lastSeq = 0,
    this.playerNames = const <String, String>{},
    this.leftHanders = const <String>{},
    required this.conditions,
    this.conditionsProposedBy,
    this.agreedHome,
    this.agreedAway,
    this.officials = const MatchOfficials(),
    this.playerOfTheMatch,
    this.superOvers = 0,
    this.pendingPenalties = const <String, int>{},
  });

  /// The empty state a new match starts from.
  factory MatchState.empty({
    int oversLimit = 20,
    String homeName = 'Home',
    String awayName = 'Away',
  }) => MatchState(
    oversLimit: oversLimit,
    homeName: homeName,
    awayName: awayName,
    conditions: MatchConditions.standard(overs: oversLimit),
  );

  final CricketMatchStatus status;
  final int oversLimit;
  final String homeName;
  final String awayName;
  final MatchSide? tossWinner;
  final TossDecision? tossDecision;
  final List<String> homeXi;
  final List<String> awayXi;
  final String? homeCaptain;
  final String? awayCaptain;
  final String? homeKeeper;
  final String? awayKeeper;
  final List<InningsState> innings;
  final int? target;
  final MatchSide? winner;
  final String? margin;

  /// Called off with no result. `winner` is nil either way, so a flag is what
  /// separates "abandoned" from "still being played".
  final bool abandoned;
  final int lastSeq;

  /// Keyed by lower-case UUID string: Rust writes lower-case keys, so the
  /// string form is the one shape both ends agree on.
  final Map<String, String> playerNames;

  /// Lower-case UUID strings of the left-handers, so the wheel mirrors.
  final Set<String> leftHanders;

  /// The terms of the game. [oversLimit] mirrors `conditions.oversLimit`.
  final MatchConditions conditions;
  final MatchSide? conditionsProposedBy;

  /// The captain who agreed, by name — the away captain rarely has an account.
  final String? agreedHome;
  final String? agreedAway;
  final MatchOfficials officials;
  final String? playerOfTheMatch;

  /// How many super overs it has taken so far.
  final int superOvers;

  /// Penalties awarded to a side that has not batted yet, keyed `home`/`away`.
  final Map<String, int> pendingPenalties;

  factory MatchState.fromJson(JsonMap json) {
    final int oversLimit = asInt(json['overs_limit'], key: 'overs_limit');
    return MatchState(
      status: CricketMatchStatus.fromJson(json['status'], key: 'status'),
      oversLimit: oversLimit,
      homeName: asString(json['home_name'], key: 'home_name'),
      awayName: asString(json['away_name'], key: 'away_name'),
      tossWinner: MatchSide.fromJsonOrNull(json['toss_winner']),
      tossDecision: TossDecision.fromJsonOrNull(json['toss_decision']),
      homeXi: asListOrEmpty(json['home_xi'], (Object? v) => asUuid(v, key: 'home_xi')),
      awayXi: asListOrEmpty(json['away_xi'], (Object? v) => asUuid(v, key: 'away_xi')),
      homeCaptain: asUuidOrNull(json['home_captain'], key: 'home_captain'),
      awayCaptain: asUuidOrNull(json['away_captain'], key: 'away_captain'),
      homeKeeper: asUuidOrNull(json['home_keeper'], key: 'home_keeper'),
      awayKeeper: asUuidOrNull(json['away_keeper'], key: 'away_keeper'),
      innings: asListOrEmpty(
        json['innings'],
        (Object? v) => InningsState.fromJson(asMap(v, key: 'innings')),
      ),
      target: asIntOrNull(json['target'], key: 'target'),
      winner: MatchSide.fromJsonOrNull(json['winner']),
      margin: asStringOrNull(json['margin'], key: 'margin'),
      abandoned: asBoolOrNull(json['abandoned'], key: 'abandoned') ?? false,
      lastSeq: asIntOrNull(json['last_seq'], key: 'last_seq') ?? 0,
      playerNames: asStringMap(json['player_names'], key: 'player_names'),
      leftHanders: <String>{
        for (final String id in asListOrEmpty(
          json['left_handers'],
          (Object? v) => asString(v, key: 'left_handers'),
        ))
          id.toLowerCase(),
      },
      conditions: json['conditions'] == null
          ? MatchConditions.standard(overs: oversLimit)
          : MatchConditions.fromJson(asMap(json['conditions'], key: 'conditions')),
      conditionsProposedBy: MatchSide.fromJsonOrNull(json['conditions_proposed_by']),
      agreedHome: asStringOrNull(json['agreed_home'], key: 'agreed_home'),
      agreedAway: asStringOrNull(json['agreed_away'], key: 'agreed_away'),
      officials: json['officials'] == null
          ? const MatchOfficials()
          : MatchOfficials.fromJson(asMap(json['officials'], key: 'officials')),
      playerOfTheMatch: asUuidOrNull(json['player_of_the_match'], key: 'player_of_the_match'),
      superOvers: asIntOrNull(json['super_overs'], key: 'super_overs') ?? 0,
      pendingPenalties: asIntMap(json['pending_penalties'], key: 'pending_penalties'),
    );
  }

  /// iOS declares `abandoned` outside `CodingKeys`, so Swift's synthesised
  /// encoder does **not** write it. This one does not either: the key is read
  /// when the server sends it and never sent back, which keeps a round trip
  /// byte-compatible with what iOS posts.
  JsonMap toJson() => <String, dynamic>{
    'status': status.toJson(),
    'overs_limit': oversLimit,
    'home_name': homeName,
    'away_name': awayName,
    'toss_winner': tossWinner?.toJson(),
    'toss_decision': tossDecision?.toJson(),
    'home_xi': homeXi,
    'away_xi': awayXi,
    'home_captain': homeCaptain,
    'away_captain': awayCaptain,
    'home_keeper': homeKeeper,
    'away_keeper': awayKeeper,
    'innings': innings.map((InningsState i) => i.toJson()).toList(growable: false),
    'target': target,
    'winner': winner?.toJson(),
    'margin': margin,
    'last_seq': lastSeq,
    'player_names': playerNames,
    'left_handers': leftHanders.toList(growable: false),
    'conditions': conditions.toJson(),
    'conditions_proposed_by': conditionsProposedBy?.toJson(),
    'agreed_home': agreedHome,
    'agreed_away': agreedAway,
    'officials': officials.toJson(),
    'player_of_the_match': playerOfTheMatch,
    'super_overs': superOvers,
    'pending_penalties': pendingPenalties,
  };

  // MARK: Names

  static String nameKey(String id) => uuidKey(id);

  String nameForPlayer(String id) =>
      playerNames[nameKey(id)] ?? (id.length >= 8 ? id.substring(0, 8) : id);

  List<MatchPlayer> playersFor(MatchSide side) => <MatchPlayer>[
    for (final String id in xi(side))
      MatchPlayer(id: id, name: nameForPlayer(id), batsLeft: batsLeft(id)),
  ];

  /// Both captains have signed off the terms, so the game can start.
  bool get conditionsAgreed => agreedHome != null && agreedAway != null;

  /// Penalties waiting for a side that has not batted yet.
  int pendingPenalty(MatchSide side) => pendingPenalties[side.wire] ?? 0;

  /// The scores are level and the match is over: it needs a super over.
  bool get needsASuperOver =>
      status == CricketMatchStatus.complete &&
      winner == null &&
      innings.length >= 2 &&
      innings.length.isEven;

  /// Which side bats first in the super over: whoever batted second last.
  MatchSide? get superOverFirstBatting => innings.isEmpty ? null : innings.last.batting;

  /// Anyone appointed to stand or to score — they may score the match.
  bool isOfficial(String id) =>
      officials.umpires.any((MatchPlayer p) => p.id == id) ||
      officials.scorers.any((MatchPlayer p) => p.id == id);

  /// Which side still has to agree, for the screen that chases them.
  List<MatchSide> get awaitingAgreement => <MatchSide>[
    if (agreedHome == null) MatchSide.home,
    if (agreedAway == null) MatchSide.away,
  ];

  String? agreedName(MatchSide side) => side == MatchSide.home ? agreedHome : agreedAway;

  /// Overs this bowler may still send down, or null when there is no limit.
  int? oversLeftForBowler(String bowler) {
    if (conditions.oversPerBowler <= 0) return null;
    int bowled = 0;
    for (final BowlerStats stats in currentInnings?.bowlers ?? const <BowlerStats>[]) {
      if (stats.playerId == bowler) {
        bowled = stats.balls ~/ 6;
        break;
      }
    }
    return conditions.oversPerBowler > bowled ? conditions.oversPerBowler - bowled : 0;
  }

  /// Why this bowler cannot come on, if they cannot.
  String? bowlerUnavailableReason(String bowler) {
    final InningsState? inn = currentInnings;
    if (inn == null) return null;
    if (inn.lastOverBowler == bowler && xi(inn.bowling).length > 1) {
      return 'bowled the last over';
    }
    if (oversLeftForBowler(bowler) case 0) {
      return 'has bowled their ${conditions.oversPerBowler} overs';
    }
    return null;
  }

  bool batsLeft(String id) => leftHanders.contains(nameKey(id));

  /// Where a shot went, named the way the batter's own field is laid out.
  String? regionFor(DeliveryRecord delivery) {
    final ShotRecord? shot = delivery.shot;
    if (shot == null) return null;
    final bool left = delivery.batterId == null ? false : batsLeft(delivery.batterId!);
    return cricketRegion(angle: shot.angle, batsLeft: left);
  }

  List<String> xi(MatchSide side) => side == MatchSide.home ? homeXi : awayXi;

  String nameForSide(MatchSide side) => side == MatchSide.home ? homeName : awayName;

  // MARK: Derived

  InningsState? get currentInnings => innings.isEmpty ? null : innings.last;

  static String oversBallsDisplay(int legalBalls) => '${legalBalls ~/ 6}.${legalBalls % 6}';

  double get currentRunRate => currentInnings?.runRate ?? 0;

  int? get ballsRemaining => currentInnings?.ballsRemaining;

  int? get runsNeeded {
    final int? target = this.target;
    final InningsState? inn = currentInnings;
    if (target == null || inn == null || inn.index < 1) return null;
    return target > inn.runs ? target - inn.runs : 0;
  }

  double? get requiredRunRate {
    final int? needed = runsNeeded;
    final int? remaining = ballsRemaining;
    if (needed == null || remaining == null) return null;
    if (remaining <= 0) return 0;
    return needed * 6.0 / remaining;
  }

  /// "Hemel need 42 from 30 balls" — the line every scoreboard carries.
  String? get chaseLine {
    final InningsState? inn = currentInnings;
    if (inn == null || inn.index < 1 || inn.complete) return null;
    final int? needed = runsNeeded;
    final int? remaining = ballsRemaining;
    if (needed == null || remaining == null) return null;
    return '${nameForSide(inn.batting)} need $needed from $remaining '
        'ball${remaining == 1 ? "" : "s"}';
  }

  /// "c Smith b Jones", "run out (Patel)", "not out".
  String dismissalText(BatterStats batter) {
    if (batter.retiredHurt && !batter.out) return 'retired hurt';
    if (!batter.out) return batter.hasBatted ? 'not out' : 'did not bat';
    final String? bowler = batter.bowlerId == null ? null : nameForPlayer(batter.bowlerId!);
    final String? fielder = batter.fielderId == null ? null : nameForPlayer(batter.fielderId!);
    return switch (batter.dismissal) {
      DismissalKind.bowled => bowler == null ? 'bowled' : 'b $bowler',
      DismissalKind.caught =>
        fielder != null && bowler != null
            ? 'c $fielder b $bowler'
            : (bowler != null ? 'c & b $bowler' : 'caught'),
      DismissalKind.lbw => bowler == null ? 'lbw' : 'lbw b $bowler',
      DismissalKind.stumped =>
        fielder != null && bowler != null
            ? 'st $fielder b $bowler'
            : (bowler != null ? 'st b $bowler' : 'stumped'),
      DismissalKind.hitWicket => bowler == null ? 'hit wicket' : 'hit wicket b $bowler',
      DismissalKind.runOut => fielder == null ? 'run out' : 'run out ($fielder)',
      DismissalKind.retired => 'retired out',
      DismissalKind.retiredHurt => 'retired hurt',
      DismissalKind.other || null => 'out',
    };
  }

  String scoreLine() {
    final InningsState? inn = currentInnings;
    if (inn == null) return '$homeName v $awayName';
    return '${nameForSide(inn.batting)} ${inn.runs}/${inn.wickets} (${inn.oversDisplay})';
  }

  @override
  bool operator ==(Object other) =>
      other is MatchState &&
      other.status == status &&
      other.oversLimit == oversLimit &&
      other.homeName == homeName &&
      other.awayName == awayName &&
      other.tossWinner == tossWinner &&
      other.tossDecision == tossDecision &&
      listEquals(other.homeXi, homeXi) &&
      listEquals(other.awayXi, awayXi) &&
      other.homeCaptain == homeCaptain &&
      other.awayCaptain == awayCaptain &&
      other.homeKeeper == homeKeeper &&
      other.awayKeeper == awayKeeper &&
      listEquals(other.innings, innings) &&
      other.target == target &&
      other.winner == winner &&
      other.margin == margin &&
      other.abandoned == abandoned &&
      other.lastSeq == lastSeq &&
      mapEquals(other.playerNames, playerNames) &&
      setEquals(other.leftHanders, leftHanders) &&
      other.conditions == conditions &&
      other.conditionsProposedBy == conditionsProposedBy &&
      other.agreedHome == agreedHome &&
      other.agreedAway == agreedAway &&
      other.officials == officials &&
      other.playerOfTheMatch == playerOfTheMatch &&
      other.superOvers == superOvers &&
      mapEquals(other.pendingPenalties, pendingPenalties);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    status,
    oversLimit,
    homeName,
    awayName,
    tossWinner,
    tossDecision,
    Object.hashAll(homeXi),
    Object.hashAll(awayXi),
    homeCaptain,
    awayCaptain,
    homeKeeper,
    awayKeeper,
    Object.hashAll(innings),
    target,
    winner,
    margin,
    abandoned,
    lastSeq,
    conditions,
    conditionsProposedBy,
    agreedHome,
    agreedAway,
    officials,
    playerOfTheMatch,
    superOvers,
  ]);
}

/// Where the chase stands on Duckworth–Lewis–Stern.
@immutable
class DlsPar {
  const DlsPar({
    required this.par,
    required this.aheadBy,
    required this.target,
    required this.resourcesFirst,
    required this.resourcesSecond,
    required this.resourcesUsed,
    required this.method,
    required this.usedG50,
  });

  final int par;
  final int aheadBy;
  final int target;
  final double resourcesFirst;
  final double resourcesSecond;
  final double resourcesUsed;

  /// `standard_approximation` | `supplied_table`
  final String method;
  final bool usedG50;

  factory DlsPar.fromJson(JsonMap json) => DlsPar(
    par: asInt(json['par'], key: 'par'),
    aheadBy: asInt(json['ahead_by'], key: 'ahead_by'),
    target: asInt(json['target'], key: 'target'),
    resourcesFirst: asDouble(json['resources_first'], key: 'resources_first'),
    resourcesSecond: asDouble(json['resources_second'], key: 'resources_second'),
    resourcesUsed: asDouble(json['resources_used'], key: 'resources_used'),
    method: asString(json['method'], key: 'method'),
    usedG50: asBool(json['used_g50'], key: 'used_g50'),
  );

  JsonMap toJson() => <String, dynamic>{
    'par': par,
    'ahead_by': aheadBy,
    'target': target,
    'resources_first': resourcesFirst,
    'resources_second': resourcesSecond,
    'resources_used': resourcesUsed,
    'method': method,
    'used_g50': usedG50,
  };

  String get methodLabel => method == 'supplied_table'
      ? 'DLS (supplied resource table)'
      : 'DLS (Standard Edition approximation)';

  /// "12 ahead of the DLS par of 84".
  String get summary {
    if (aheadBy == 0) return 'Level with the DLS par of $par';
    return aheadBy > 0
        ? '$aheadBy ahead of the DLS par of $par'
        : '${-aheadBy} behind the DLS par of $par';
  }

  @override
  bool operator ==(Object other) =>
      other is DlsPar &&
      other.par == par &&
      other.aheadBy == aheadBy &&
      other.target == target &&
      other.resourcesFirst == resourcesFirst &&
      other.resourcesSecond == resourcesSecond &&
      other.resourcesUsed == resourcesUsed &&
      other.method == method &&
      other.usedG50 == usedG50;

  @override
  int get hashCode => Object.hash(
    par,
    aheadBy,
    target,
    resourcesFirst,
    resourcesSecond,
    resourcesUsed,
    method,
    usedG50,
  );
}

@immutable
class CricketMatchDto {
  const CricketMatchDto({
    required this.id,
    required this.eventId,
    required this.clubId,
    required this.status,
    required this.oversLimit,
    required this.homeName,
    required this.awayName,
    required this.lastSeq,
    required this.canScore,
    required this.mySides,
    required this.state,
    this.activeScorerUserId,
    this.activeScorerDeviceId,
    this.opponentClubId,
    this.startAt,
    this.myClubSide,
    this.dls,
  });

  final String id;
  final String eventId;
  final String clubId;
  final String status;
  final int oversLimit;
  final String homeName;
  final String awayName;
  final int lastSeq;
  final String? activeScorerUserId;
  final String? activeScorerDeviceId;
  final bool canScore;

  /// The visiting club, when they are on Fishers.
  final String? opponentClubId;

  /// When the fixture is. A club plays the same opposition several times a
  /// season, so the two names alone do not say which match this is.
  final DateTime? startAt;

  /// The side this caller actually plays for. Proposing terms on behalf of the
  /// opposition is something you do because their captain is standing next to
  /// you — never by accident, which is what a hardcoded `.home` was.
  final MatchSide? myClubSide;

  /// Which sides this caller may propose or agree terms for. The scorer at the
  /// ground gets both; a captain gets only their own.
  final List<MatchSide> mySides;
  final DlsPar? dls;
  final MatchState state;

  factory CricketMatchDto.fromJson(JsonMap json) => CricketMatchDto(
    id: asUuid(json['id'], key: 'id'),
    eventId: asUuid(json['event_id'], key: 'event_id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    status: asString(json['status'], key: 'status'),
    oversLimit: asInt(json['overs_limit'], key: 'overs_limit'),
    homeName: asString(json['home_name'], key: 'home_name'),
    awayName: asString(json['away_name'], key: 'away_name'),
    lastSeq: asInt(json['last_seq'], key: 'last_seq'),
    activeScorerUserId: asUuidOrNull(json['active_scorer_user_id'], key: 'active_scorer_user_id'),
    activeScorerDeviceId: asStringOrNull(
      json['active_scorer_device_id'],
      key: 'active_scorer_device_id',
    ),
    canScore: asBoolOrNull(json['can_score'], key: 'can_score') ?? false,
    opponentClubId: asUuidOrNull(json['opponent_club_id'], key: 'opponent_club_id'),
    startAt: asDateOrNull(json['start_at'], key: 'start_at'),
    myClubSide: MatchSide.fromJsonOrNull(json['my_club_side']),
    // Older builds of the API did not send this; an empty list reads as
    // "nothing you may act for", which is the safe way to be wrong.
    mySides: asListOrEmpty(json['my_sides'], (Object? v) => MatchSide.fromJson(v, key: 'my_sides')),
    dls: json['dls'] == null ? null : DlsPar.fromJson(asMap(json['dls'], key: 'dls')),
    state: MatchState.fromJson(asMap(json['state'], key: 'state')),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'event_id': eventId,
    'club_id': clubId,
    'status': status,
    'overs_limit': oversLimit,
    'home_name': homeName,
    'away_name': awayName,
    'last_seq': lastSeq,
    'active_scorer_user_id': activeScorerUserId,
    'active_scorer_device_id': activeScorerDeviceId,
    'can_score': canScore,
    'opponent_club_id': opponentClubId,
    'start_at': encodeDateOrNull(startAt),
    'my_club_side': myClubSide?.toJson(),
    'my_sides': mySides.map((MatchSide s) => s.toJson()).toList(growable: false),
    'dls': dls?.toJson(),
    'state': state.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CricketMatchDto &&
      other.id == id &&
      other.eventId == eventId &&
      other.clubId == clubId &&
      other.status == status &&
      other.oversLimit == oversLimit &&
      other.homeName == homeName &&
      other.awayName == awayName &&
      other.lastSeq == lastSeq &&
      other.activeScorerUserId == activeScorerUserId &&
      other.activeScorerDeviceId == activeScorerDeviceId &&
      other.canScore == canScore &&
      other.opponentClubId == opponentClubId &&
      other.startAt == startAt &&
      other.myClubSide == myClubSide &&
      listEquals(other.mySides, mySides) &&
      other.dls == dls &&
      other.state == state;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    eventId,
    clubId,
    status,
    oversLimit,
    homeName,
    awayName,
    lastSeq,
    activeScorerUserId,
    activeScorerDeviceId,
    canScore,
    opponentClubId,
    startAt,
    myClubSide,
    Object.hashAll(mySides),
    dls,
    state,
  ]);
}

/// The engine's refusals — thrown by the scoring layer, defined here beside the
/// types it refuses, exactly as on iOS.
class CricketEngineException implements Exception {
  const CricketEngineException.validation(this.message) : isConflict = false;
  const CricketEngineException.conflict(this.message) : isConflict = true;

  final String message;
  final bool isConflict;

  @override
  String toString() => message;
}

/// Response from `POST /cricket/matches/{id}/share`.
@immutable
class ScoreboardShareResponse {
  const ScoreboardShareResponse({
    required this.token,
    required this.url,
    required this.expiresAt,
    this.conversationId,
    this.messageId,
  });

  final String token;
  final String url;
  final DateTime expiresAt;
  final String? conversationId;
  final String? messageId;

  factory ScoreboardShareResponse.fromJson(JsonMap json) => ScoreboardShareResponse(
    token: asString(json['token'], key: 'token'),
    url: asString(json['url'], key: 'url'),
    expiresAt: asDate(json['expires_at'], key: 'expires_at'),
    conversationId: asUuidOrNull(json['conversation_id'], key: 'conversation_id'),
    messageId: asUuidOrNull(json['message_id'], key: 'message_id'),
  );

  JsonMap toJson() => <String, dynamic>{
    'token': token,
    'url': url,
    'expires_at': encodeDate(expiresAt),
    'conversation_id': conversationId,
    'message_id': messageId,
  };

  @override
  bool operator ==(Object other) =>
      other is ScoreboardShareResponse &&
      other.token == token &&
      other.url == url &&
      other.expiresAt == expiresAt &&
      other.conversationId == conversationId &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(token, url, expiresAt, conversationId, messageId);
}
