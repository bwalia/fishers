import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'club_admin.dart';
import 'json.dart';
import 'models.dart';
import 'player_profile.dart';
import 'rbac.dart';

/// A port of `ios/Fishers/Models/Clubs.swift`.

/// One row of `GET /me/clubs`: the club, what you are in it, and the numbers
/// the list shows.
@immutable
class ClubMembershipRow {
  const ClubMembershipRow({
    required this.id,
    required this.name,
    required this.sportTypes,
    required this.visibility,
    required this.ownerId,
    required this.isInformalGroup,
    required this.role,
    required this.isCaptain,
    required this.memberCount,
    required this.teamCount,
    this.description,
    this.publicSlug,
  });

  final String id;
  final String name;
  final List<String> sportTypes;
  final String visibility;
  final String ownerId;
  final String? description;
  final bool isInformalGroup;
  final ClubRole role;

  /// Captains the side — by role, or a secretary who captains too.
  final bool isCaptain;
  final int memberCount;
  final int teamCount;

  /// The public page's address, only once the club has switched it on.
  final String? publicSlug;

  factory ClubMembershipRow.fromJson(JsonMap json) {
    final ClubRole role = ClubRole.fromJson(json['role'], key: 'role');
    return ClubMembershipRow(
      id: asUuid(json['id'], key: 'id'),
      name: asString(json['name'], key: 'name'),
      sportTypes: asListOrEmpty(
        json['sport_types'],
        (Object? v) => asString(v, key: 'sport_types'),
      ),
      visibility: asStringOrNull(json['visibility'], key: 'visibility') ?? 'invite_only',
      ownerId: asUuid(json['owner_id'], key: 'owner_id'),
      description: asStringOrNull(json['description'], key: 'description'),
      isInformalGroup: asBoolOrNull(json['is_informal_group'], key: 'is_informal_group') ?? false,
      role: role,
      isCaptain:
          asBoolOrNull(json['is_captain'], key: 'is_captain') ?? (role == ClubRole.teamCaptain),
      memberCount: asIntOrNull(json['member_count'], key: 'member_count') ?? 0,
      teamCount: asIntOrNull(json['team_count'], key: 'team_count') ?? 0,
      publicSlug: asStringOrNull(json['public_slug'], key: 'public_slug'),
    );
  }

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'sport_types': sportTypes,
    'visibility': visibility,
    'owner_id': ownerId,
    'description': description,
    'is_informal_group': isInformalGroup,
    'role': role.toJson(),
    'is_captain': isCaptain,
    'member_count': memberCount,
    'team_count': teamCount,
    'public_slug': publicSlug,
  };

  /// The same club, as the screens that take a [Club] want it.
  Club get club => Club(
    id: id,
    name: name,
    sportTypes: sportTypes,
    visibility: visibility,
    ownerId: ownerId,
    description: description,
    isInformalGroup: isInformalGroup,
    role: role,
  );

  String get roleLabel => RoleChoice(role: role, isCaptain: isCaptain).label;

  bool get isPublic => visibility == 'public';

  Uri? get publicPageUrl =>
      publicSlug == null ? null : Uri.parse('${AppConfig.instance.webBaseUrl}/c/$publicSlug');

  @override
  bool operator ==(Object other) =>
      other is ClubMembershipRow &&
      other.id == id &&
      other.name == name &&
      listEquals(other.sportTypes, sportTypes) &&
      other.visibility == visibility &&
      other.ownerId == ownerId &&
      other.description == description &&
      other.isInformalGroup == isInformalGroup &&
      other.role == role &&
      other.isCaptain == isCaptain &&
      other.memberCount == memberCount &&
      other.teamCount == teamCount &&
      other.publicSlug == publicSlug;

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
    isCaptain,
    memberCount,
    teamCount,
    publicSlug,
  );
}

/// What the clubs list is filtered and sorted by — all done by the server.
@immutable
class ClubListFilters {
  const ClubListFilters({
    this.query = '',
    this.role,
    this.sport,
    this.publicPage,
    this.sort = ClubListSort.name,
  });

  final String query;
  final ClubListRole? role;
  final String? sport;

  /// null for either, true for published pages, false for none.
  final bool? publicPage;
  final ClubListSort sort;

  ClubListFilters copyWith({
    String? query,
    ClubListRole? role,
    String? sport,
    bool? publicPage,
    ClubListSort? sort,
    bool clearRole = false,
    bool clearSport = false,
    bool clearPublicPage = false,
  }) => ClubListFilters(
    query: query ?? this.query,
    role: clearRole ? null : (role ?? this.role),
    sport: clearSport ? null : (sport ?? this.sport),
    publicPage: clearPublicPage ? null : (publicPage ?? this.publicPage),
    sort: sort ?? this.sort,
  );

  bool get isFiltered =>
      query.trim().isNotEmpty || role != null || sport != null || publicPage != null;

  /// The query string `GET /me/clubs` is asked with. Built in the same order as
  /// the Swift version, so the two clients produce identical URLs.
  List<({String name, String value})> queryItems({required int page, required int perPage}) {
    final List<({String name, String value})> items = <({String name, String value})>[
      (name: 'sort', value: sort.wire),
      (name: 'page', value: '$page'),
      (name: 'per_page', value: '$perPage'),
    ];
    final String q = query.trim();
    if (q.isNotEmpty) {
      items.add((name: 'q', value: q.length > 100 ? q.substring(0, 100) : q));
    }
    if (role != null) items.add((name: 'role', value: role!.wire));
    if (sport != null) items.add((name: 'sport', value: sport!));
    if (publicPage != null) {
      items.add((name: 'public_page', value: publicPage! ? 'true' : 'false'));
    }
    return items;
  }

  @override
  bool operator ==(Object other) =>
      other is ClubListFilters &&
      other.query == query &&
      other.role == role &&
      other.sport == sport &&
      other.publicPage == publicPage &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(query, role, sport, publicPage, sort);
}

enum ClubListRole {
  secretary('secretary'),
  captain('captain'),
  viceCaptain('vice_captain'),
  member('member');

  const ClubListRole(this.wire);

  final String wire;

  String get label => switch (this) {
    ClubListRole.secretary => 'Secretary',
    ClubListRole.captain => 'Captain',
    ClubListRole.viceCaptain => 'Vice captain',
    ClubListRole.member => 'Member',
  };
}

enum ClubListSort {
  name('name'),
  recent('recent'),
  members('members');

  const ClubListSort(this.wire);

  final String wire;

  String get label => switch (this) {
    ClubListSort.name => 'Name A–Z',
    ClubListSort.recent => 'Recently joined',
    ClubListSort.members => 'Most members',
  };
}

/// A role as the picker offers it: the roles, plus a secretary who captains.
@immutable
class RoleChoice {
  /// Only a secretary carries the flag; a Captain is a captain by role.
  RoleChoice({required this.role, required bool isCaptain})
    : isCaptain = role.isSecretary && isCaptain;

  final ClubRole role;
  final bool isCaptain;

  String get id => role.wire + (isCaptain ? '+captain' : '');

  String get label => isCaptain ? 'Secretary & captain' : role.displayName;

  String get shortLabel => isCaptain ? 'SEC · C' : role.shortLabel;

  String get responsibilities => isCaptain
      ? 'A secretary who also captains the side — usual in a small club. '
            'Marked captain on the team sheet.'
      : role.responsibilities;

  /// Every choice a secretary can make, strongest first.
  static List<RoleChoice> get appointable => <RoleChoice>[
    RoleChoice(role: ClubRole.clubAdmin, isCaptain: true),
    for (final ClubRole role in ClubRole.appointable) RoleChoice(role: role, isCaptain: false),
  ];

  @override
  bool operator ==(Object other) =>
      other is RoleChoice && other.role == role && other.isCaptain == isCaptain;

  @override
  int get hashCode => Object.hash(role, isCaptain);
}

/// `GET/PATCH /clubs/{id}/page` — the club's own public page.
@immutable
class ClubPageSettings {
  const ClubPageSettings({
    required this.id,
    required this.name,
    required this.publicPage,
    this.slug,
    this.tagline,
    this.about,
    this.ground,
    this.foundedYear,
    this.contactEmail,
    this.website,
    this.iconPlayerId,
  });

  final String id;
  final String name;
  final String? slug;
  final String? tagline;
  final String? about;
  final String? ground;
  final int? foundedYear;
  final String? contactEmail;
  final String? website;
  final bool publicPage;
  final String? iconPlayerId;

  factory ClubPageSettings.fromJson(JsonMap json) => ClubPageSettings(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    slug: asStringOrNull(json['slug'], key: 'slug'),
    tagline: asStringOrNull(json['tagline'], key: 'tagline'),
    about: asStringOrNull(json['about'], key: 'about'),
    ground: asStringOrNull(json['ground'], key: 'ground'),
    foundedYear: asIntOrNull(json['founded_year'], key: 'founded_year'),
    contactEmail: asStringOrNull(json['contact_email'], key: 'contact_email'),
    website: asStringOrNull(json['website'], key: 'website'),
    publicPage: asBool(json['public_page'], key: 'public_page'),
    iconPlayerId: asUuidOrNull(json['icon_player_id'], key: 'icon_player_id'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'slug': slug,
    'tagline': tagline,
    'about': about,
    'ground': ground,
    'founded_year': foundedYear,
    'contact_email': contactEmail,
    'website': website,
    'public_page': publicPage,
    'icon_player_id': iconPlayerId,
  };

  ClubPageSettings copyWith({
    String? slug,
    String? tagline,
    String? about,
    String? ground,
    int? foundedYear,
    String? contactEmail,
    String? website,
    bool? publicPage,
    String? iconPlayerId,
  }) => ClubPageSettings(
    id: id,
    name: name,
    slug: slug ?? this.slug,
    tagline: tagline ?? this.tagline,
    about: about ?? this.about,
    ground: ground ?? this.ground,
    foundedYear: foundedYear ?? this.foundedYear,
    contactEmail: contactEmail ?? this.contactEmail,
    website: website ?? this.website,
    publicPage: publicPage ?? this.publicPage,
    iconPlayerId: iconPlayerId ?? this.iconPlayerId,
  );

  /// A default anyone can live with, from the name the club already chose.
  static String suggestedSlug(String name) {
    final StringBuffer out = StringBuffer();
    bool lastDash = false;
    for (final int rune in name.toLowerCase().runes) {
      final bool alphanumericAscii =
          (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7A);
      if (alphanumericAscii) {
        out.writeCharCode(rune);
        lastDash = false;
      } else if (!lastDash && out.isNotEmpty) {
        out.write('-');
        lastDash = true;
      }
    }
    final String slug = out.toString();
    return slug.endsWith('-') ? slug.substring(0, slug.length - 1) : slug;
  }

  /// Sent as `icon_player_id` to mean "nobody": a JSON null means "not
  /// touched", so clearing needs a value the API can tell apart.
  static const String noIconPlayer = '00000000-0000-0000-0000-000000000000';

  @override
  bool operator ==(Object other) =>
      other is ClubPageSettings &&
      other.id == id &&
      other.name == name &&
      other.slug == slug &&
      other.tagline == tagline &&
      other.about == about &&
      other.ground == ground &&
      other.foundedYear == foundedYear &&
      other.contactEmail == contactEmail &&
      other.website == website &&
      other.publicPage == publicPage &&
      other.iconPlayerId == iconPlayerId;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    slug,
    tagline,
    about,
    ground,
    foundedYear,
    contactEmail,
    website,
    publicPage,
    iconPlayerId,
  );
}

/// One person in a team, from `GET /teams/{id}/members`.
@immutable
class TeamMemberRow {
  const TeamMemberRow({
    required this.userId,
    required this.name,
    required this.role,
    this.avatarUrl,
    this.positionRole,
  });

  final String userId;
  final String name;
  final ClubRole role;
  final String? avatarUrl;
  final String? positionRole;

  String get id => userId;

  factory TeamMemberRow.fromJson(JsonMap json) => TeamMemberRow(
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asString(json['name'], key: 'name'),
    role: ClubRole.fromJson(json['role'], key: 'role'),
    avatarUrl: asStringOrNull(json['avatar_url'], key: 'avatar_url'),
    positionRole: asStringOrNull(json['position_role'], key: 'position_role'),
  );

  JsonMap toJson() => <String, dynamic>{
    'user_id': userId,
    'name': name,
    'role': role.toJson(),
    'avatar_url': avatarUrl,
    'position_role': positionRole,
  };

  @override
  bool operator ==(Object other) =>
      other is TeamMemberRow &&
      other.userId == userId &&
      other.name == name &&
      other.role == role &&
      other.avatarUrl == avatarUrl &&
      other.positionRole == positionRole;

  @override
  int get hashCode => Object.hash(userId, name, role, avatarUrl, positionRole);
}

/// A player's card, as a secretary sees it from a shared link. No contact
/// details — those come with membership, which the player still accepts.
@immutable
class SharedPlayerCard {
  const SharedPlayerCard({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.primarySport,
    this.sportProfiles,
    this.area,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? primarySport;
  final List<SportProfile>? sportProfiles;
  final String? area;

  factory SharedPlayerCard.fromJson(JsonMap json) => SharedPlayerCard(
    id: asUuid(json['id'], key: 'id'),
    name: asString(json['name'], key: 'name'),
    avatarUrl: asStringOrNull(json['avatar_url'], key: 'avatar_url'),
    primarySport: asStringOrNull(json['primary_sport'], key: 'primary_sport'),
    sportProfiles: json['sport_profiles'] == null
        ? null
        : asList(
            json['sport_profiles'],
            (Object? v) => SportProfile.fromJson(asMap(v, key: 'sport_profiles')),
          ),
    area: asStringOrNull(json['area'], key: 'area'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'avatar_url': avatarUrl,
    'primary_sport': primarySport,
    'sport_profiles': sportProfiles?.map((SportProfile p) => p.toJson()).toList(growable: false),
    'area': area,
  };

  /// Pulls the token out of whatever was pasted — people paste the whole
  /// message they were sent, not just the link.
  static String? token(String text) {
    final RegExpMatch? match = RegExp(r'/p/([A-Za-z0-9]{16,64})').firstMatch(text);
    return match?.group(1);
  }

  @override
  bool operator ==(Object other) =>
      other is SharedPlayerCard &&
      other.id == id &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.primarySport == primarySport &&
      listEquals(other.sportProfiles, sportProfiles) &&
      other.area == area;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatarUrl,
    primarySport,
    sportProfiles == null ? null : Object.hashAll(sportProfiles!),
    area,
  );
}

/// A new club's next steps, ticked off from what exists.
enum ClubSetupStepKind { players, team, captain, ground }

@immutable
class ClubSetupStep {
  const ClubSetupStep({required this.kind, required this.done});

  final ClubSetupStepKind kind;
  final bool done;

  ClubSetupStepKind get id => kind;

  String get title => switch (kind) {
    ClubSetupStepKind.players => 'Add your players',
    ClubSetupStepKind.team => 'Add a team',
    ClubSetupStepKind.captain => 'Name a captain',
    ClubSetupStepKind.ground => 'Add your ground',
  };

  String get detail => switch (kind) {
    ClubSetupStepKind.players =>
      'By email or mobile number, or from a profile link a player sends you.',
    ClubSetupStepKind.team => 'A 1st XI, a Sunday side, the juniors — each keeps its own squad.',
    ClubSetupStepKind.captain =>
      'Captains pick the side and run the scorebook. Captain it yourself? '
          'Be Secretary & captain.',
    ClubSetupStepKind.ground => 'So every fixture says where to turn up.',
  };

  static List<ClubSetupStep> steps({
    required List<ClubMemberDetail> members,
    required int teams,
    required int venues,
  }) => <ClubSetupStep>[
    ClubSetupStep(kind: ClubSetupStepKind.players, done: members.length > 1),
    ClubSetupStep(kind: ClubSetupStepKind.team, done: teams > 0),
    ClubSetupStep(
      kind: ClubSetupStepKind.captain,
      done: members.any(
        (ClubMemberDetail m) => m.role == ClubRole.teamCaptain || m.isCaptain == true,
      ),
    ),
    ClubSetupStep(kind: ClubSetupStepKind.ground, done: venues > 0),
  ];

  @override
  bool operator ==(Object other) =>
      other is ClubSetupStep && other.kind == kind && other.done == done;

  @override
  int get hashCode => Object.hash(kind, done);
}
