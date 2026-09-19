import 'json.dart';

/// Club / team role — matches the backend `user_role` and the RBAC matrix.
/// A port of `ios/Fishers/Models/RBAC.swift`.
enum ClubRole {
  superAdmin('super_admin'),
  clubAdmin('club_admin'), // Club secretary
  teamCaptain('team_captain'),
  teamViceCaptain('team_vice_captain'),
  member('member'),
  guest('guest');

  const ClubRole(this.wire);

  /// The `CodingKeys` raw value.
  final String wire;

  static ClubRole fromJson(Object? raw, {String? key}) =>
      enumFromRawOrThrow(ClubRole.values, raw, (ClubRole r) => r.wire, key: key);

  static ClubRole? fromJsonOrNull(Object? raw) =>
      raw == null ? null : enumFromRaw(ClubRole.values, raw as String?, (ClubRole r) => r.wire);

  String toJson() => wire;

  String get displayName => switch (this) {
    ClubRole.superAdmin => 'Super admin',
    ClubRole.clubAdmin => 'Club secretary',
    ClubRole.teamCaptain => 'Team captain',
    ClubRole.teamViceCaptain => 'Vice captain',
    ClubRole.member => 'Member',
    ClubRole.guest => 'Guest',
  };

  /// Short form for a badge.
  String get shortLabel => switch (this) {
    ClubRole.superAdmin => 'ADMIN',
    ClubRole.clubAdmin => 'SEC',
    ClubRole.teamCaptain => 'CAPT',
    ClubRole.teamViceCaptain => 'VICE',
    ClubRole.member => 'MEMBER',
    ClubRole.guest => 'GUEST',
  };

  /// What the role actually lets someone do, in the words the app uses.
  String get responsibilities => switch (this) {
    ClubRole.superAdmin => 'Platform administration.',
    ClubRole.clubAdmin =>
      'Everything: the roster, roles, teams, venues, fixtures, selection, fees and scoring.',
    ClubRole.teamCaptain =>
      'Create fixtures, invite players, pick and publish the squad, score matches.',
    ClubRole.teamViceCaptain => 'Help with selection, invite players to a fixture, score matches.',
    ClubRole.member => 'Mark availability, RSVP, chat, the shop.',
    ClubRole.guest => 'The same as a member, for a one-off invitee.',
  };

  /// The roles a secretary can hand out, strongest first.
  static const List<ClubRole> appointable = <ClubRole>[
    ClubRole.clubAdmin,
    ClubRole.teamCaptain,
    ClubRole.teamViceCaptain,
    ClubRole.member,
    ClubRole.guest,
  ];

  /// The order the roster groups people in.
  static const List<ClubRole> rosterOrder = <ClubRole>[
    ClubRole.superAdmin,
    ClubRole.clubAdmin,
    ClubRole.teamCaptain,
    ClubRole.teamViceCaptain,
    ClubRole.member,
    ClubRole.guest,
  ];

  bool get isSecretary => this == ClubRole.clubAdmin || this == ClubRole.superAdmin;

  bool get isCaptain =>
      this == ClubRole.teamCaptain || this == ClubRole.teamViceCaptain || isSecretary;

  bool get canInviteToPlay => isCaptain;
  bool get canScoreMatch => isCaptain;
  bool get canManageMembers => isSecretary;
  bool get canManageSelection => isCaptain;
}

/// `GET /clubs/{id}/my-role`.
class ClubRoleInfo {
  const ClubRoleInfo({
    required this.role,
    required this.displayName,
    required this.isSecretary,
    required this.isCaptain,
    required this.canInviteToPlay,
    required this.canScoreMatch,
    required this.permissions,
  });

  final ClubRole role;
  final String displayName;
  final bool isSecretary;
  final bool isCaptain;
  final bool canInviteToPlay;
  final bool canScoreMatch;
  final List<String> permissions;

  factory ClubRoleInfo.fromJson(JsonMap json) {
    final ClubRole role = ClubRole.fromJson(json['role'], key: 'role');
    final List<String> permissions = asListOrEmpty(
      json['permissions'],
      (Object? v) => asString(v, key: 'permissions'),
    );
    // The API may leave `can_score_match` out; fall back to the role and the
    // permission list rather than to `false`, which would hide the book from
    // the person holding it.
    final bool? flagged = asBoolOrNull(json['can_score_match'], key: 'can_score_match');
    return ClubRoleInfo(
      role: role,
      displayName: asString(json['display_name'], key: 'display_name'),
      isSecretary: asBool(json['is_secretary'], key: 'is_secretary'),
      isCaptain: asBool(json['is_captain'], key: 'is_captain'),
      canInviteToPlay: asBool(json['can_invite_to_play'], key: 'can_invite_to_play'),
      canScoreMatch: flagged ?? (role.canScoreMatch || permissions.contains('score_match')),
      permissions: permissions,
    );
  }

  JsonMap toJson() => <String, dynamic>{
    'role': role.toJson(),
    'display_name': displayName,
    'is_secretary': isSecretary,
    'is_captain': isCaptain,
    'can_invite_to_play': canInviteToPlay,
    'can_score_match': canScoreMatch,
    'permissions': permissions,
  };

  @override
  bool operator ==(Object other) =>
      other is ClubRoleInfo &&
      other.role == role &&
      other.displayName == displayName &&
      other.isSecretary == isSecretary &&
      other.isCaptain == isCaptain &&
      other.canInviteToPlay == canInviteToPlay &&
      other.canScoreMatch == canScoreMatch &&
      other.permissions.join(',') == permissions.join(',');

  @override
  int get hashCode => Object.hash(
    role,
    displayName,
    isSecretary,
    isCaptain,
    canInviteToPlay,
    canScoreMatch,
    permissions.join(','),
  );
}
