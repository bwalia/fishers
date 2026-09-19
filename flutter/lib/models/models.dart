import 'package:flutter/foundation.dart';

import 'json.dart';
import 'onboarding.dart';
import 'player_profile.dart';
import 'rbac.dart';

/// A port of `ios/Fishers/Models/Models.swift` — the core wire types.

@immutable
class PublicUser {
  const PublicUser({
    required this.id,
    required this.name,
    required this.sportsPlayed,
    this.email,
    this.phone,
    this.avatarUrl,
    this.positionRole,
    this.skillLevel,
    this.emergencyContact,
    this.primarySport,
    this.sportProfiles,
    this.location,
    this.profileComplete,
    this.reliability,
    this.emailVerified,
    this.phoneVerified,
    this.roleIntent,
  });

  final String id;
  final String name;

  /// Absent for somebody who registered with a mobile number instead.
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final List<String> sportsPlayed;

  /// Position and standard of the primary sport, flattened for list views.
  final String? positionRole;
  final String? skillLevel;
  final String? emergencyContact;

  /// Sport the player leads with — the rest of the profile hangs off it.
  final String? primarySport;

  /// One entry per sport played, each with its own level, league and stats.
  final List<SportProfile>? sportProfiles;
  final PlayerLocation? location;

  /// Server's view of whether first-run profile setup is done.
  final bool? profileComplete;

  /// Computed by the API from attendance and payment history.
  final ReliabilityScore? reliability;

  /// Whether the address or number has been confirmed with a code. Starting a
  /// club and accepting an invite wait on one of them.
  final bool? emailVerified;
  final bool? phoneVerified;

  /// "secretary" or "player" — what they said they came to do. Absent until
  /// they have been asked.
  final String? roleIntent;

  factory PublicUser.fromJson(JsonMap json) => PublicUser(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    email: asStringOrNull(json['email'], key: 'email'),
    phone: asStringOrNull(json['phone'], key: 'phone'),
    avatarUrl: asStringOrNull(json['avatar_url'], key: 'avatar_url'),
    sportsPlayed: asListOrEmpty(
      json['sports_played'],
      (Object? v) => asString(v, key: 'sports_played'),
    ),
    positionRole: asStringOrNull(json['position_role'], key: 'position_role'),
    skillLevel: asStringOrNull(json['skill_level'], key: 'skill_level'),
    emergencyContact: asStringOrNull(json['emergency_contact'], key: 'emergency_contact'),
    primarySport: asStringOrNull(json['primary_sport'], key: 'primary_sport'),
    sportProfiles: json['sport_profiles'] == null
        ? null
        : asList(
            json['sport_profiles'],
            (Object? v) => SportProfile.fromJson(asMap(v, key: 'sport_profiles')),
          ),
    location: json['location'] == null
        ? null
        : PlayerLocation.fromJson(asMap(json['location'], key: 'location')),
    profileComplete: asBoolOrNull(json['profile_complete'], key: 'profile_complete'),
    reliability: json['reliability'] == null
        ? null
        : ReliabilityScore.fromJson(asMap(json['reliability'], key: 'reliability')),
    emailVerified: asBoolOrNull(json['email_verified'], key: 'email_verified'),
    phoneVerified: asBoolOrNull(json['phone_verified'], key: 'phone_verified'),
    roleIntent: asStringOrNull(json['role_intent'], key: 'role_intent'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'avatar_url': avatarUrl,
    'sports_played': sportsPlayed,
    'position_role': positionRole,
    'skill_level': skillLevel,
    'emergency_contact': emergencyContact,
    'primary_sport': primarySport,
    'sport_profiles': sportProfiles?.map((SportProfile p) => p.toJson()).toList(growable: false),
    'location': location?.toJson(),
    'profile_complete': profileComplete,
    'reliability': reliability?.toJson(),
    'email_verified': emailVerified,
    'phone_verified': phoneVerified,
    'role_intent': roleIntent,
  };

  bool get isVerified => emailVerified == true || phoneVerified == true;

  RoleIntent? get intent => enumFromRaw(RoleIntent.values, roleIntent, (RoleIntent r) => r.wire);

  String get initials {
    final List<String> parts = name.split(' ').where((String p) => p.isNotEmpty).toList();
    final String first = parts.isEmpty ? '' : parts.first[0];
    final String last = parts.length > 1 ? parts.last[0] : '';
    return first + last;
  }

  List<SportProfile> get profiles => sportProfiles ?? const <SportProfile>[];

  SportProfile? get primaryProfile {
    for (final SportProfile profile in profiles) {
      if (profile.sport == primarySport) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  SportProfile? profileFor(Sport sport) {
    for (final SportProfile profile in profiles) {
      if (profile.sport == sport.wire) return profile;
    }
    return null;
  }

  List<Sport> get playedSports => <Sport>[
    for (final SportProfile profile in profiles)
      if (profile.sportKind case final Sport s) s,
  ];

  @override
  bool operator ==(Object other) =>
      other is PublicUser &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.phone == phone &&
      other.avatarUrl == avatarUrl &&
      listEquals(other.sportsPlayed, sportsPlayed) &&
      other.positionRole == positionRole &&
      other.skillLevel == skillLevel &&
      other.emergencyContact == emergencyContact &&
      other.primarySport == primarySport &&
      listEquals(other.sportProfiles, sportProfiles) &&
      other.location == location &&
      other.profileComplete == profileComplete &&
      other.reliability == reliability &&
      other.emailVerified == emailVerified &&
      other.phoneVerified == phoneVerified &&
      other.roleIntent == roleIntent;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    email,
    phone,
    avatarUrl,
    Object.hashAll(sportsPlayed),
    positionRole,
    skillLevel,
    emergencyContact,
    primarySport,
    sportProfiles == null ? null : Object.hashAll(sportProfiles!),
    location,
    profileComplete,
    reliability,
    emailVerified,
    phoneVerified,
    roleIntent,
  );
}

@immutable
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final PublicUser user;

  factory AuthTokens.fromJson(JsonMap json) => AuthTokens(
    accessToken: asString(json['access_token'], key: 'access_token'),
    refreshToken: asString(json['refresh_token'], key: 'refresh_token'),
    tokenType: asString(json['token_type'], key: 'token_type'),
    expiresIn: asInt(json['expires_in'], key: 'expires_in'),
    user: PublicUser.fromJson(asMap(json['user'], key: 'user')),
  );

  JsonMap toJson() => <String, dynamic>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
    'expires_in': expiresIn,
    'user': user.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AuthTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.tokenType == tokenType &&
      other.expiresIn == expiresIn &&
      other.user == user;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, tokenType, expiresIn, user);
}

/// Google / Apple sign-in response — same tokens, plus whether the account is
/// new. (v1 on Android only ever asks Google for one; see `flutter/PARITY.md`.)
@immutable
class SocialSignedIn {
  const SocialSignedIn({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
    required this.created,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final PublicUser user;
  final bool created;

  AuthTokens get tokens => AuthTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
    tokenType: tokenType,
    expiresIn: expiresIn,
    user: user,
  );

  factory SocialSignedIn.fromJson(JsonMap json) => SocialSignedIn(
    accessToken: asString(json['access_token'], key: 'access_token'),
    refreshToken: asString(json['refresh_token'], key: 'refresh_token'),
    tokenType: asString(json['token_type'], key: 'token_type'),
    expiresIn: asInt(json['expires_in'], key: 'expires_in'),
    user: PublicUser.fromJson(asMap(json['user'], key: 'user')),
    created: asBool(json['created'], key: 'created'),
  );

  JsonMap toJson() => <String, dynamic>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
    'expires_in': expiresIn,
    'user': user.toJson(),
    'created': created,
  };

  @override
  bool operator ==(Object other) =>
      other is SocialSignedIn &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.tokenType == tokenType &&
      other.expiresIn == expiresIn &&
      other.user == user &&
      other.created == created;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, tokenType, expiresIn, user, created);
}

@immutable
class Club {
  const Club({
    required this.id,
    required this.name,
    required this.sportTypes,
    required this.visibility,
    required this.ownerId,
    required this.isInformalGroup,
    this.description,
    this.role,
  });

  final String id;
  final String name;
  final List<String> sportTypes;
  final String visibility;
  final String ownerId;
  final String? description;
  final bool isInformalGroup;

  /// What you are in this club. Only `GET /clubs` fills it in — a club fetched
  /// on its own says nothing about the reader.
  final ClubRole? role;

  factory Club.fromJson(JsonMap json) => Club(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    sportTypes: asListOrEmpty(json['sport_types'], (Object? v) => asString(v, key: 'sport_types')),
    visibility: asString(json['visibility'], key: 'visibility'),
    ownerId: asUuid(json['owner_id'], key: 'owner_id'),
    description: asStringOrNull(json['description'], key: 'description'),
    isInformalGroup: asBool(json['is_informal_group'], key: 'is_informal_group'),
    role: ClubRole.fromJsonOrNull(json['role']),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'sport_types': sportTypes,
    'visibility': visibility,
    'owner_id': ownerId,
    'description': description,
    'is_informal_group': isInformalGroup,
    'role': role?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Club &&
      other.id == id &&
      other.name == name &&
      listEquals(other.sportTypes, sportTypes) &&
      other.visibility == visibility &&
      other.ownerId == ownerId &&
      other.description == description &&
      other.isInformalGroup == isInformalGroup &&
      other.role == role;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(sportTypes),
    visibility,
    ownerId,
    description,
    isInformalGroup,
    role,
  );
}

@immutable
class Team {
  const Team({required this.id, required this.clubId, required this.sport, required this.name});

  final String id;
  final String clubId;
  final String sport;
  final String name;

  factory Team.fromJson(JsonMap json) => Team(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    sport: asString(json['sport'], key: 'sport'),
    name: asString(json['name'], key: 'name'),
  );

  JsonMap toJson() => <String, dynamic>{'id': id, 'club_id': clubId, 'sport': sport, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is Team &&
      other.id == id &&
      other.clubId == clubId &&
      other.sport == sport &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, clubId, sport, name);
}

@immutable
class Venue {
  const Venue({
    required this.id,
    required this.clubId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
  });

  final String id;
  final String clubId;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;

  factory Venue.fromJson(JsonMap json) => Venue(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    name: asString(json['name'], key: 'name'),
    address: asStringOrNull(json['address'], key: 'address'),
    lat: asDoubleOrNull(json['lat'], key: 'lat'),
    lng: asDoubleOrNull(json['lng'], key: 'lng'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'name': name,
    'address': address,
    'lat': lat,
    'lng': lng,
  };

  @override
  bool operator ==(Object other) =>
      other is Venue &&
      other.id == id &&
      other.clubId == clubId &&
      other.name == name &&
      other.address == address &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(id, clubId, name, address, lat, lng);
}

enum EventSubtype {
  nets('nets'),
  friendly('friendly'),
  leagueMatch('league_match'),
  tournament('tournament'),
  social('social'),
  training('training'),
  generic('generic');

  const EventSubtype(this.wire);

  final String wire;

  static EventSubtype? named(String? raw) =>
      enumFromRaw(EventSubtype.values, raw, (EventSubtype s) => s.wire);

  String toJson() => wire;
}

@immutable
class Event {
  const Event({
    required this.id,
    required this.clubId,
    required this.sport,
    required this.eventSubtype,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.feeCurrency,
    required this.status,
    this.teamId,
    this.venueId,
    this.capacity,
    this.feeAmountCents,
    this.metadata,
    this.ticketPriceCents,
    this.opponentClubId,
  });

  final String id;
  final String clubId;
  final String? teamId;
  final String sport;
  final String eventSubtype;
  final String title;
  final String? venueId;
  final DateTime startAt;
  final DateTime endAt;
  final int? capacity;
  final int? feeAmountCents;
  final String feeCurrency;
  final String status;
  final Map<String, JsonValue>? metadata;

  /// Set on a ticketed event — a dinner, a quiz, presentation night.
  final int? ticketPriceCents;
  final String? opponentClubId;

  factory Event.fromJson(JsonMap json) => Event(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    teamId: asUuidOrNull(json['team_id'], key: 'team_id'),
    sport: asString(json['sport'], key: 'sport'),
    eventSubtype: asString(json['event_subtype'], key: 'event_subtype'),
    title: asString(json['title'], key: 'title'),
    venueId: asUuidOrNull(json['venue_id'], key: 'venue_id'),
    startAt: asDate(json['start_at'], key: 'start_at'),
    endAt: asDate(json['end_at'], key: 'end_at'),
    capacity: asIntOrNull(json['capacity'], key: 'capacity'),
    feeAmountCents: asIntOrNull(json['fee_amount_cents'], key: 'fee_amount_cents'),
    feeCurrency: asString(json['fee_currency'], key: 'fee_currency'),
    status: asString(json['status'], key: 'status'),
    metadata: JsonValue.mapFrom(json['metadata']),
    ticketPriceCents: asIntOrNull(json['ticket_price_cents'], key: 'ticket_price_cents'),
    opponentClubId: asUuidOrNull(json['opponent_club_id'], key: 'opponent_club_id'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'team_id': teamId,
    'sport': sport,
    'event_subtype': eventSubtype,
    'title': title,
    'venue_id': venueId,
    'start_at': encodeDate(startAt),
    'end_at': encodeDate(endAt),
    'capacity': capacity,
    'fee_amount_cents': feeAmountCents,
    'fee_currency': feeCurrency,
    'status': status,
    'metadata': JsonValue.mapToJson(metadata),
    'ticket_price_cents': ticketPriceCents,
    'opponent_club_id': opponentClubId,
  };

  @override
  bool operator ==(Object other) =>
      other is Event &&
      other.id == id &&
      other.clubId == clubId &&
      other.teamId == teamId &&
      other.sport == sport &&
      other.eventSubtype == eventSubtype &&
      other.title == title &&
      other.venueId == venueId &&
      other.startAt == startAt &&
      other.endAt == endAt &&
      other.capacity == capacity &&
      other.feeAmountCents == feeAmountCents &&
      other.feeCurrency == feeCurrency &&
      other.status == status &&
      mapEquals(other.metadata, metadata) &&
      other.ticketPriceCents == ticketPriceCents &&
      other.opponentClubId == opponentClubId;

  @override
  int get hashCode => Object.hash(
    id,
    clubId,
    teamId,
    sport,
    eventSubtype,
    title,
    venueId,
    startAt,
    endAt,
    capacity,
    feeAmountCents,
    feeCurrency,
    status,
    ticketPriceCents,
    opponentClubId,
  );
}

enum AvailabilityStatus {
  available('available'),
  unavailable('unavailable'),
  maybe('maybe');

  const AvailabilityStatus(this.wire);

  final String wire;

  String get colorName => wire;

  String get label => switch (this) {
    AvailabilityStatus.available => 'Available',
    AvailabilityStatus.unavailable => 'Unavailable',
    AvailabilityStatus.maybe => 'Maybe',
  };

  /// The cycle a tap on a calendar day walks.
  AvailabilityStatus next() => switch (this) {
    AvailabilityStatus.available => AvailabilityStatus.maybe,
    AvailabilityStatus.maybe => AvailabilityStatus.unavailable,
    AvailabilityStatus.unavailable => AvailabilityStatus.available,
  };

  static AvailabilityStatus fromJson(Object? raw, {String? key}) => enumFromRawOrThrow(
    AvailabilityStatus.values,
    raw,
    (AvailabilityStatus s) => s.wire,
    key: key,
  );

  static AvailabilityStatus? fromJsonOrNull(Object? raw) => raw == null
      ? null
      : enumFromRaw(AvailabilityStatus.values, raw as String?, (AvailabilityStatus s) => s.wire);

  String toJson() => wire;
}

@immutable
class Availability {
  const Availability({
    required this.id,
    required this.userId,
    required this.date,
    required this.status,
    this.note,
  });

  final String id;
  final String userId;

  /// A calendar day, `YYYY-MM-DD` — not an instant, which is why it stays a
  /// string on both platforms.
  final String date;
  final AvailabilityStatus status;
  final String? note;

  factory Availability.fromJson(JsonMap json) => Availability(
    id: asUuid(json['id'], key: 'id'),
    userId: asUuid(json['user_id'], key: 'user_id'),
    date: asString(json['date'], key: 'date'),
    status: AvailabilityStatus.fromJson(json['status'], key: 'status'),
    note: asStringOrNull(json['note'], key: 'note'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'user_id': userId,
    'date': date,
    'status': status.toJson(),
    'note': note,
  };

  @override
  bool operator ==(Object other) =>
      other is Availability &&
      other.id == id &&
      other.userId == userId &&
      other.date == date &&
      other.status == status &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, userId, date, status, note);
}

enum RsvpStatus {
  going('going'),
  notGoing('not_going'),
  maybe('maybe'),
  invited('invited');

  const RsvpStatus(this.wire);

  final String wire;

  static RsvpStatus fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(RsvpStatus.values, raw, (RsvpStatus s) => s.wire, key: key);

  String toJson() => wire;
}

@immutable
class AttendeeSummary {
  const AttendeeSummary({
    required this.userId,
    required this.name,
    required this.status,
    required this.paid,
    this.availability,
  });

  final String userId;
  final String name;
  final RsvpStatus status;
  final AvailabilityStatus? availability;
  final bool paid;

  String get id => userId;

  factory AttendeeSummary.fromJson(JsonMap json) => AttendeeSummary(
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asString(json['name'], key: 'name'),
    status: RsvpStatus.fromJson(json['status'], key: 'status'),
    availability: AvailabilityStatus.fromJsonOrNull(json['availability']),
    paid: asBool(json['paid'], key: 'paid'),
  );

  JsonMap toJson() => <String, dynamic>{
    'user_id': userId,
    'name': name,
    'status': status.toJson(),
    'availability': availability?.toJson(),
    'paid': paid,
  };

  @override
  bool operator ==(Object other) =>
      other is AttendeeSummary &&
      other.userId == userId &&
      other.name == name &&
      other.status == status &&
      other.availability == availability &&
      other.paid == paid;

  @override
  int get hashCode => Object.hash(userId, name, status, availability, paid);
}

@immutable
class Product {
  const Product({
    required this.id,
    required this.clubId,
    required this.name,
    required this.priceCents,
    required this.currency,
    required this.category,
    this.description,
  });

  final String id;
  final String clubId;
  final String name;
  final String? description;
  final int priceCents;
  final String currency;
  final String category;

  factory Product.fromJson(JsonMap json) => Product(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    name: asString(json['name'], key: 'name'),
    description: asStringOrNull(json['description'], key: 'description'),
    priceCents: asInt(json['price_cents'], key: 'price_cents'),
    currency: asString(json['currency'], key: 'currency'),
    category: asString(json['category'], key: 'category'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'name': name,
    'description': description,
    'price_cents': priceCents,
    'currency': currency,
    'category': category,
  };

  String get priceLabel => '£${(priceCents / 100).toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      other is Product &&
      other.id == id &&
      other.clubId == clubId &&
      other.name == name &&
      other.description == description &&
      other.priceCents == priceCents &&
      other.currency == currency &&
      other.category == category;

  @override
  int get hashCode => Object.hash(id, clubId, name, description, priceCents, currency, category);
}

@immutable
class Order {
  const Order({
    required this.id,
    required this.userId,
    required this.clubId,
    required this.status,
    required this.totalAmountCents,
    required this.currency,
    this.eventId,
  });

  final String id;
  final String userId;
  final String clubId;
  final String? eventId;
  final String status;
  final int totalAmountCents;
  final String currency;

  factory Order.fromJson(JsonMap json) => Order(
    id: asUuid(json['id'], key: 'id'),
    userId: asUuid(json['user_id'], key: 'user_id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    eventId: asUuidOrNull(json['event_id'], key: 'event_id'),
    status: asString(json['status'], key: 'status'),
    totalAmountCents: asInt(json['total_amount_cents'], key: 'total_amount_cents'),
    currency: asString(json['currency'], key: 'currency'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'user_id': userId,
    'club_id': clubId,
    'event_id': eventId,
    'status': status,
    'total_amount_cents': totalAmountCents,
    'currency': currency,
  };

  @override
  bool operator ==(Object other) =>
      other is Order &&
      other.id == id &&
      other.userId == userId &&
      other.clubId == clubId &&
      other.eventId == eventId &&
      other.status == status &&
      other.totalAmountCents == totalAmountCents &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(id, userId, clubId, eventId, status, totalAmountCents, currency);
}
