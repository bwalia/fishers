import 'package:flutter/foundation.dart';

import 'json.dart';

/// Sports the app knows about. A port of `ios/Fishers/Models/PlayerProfile.swift`.
///
/// The wire format stays a plain string (`sports_played`, `Club.sportTypes`,
/// `Team.sport`) so clubs can carry sports outside this list. The first seven
/// spellings are the API's `SportType`, so a profile saved on the web resolves
/// here.
enum Sport {
  cricket('cricket'),
  football('football'),
  badminton('badminton'),
  paddle('paddle'),
  pickleball('pickleball'),
  tennis('tennis'),
  other('other'),
  hockey('hockey'),
  netball('netball'),
  rugby('rugby'),
  basketball('basketball');

  const Sport(this.wire);

  final String wire;

  String get label => wire[0].toUpperCase() + wire.substring(1);

  /// Read a stored sport, allowing for how this app used to spell it. Profiles
  /// saved before the spellings were lined up still say "padel".
  static Sport? named(String? raw) {
    final String key = raw?.trim().toLowerCase() ?? '';
    if (key.isEmpty) return null;
    return enumFromRaw(Sport.values, key == 'padel' ? 'paddle' : key, (Sport s) => s.wire);
  }

  static Sport fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(Sport.values, raw, (Sport s) => s.wire, key: key);

  String toJson() => wire;

  /// Positions offered during profile setup for this sport.
  List<String> get positions => switch (this) {
    Sport.cricket => const <String>[
      'Batter',
      'Fast Bowler',
      'Spinner',
      'All-rounder',
      'Wicketkeeper',
    ],
    Sport.football ||
    Sport.hockey => const <String>['Goalkeeper', 'Defender', 'Midfielder', 'Forward'],
    Sport.badminton || Sport.tennis => const <String>['Singles', 'Doubles', 'Mixed doubles'],
    Sport.paddle || Sport.pickleball => const <String>['Right side', 'Left side', 'Either side'],
    Sport.other => const <String>[],
    Sport.netball => const <String>[
      'Goal Shooter',
      'Goal Attack',
      'Wing Attack',
      'Centre',
      'Wing Defence',
      'Goal Defence',
      'Goal Keeper',
    ],
    Sport.rugby => const <String>[
      'Front row',
      'Second row',
      'Back row',
      'Half back',
      'Centre',
      'Back three',
    ],
    Sport.basketball => const <String>['Guard', 'Forward', 'Centre'],
  };

  /// Leagues are graded per sport; cricket drives the reference scenario.
  bool get usesDivisions => switch (this) {
    Sport.cricket || Sport.football || Sport.hockey || Sport.netball || Sport.rugby => true,
    Sport.badminton ||
    Sport.paddle ||
    Sport.pickleball ||
    Sport.tennis ||
    Sport.basketball ||
    Sport.other => false,
  };
}

/// Self-rated standard, ordered so a player can see the rung above them.
enum SkillTier {
  beginner('beginner'),
  improver('improver'),
  intermediate('intermediate'),
  club('club'),
  advanced('advanced'),
  elite('elite');

  const SkillTier(this.wire);

  final String wire;

  String get label =>
      this == SkillTier.club ? 'Club standard' : wire[0].toUpperCase() + wire.substring(1);

  String get blurb => switch (this) {
    SkillTier.beginner => 'New to the sport — learning the basics.',
    SkillTier.improver => 'Played a bit, still building consistency.',
    SkillTier.intermediate => 'Comfortable in social and lower league sides.',
    SkillTier.club => 'Regular league player, holds a place in a side.',
    SkillTier.advanced => 'Strong league performer, front-line pick.',
    SkillTier.elite => 'Premier, county or representative standard.',
  };

  int get rank => index;

  /// The next rung up, used by the progression hint on the profile.
  SkillTier? get next => index + 1 < SkillTier.values.length ? SkillTier.values[index + 1] : null;

  /// Tolerates the capitalised strings stored on `skill_level`.
  static SkillTier? stored(String? raw) {
    if (raw == null) return null;
    final String key = raw.toLowerCase().replaceAll(' standard', '');
    return enumFromRaw(SkillTier.values, key, (SkillTier t) => t.wire);
  }

  String toJson() => wire;
}

/// League grade, lowest to highest — a player's current and target division.
enum Division {
  social('social'),
  development('development'),
  division5('division5'),
  division4('division4'),
  division3('division3'),
  division2('division2'),
  division1('division1'),
  premier('premier'),
  county('county');

  const Division(this.wire);

  final String wire;

  String get label => switch (this) {
    Division.social => 'Social & friendlies',
    Division.development => 'Development side',
    Division.division5 => 'Division 5',
    Division.division4 => 'Division 4',
    Division.division3 => 'Division 3',
    Division.division2 => 'Division 2',
    Division.division1 => 'Division 1',
    Division.premier => 'Premier Division',
    Division.county => 'County / Representative',
  };

  String get shortLabel => switch (this) {
    Division.social => 'Social',
    Division.development => 'Dev',
    Division.division5 => 'Div 5',
    Division.division4 => 'Div 4',
    Division.division3 => 'Div 3',
    Division.division2 => 'Div 2',
    Division.division1 => 'Div 1',
    Division.premier => 'Prem',
    Division.county => 'County',
  };

  int get rank => index;

  Division? get next => index + 1 < Division.values.length ? Division.values[index + 1] : null;

  static Division? stored(String? raw) =>
      raw == null ? null : enumFromRaw(Division.values, raw, (Division d) => d.wire);

  String toJson() => wire;
}

/// Age band the player is eligible for — colts sides pick from the junior bands.
enum AgeGroup {
  u11('u11'),
  u13('u13'),
  u15('u15'),
  u17('u17'),
  senior('senior'),
  vets40('vets40'),
  vets50('vets50');

  const AgeGroup(this.wire);

  final String wire;

  String get label => switch (this) {
    AgeGroup.u11 => 'Under 11s',
    AgeGroup.u13 => 'Under 13s',
    AgeGroup.u15 => 'Under 15s',
    AgeGroup.u17 => 'Under 17s',
    AgeGroup.senior => 'Senior',
    AgeGroup.vets40 => 'Vets 40+',
    AgeGroup.vets50 => 'Vets 50+',
  };

  bool get isJunior => switch (this) {
    AgeGroup.u11 || AgeGroup.u13 || AgeGroup.u15 || AgeGroup.u17 => true,
    _ => false,
  };

  static AgeGroup? stored(String? raw) =>
      raw == null ? null : enumFromRaw(AgeGroup.values, raw, (AgeGroup g) => g.wire);

  String toJson() => wire;
}

/// How the player gets to fixtures — feeds lift sharing on away games.
///
/// The raw values are Swift's default enum case names, which is what the API
/// stores, so they are camelCase here and not snake_case. Checked against a
/// captured `PATCH /me` response.
enum TransportMode {
  driverWithSeats('driverWithSeats'),
  driver('driver'),
  publicTransport('publicTransport'),
  needsLift('needsLift');

  const TransportMode(this.wire);

  final String wire;

  String get label => switch (this) {
    TransportMode.driverWithSeats => 'Drives, can offer lifts',
    TransportMode.driver => 'Drives, no spare seats',
    TransportMode.publicTransport => 'Public transport',
    TransportMode.needsLift => 'Needs a lift',
  };

  bool get offersLifts => this == TransportMode.driverWithSeats;

  static TransportMode? fromJsonOrNull(Object? raw) => raw == null
      ? null
      : enumFromRaw(TransportMode.values, raw as String?, (TransportMode t) => t.wire);

  String toJson() => wire;
}

/// Weekday, matching `Calendar` numbering (1 = Sunday).
enum Weekday {
  sunday(1),
  monday(2),
  tuesday(3),
  wednesday(4),
  thursday(5),
  friday(6),
  saturday(7);

  const Weekday(this.wire);

  final int wire;

  String get shortLabel => switch (this) {
    Weekday.sunday => 'Sun',
    Weekday.monday => 'Mon',
    Weekday.tuesday => 'Tue',
    Weekday.wednesday => 'Wed',
    Weekday.thursday => 'Thu',
    Weekday.friday => 'Fri',
    Weekday.saturday => 'Sat',
  };

  static Weekday? fromWire(int raw) {
    for (final Weekday day in Weekday.values) {
      if (day.wire == raw) return day;
    }
    return null;
  }

  /// Monday-first ordering for the day picker.
  static const List<Weekday> pickerOrder = <Weekday>[
    Weekday.monday,
    Weekday.tuesday,
    Weekday.wednesday,
    Weekday.thursday,
    Weekday.friday,
    Weekday.saturday,
    Weekday.sunday,
  ];
}

/// One sport a player takes part in, with the level, league grade and stats
/// they keep for it. A player carries one of these per sport picked at setup.
@immutable
class SportProfile {
  const SportProfile({
    required this.sport,
    this.position,
    this.skillLevel,
    this.currentDivision,
    this.targetDivision,
    this.ageGroup,
    this.teamName,
    this.yearsPlaying,
    this.stats = const <String, String>{},
  });

  final String sport;
  final String? position;
  final String? skillLevel;
  final String? currentDivision;
  final String? targetDivision;
  final String? ageGroup;
  final String? teamName;
  final int? yearsPlaying;
  final Map<String, String> stats;

  String get id => sport;

  /// Hand-rolled so a payload without `stats` still decodes.
  factory SportProfile.fromJson(JsonMap json) => SportProfile(
    sport: asString(json['sport'], key: 'sport'),
    position: asStringOrNull(json['position'], key: 'position'),
    skillLevel: asStringOrNull(json['skill_level'], key: 'skill_level'),
    currentDivision: asStringOrNull(json['current_division'], key: 'current_division'),
    targetDivision: asStringOrNull(json['target_division'], key: 'target_division'),
    ageGroup: asStringOrNull(json['age_group'], key: 'age_group'),
    teamName: asStringOrNull(json['team_name'], key: 'team_name'),
    yearsPlaying: asIntOrNull(json['years_playing'], key: 'years_playing'),
    stats: asStringMap(json['stats'], key: 'stats'),
  );

  /// Every key is written, nulls included: `PATCH /me` sends the whole profile
  /// the app holds, so a field cleared on the phone has to arrive as a null.
  JsonMap toJson() => <String, dynamic>{
    'sport': sport,
    'position': position,
    'skill_level': skillLevel,
    'current_division': currentDivision,
    'target_division': targetDivision,
    'age_group': ageGroup,
    'team_name': teamName,
    'years_playing': yearsPlaying,
    'stats': stats,
  };

  SportProfile copyWith({
    String? sport,
    String? position,
    String? skillLevel,
    String? currentDivision,
    String? targetDivision,
    String? ageGroup,
    String? teamName,
    int? yearsPlaying,
    Map<String, String>? stats,
  }) => SportProfile(
    sport: sport ?? this.sport,
    position: position ?? this.position,
    skillLevel: skillLevel ?? this.skillLevel,
    currentDivision: currentDivision ?? this.currentDivision,
    targetDivision: targetDivision ?? this.targetDivision,
    ageGroup: ageGroup ?? this.ageGroup,
    teamName: teamName ?? this.teamName,
    yearsPlaying: yearsPlaying ?? this.yearsPlaying,
    stats: stats ?? this.stats,
  );

  Sport? get sportKind => Sport.named(sport);
  SkillTier? get tier => SkillTier.stored(skillLevel);
  Division? get division => Division.stored(currentDivision);
  Division? get target => Division.stored(targetDivision);
  AgeGroup? get ageBand => AgeGroup.stored(ageGroup);

  /// True once the player has said what standard they play at — the gate the
  /// setup flow uses.
  bool get isComplete => tier != null;

  /// How many divisions sit between where they play and where they're aiming.
  int get divisionsToTarget {
    final Division? from = division;
    final Division? to = target;
    if (from == null || to == null) return 0;
    final int gap = to.rank - from.rank;
    return gap > 0 ? gap : 0;
  }

  @override
  bool operator ==(Object other) =>
      other is SportProfile &&
      other.sport == sport &&
      other.position == position &&
      other.skillLevel == skillLevel &&
      other.currentDivision == currentDivision &&
      other.targetDivision == targetDivision &&
      other.ageGroup == ageGroup &&
      other.teamName == teamName &&
      other.yearsPlaying == yearsPlaying &&
      mapEquals(other.stats, stats);

  @override
  int get hashCode => Object.hash(
    sport,
    position,
    skillLevel,
    currentDivision,
    targetDivision,
    ageGroup,
    teamName,
    yearsPlaying,
    Object.hashAllUnordered(
      stats.entries.map((MapEntry<String, String> e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Where the player is based and how they travel — drives away-game lift
/// sharing.
@immutable
class PlayerLocation {
  const PlayerLocation({
    this.area,
    this.postcode,
    this.travelRadiusMiles,
    this.transport,
    this.spareSeats,
    this.preferredDays,
    this.notes,
  });

  final String? area;
  final String? postcode;
  final int? travelRadiusMiles;
  final TransportMode? transport;
  final int? spareSeats;
  final List<int>? preferredDays;
  final String? notes;

  factory PlayerLocation.fromJson(JsonMap json) => PlayerLocation(
    area: asStringOrNull(json['area'], key: 'area'),
    postcode: asStringOrNull(json['postcode'], key: 'postcode'),
    travelRadiusMiles: asIntOrNull(json['travel_radius_miles'], key: 'travel_radius_miles'),
    transport: TransportMode.fromJsonOrNull(json['transport']),
    spareSeats: asIntOrNull(json['spare_seats'], key: 'spare_seats'),
    preferredDays: json['preferred_days'] == null
        ? null
        : asList(json['preferred_days'], (Object? v) => asInt(v, key: 'preferred_days')),
    notes: asStringOrNull(json['notes'], key: 'notes'),
  );

  JsonMap toJson() => <String, dynamic>{
    'area': area,
    'postcode': postcode,
    'travel_radius_miles': travelRadiusMiles,
    'transport': transport?.toJson(),
    'spare_seats': spareSeats,
    'preferred_days': preferredDays,
    'notes': notes,
  };

  List<Weekday> get weekdays => <Weekday>[
    for (final int day in preferredDays ?? const <int>[])
      if (Weekday.fromWire(day) case final Weekday d) d,
  ];

  String? get summary {
    final List<String> parts = <String?>[
      area,
      postcode,
    ].nonNulls.where((String p) => p.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get isEmpty =>
      (area?.isEmpty ?? true) &&
      (postcode?.isEmpty ?? true) &&
      travelRadiusMiles == null &&
      transport == null &&
      (preferredDays?.isEmpty ?? true) &&
      (notes?.isEmpty ?? true);

  @override
  bool operator ==(Object other) =>
      other is PlayerLocation &&
      other.area == area &&
      other.postcode == postcode &&
      other.travelRadiusMiles == travelRadiusMiles &&
      other.transport == transport &&
      other.spareSeats == spareSeats &&
      listEquals(other.preferredDays, preferredDays) &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
    area,
    postcode,
    travelRadiusMiles,
    transport,
    spareSeats,
    preferredDays == null ? null : Object.hashAll(preferredDays!),
    notes,
  );
}

enum ReliabilityBand {
  unproven('unproven'),
  patchy('patchy'),
  dependable('dependable'),
  rockSolid('rock_solid');

  const ReliabilityBand(this.wire);

  final String wire;

  String get label => switch (this) {
    ReliabilityBand.unproven => 'Unproven',
    ReliabilityBand.patchy => 'Patchy',
    ReliabilityBand.dependable => 'Dependable',
    ReliabilityBand.rockSolid => 'Rock solid',
  };

  String get blurb => switch (this) {
    ReliabilityBand.unproven => 'Not enough games yet to score.',
    ReliabilityBand.patchy => 'Drops out late more often than most.',
    ReliabilityBand.dependable => 'Turns up when they say they will.',
    ReliabilityBand.rockSolid => 'Answers early, shows up, pays up.',
  };

  static ReliabilityBand fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(ReliabilityBand.values, raw, (ReliabilityBand b) => b.wire, key: key);

  String toJson() => wire;
}

/// Server-computed selection weighting: did they answer, did they turn up, did
/// they pay. Captains weigh it beside skill; players see their own breakdown.
@immutable
class ReliabilityScore {
  const ReliabilityScore({
    required this.score,
    required this.attendanceRate,
    required this.responseRate,
    required this.paymentRate,
    required this.lateCancellations,
    required this.sampleSize,
    required this.band,
  });

  final int score;
  final double attendanceRate;
  final double responseRate;
  final double paymentRate;
  final int lateCancellations;
  final int sampleSize;
  final ReliabilityBand band;

  static const int minimumSample = 3;

  factory ReliabilityScore.fromJson(JsonMap json) => ReliabilityScore(
    score: asInt(json['score'], key: 'score'),
    attendanceRate: asDouble(json['attendance_rate'], key: 'attendance_rate'),
    responseRate: asDouble(json['response_rate'], key: 'response_rate'),
    paymentRate: asDouble(json['payment_rate'], key: 'payment_rate'),
    lateCancellations: asInt(json['late_cancellations'], key: 'late_cancellations'),
    sampleSize: asInt(json['sample_size'], key: 'sample_size'),
    band: ReliabilityBand.fromJson(json['band'], key: 'band'),
  );

  JsonMap toJson() => <String, dynamic>{
    'score': score,
    'attendance_rate': attendanceRate,
    'response_rate': responseRate,
    'payment_rate': paymentRate,
    'late_cancellations': lateCancellations,
    'sample_size': sampleSize,
    'band': band.toJson(),
  };

  /// 0…1 for the progress ring on the profile header.
  double get fraction => score.clamp(0, 100) / 100;

  /// Same weighting as `fishers_domain::reliability`, kept here so previews and
  /// any client-side estimate match the server.
  static ReliabilityScore compute({
    required int invitesReceived,
    required int responded,
    required int saidGoing,
    required int turnedUp,
    required int lateCancellations,
    required int feesDue,
    required int feesPaid,
  }) {
    final double responseRate = invitesReceived > 0 ? responded / invitesReceived : 0;
    final double attendanceRate = saidGoing > 0 ? turnedUp / saidGoing : 0;
    final double paymentRate = feesDue > 0 ? feesPaid / feesDue : 1;
    final double weighted = 0.5 * attendanceRate + 0.25 * responseRate + 0.25 * paymentRate;
    final int score = ((weighted * 100).round() - 5 * lateCancellations).clamp(0, 100);
    final ReliabilityBand band;
    if (invitesReceived < minimumSample) {
      band = ReliabilityBand.unproven;
    } else if (score >= 85) {
      band = ReliabilityBand.rockSolid;
    } else if (score >= 65) {
      band = ReliabilityBand.dependable;
    } else {
      band = ReliabilityBand.patchy;
    }
    return ReliabilityScore(
      score: score,
      attendanceRate: attendanceRate,
      responseRate: responseRate,
      paymentRate: paymentRate,
      lateCancellations: lateCancellations,
      sampleSize: invitesReceived,
      band: band,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReliabilityScore &&
      other.score == score &&
      other.attendanceRate == attendanceRate &&
      other.responseRate == responseRate &&
      other.paymentRate == paymentRate &&
      other.lateCancellations == lateCancellations &&
      other.sampleSize == sampleSize &&
      other.band == band;

  @override
  int get hashCode => Object.hash(
    score,
    attendanceRate,
    responseRate,
    paymentRate,
    lateCancellations,
    sampleSize,
    band,
  );
}

/// Body of `PATCH /me`. The client submits the whole profile it holds; the flat
/// `position_role` / `skill_level` mirror the primary sport.
@immutable
class ProfileUpdate {
  ProfileUpdate({
    required this.name,
    required List<SportProfile> sportProfiles,
    required this.primarySport,
    this.phone,
    this.avatarUrl,
    this.emergencyContact,
    this.location,
  }) : sportProfiles = sportProfiles,
       sportsPlayed = sportProfiles.map((SportProfile p) => p.sport).toList(growable: false),
       positionRole = _primary(sportProfiles, primarySport)?.position,
       skillLevel = _primary(sportProfiles, primarySport)?.skillLevel;

  const ProfileUpdate.raw({
    required this.name,
    required this.sportsPlayed,
    required this.sportProfiles,
    this.phone,
    this.avatarUrl,
    this.emergencyContact,
    this.primarySport,
    this.positionRole,
    this.skillLevel,
    this.location,
  });

  final String name;
  final String? phone;
  final String? avatarUrl;
  final String? emergencyContact;
  final String? primarySport;
  final List<String> sportsPlayed;
  final String? positionRole;
  final String? skillLevel;
  final List<SportProfile> sportProfiles;
  final PlayerLocation? location;

  static SportProfile? _primary(List<SportProfile> profiles, String? primarySport) {
    for (final SportProfile profile in profiles) {
      if (profile.sport == primarySport) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  /// Every key, nulls included — see [SportProfile.toJson].
  JsonMap toJson() => <String, dynamic>{
    'name': name,
    'phone': phone,
    'avatar_url': avatarUrl,
    'emergency_contact': emergencyContact,
    'primary_sport': primarySport,
    'sports_played': sportsPlayed,
    'position_role': positionRole,
    'skill_level': skillLevel,
    'sport_profiles': sportProfiles.map((SportProfile p) => p.toJson()).toList(growable: false),
    'location': location?.toJson(),
  };

  factory ProfileUpdate.fromJson(JsonMap json) => ProfileUpdate.raw(
    name: asString(json['name'], key: 'name'),
    phone: asStringOrNull(json['phone'], key: 'phone'),
    avatarUrl: asStringOrNull(json['avatar_url'], key: 'avatar_url'),
    emergencyContact: asStringOrNull(json['emergency_contact'], key: 'emergency_contact'),
    primarySport: asStringOrNull(json['primary_sport'], key: 'primary_sport'),
    sportsPlayed: asListOrEmpty(
      json['sports_played'],
      (Object? v) => asString(v, key: 'sports_played'),
    ),
    positionRole: asStringOrNull(json['position_role'], key: 'position_role'),
    skillLevel: asStringOrNull(json['skill_level'], key: 'skill_level'),
    sportProfiles: asListOrEmpty(
      json['sport_profiles'],
      (Object? v) => SportProfile.fromJson(asMap(v, key: 'sport_profiles')),
    ),
    location: json['location'] == null
        ? null
        : PlayerLocation.fromJson(asMap(json['location'], key: 'location')),
  );

  @override
  bool operator ==(Object other) =>
      other is ProfileUpdate &&
      other.name == name &&
      other.phone == phone &&
      other.avatarUrl == avatarUrl &&
      other.emergencyContact == emergencyContact &&
      other.primarySport == primarySport &&
      listEquals(other.sportsPlayed, sportsPlayed) &&
      other.positionRole == positionRole &&
      other.skillLevel == skillLevel &&
      listEquals(other.sportProfiles, sportProfiles) &&
      other.location == location;

  @override
  int get hashCode => Object.hash(
    name,
    phone,
    avatarUrl,
    emergencyContact,
    primarySport,
    Object.hashAll(sportsPlayed),
    positionRole,
    skillLevel,
    Object.hashAll(sportProfiles),
    location,
  );
}
