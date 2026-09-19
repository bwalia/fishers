import 'package:flutter/foundation.dart';

import 'json.dart';
import 'player_profile.dart';

/// Another player, as their club-mates may see them.
/// A port of `ios/Fishers/Models/TeammateProfile.swift`.
///
/// Deliberately narrower than `PublicUser`: no email, no phone number, no
/// emergency contact, no home location. Being in the same club as somebody is
/// not consent to hand over their mobile number, and the server does not send
/// those fields — this type simply has nowhere to put them.
@immutable
class TeammateProfile {
  const TeammateProfile({
    required this.id,
    required this.name,
    required this.sportProfiles,
    required this.sharedClubs,
    this.avatarUrl,
    this.positionRole,
    this.skillLevel,
    this.primarySport,
    this.reliability,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? positionRole;
  final String? skillLevel;
  final String? primarySport;
  final List<SportProfile> sportProfiles;
  final ReliabilityScore? reliability;

  /// Clubs you and they are both in — the reason you can see this at all, and
  /// the useful thing to know about a name you do not recognise.
  final List<String> sharedClubs;

  factory TeammateProfile.fromJson(JsonMap json) => TeammateProfile(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    avatarUrl: asStringOrNull(json['avatar_url'], key: 'avatar_url'),
    positionRole: asStringOrNull(json['position_role'], key: 'position_role'),
    skillLevel: asStringOrNull(json['skill_level'], key: 'skill_level'),
    primarySport: asStringOrNull(json['primary_sport'], key: 'primary_sport'),
    sportProfiles: asListOrEmpty(
      json['sport_profiles'],
      (Object? v) => SportProfile.fromJson(asMap(v, key: 'sport_profiles')),
    ),
    reliability: json['reliability'] == null
        ? null
        : ReliabilityScore.fromJson(asMap(json['reliability'], key: 'reliability')),
    sharedClubs: asListOrEmpty(
      json['shared_clubs'],
      (Object? v) => asString(v, key: 'shared_clubs'),
    ),
  );

  /// Decode-only on iOS; the encoder exists here so the round-trip tests can
  /// run, and so a teammate can be cached.
  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'avatar_url': avatarUrl,
    'position_role': positionRole,
    'skill_level': skillLevel,
    'primary_sport': primarySport,
    'sport_profiles': sportProfiles.map((SportProfile p) => p.toJson()).toList(growable: false),
    'reliability': reliability?.toJson(),
    'shared_clubs': sharedClubs,
  };

  /// The sport they lead with, falling back to whatever they have filled in.
  SportProfile? get mainSport {
    for (final SportProfile profile in sportProfiles) {
      if (profile.sport == primarySport) return profile;
    }
    return sportProfiles.isEmpty ? null : sportProfiles.first;
  }

  @override
  bool operator ==(Object other) =>
      other is TeammateProfile &&
      other.id == id &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.positionRole == positionRole &&
      other.skillLevel == skillLevel &&
      other.primarySport == primarySport &&
      listEquals(other.sportProfiles, sportProfiles) &&
      other.reliability == reliability &&
      listEquals(other.sharedClubs, sharedClubs);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatarUrl,
    positionRole,
    skillLevel,
    primarySport,
    Object.hashAll(sportProfiles),
    reliability,
    Object.hashAll(sharedClubs),
  );
}
