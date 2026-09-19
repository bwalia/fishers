import 'package:flutter/foundation.dart';

import 'clubs.dart';
import 'json.dart';
import 'rbac.dart';

/// A port of `ios/Fishers/Models/ClubAdmin.swift`.

/// A member as the roster screen needs them: who, what role, how to reach them.
@immutable
class ClubMemberDetail {
  const ClubMemberDetail({
    required this.userId,
    required this.name,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.email,
    this.phone,
    this.isCaptain,
    this.positionRole,
    this.skillLevel,
    this.avatarUrl,
  });

  final String userId;
  final String name;

  /// One of these is absent: people register with an address or a number.
  final String? email;
  final String? phone;
  final ClubRole role;

  /// Captains the side — by role, or a secretary who captains as well. Absent
  /// from an API older than that distinction.
  final bool? isCaptain;
  final String status;
  final DateTime joinedAt;
  final String? positionRole;
  final String? skillLevel;
  final String? avatarUrl;

  String get id => userId;

  factory ClubMemberDetail.fromJson(JsonMap json) => ClubMemberDetail(
    userId: asUuid(json['user_id'], key: 'user_id'),
    name: asString(json['name'], key: 'name'),
    email: asStringOrNull(json['email'], key: 'email'),
    phone: asStringOrNull(json['phone'], key: 'phone'),
    role: ClubRole.fromJson(json['role'], key: 'role'),
    isCaptain: asBoolOrNull(json['is_captain'], key: 'is_captain'),
    status: asString(json['status'], key: 'status'),
    joinedAt: asDate(json['joined_at'], key: 'joined_at'),
    positionRole: asStringOrNull(json['position_role'], key: 'position_role'),
    skillLevel: asStringOrNull(json['skill_level'], key: 'skill_level'),
    avatarUrl: asStringOrNull(json['avatar_url'], key: 'avatar_url'),
  );

  JsonMap toJson() => <String, dynamic>{
    'user_id': userId,
    'name': name,
    'email': email,
    'phone': phone,
    'role': role.toJson(),
    'is_captain': isCaptain,
    'status': status,
    'joined_at': encodeDate(joinedAt),
    'position_role': positionRole,
    'skill_level': skillLevel,
    'avatar_url': avatarUrl,
  };

  bool get isActive => status == 'active';

  /// The role as the picker shows it — a secretary may captain too.
  RoleChoice get roleChoice => RoleChoice(role: role, isCaptain: isCaptain ?? false);

  /// Whichever way this member can actually be reached.
  String get contact => email ?? phone ?? 'No contact details';

  /// "Batter · Club standard" under the name.
  String get subtitle =>
      <String?>[positionRole, skillLevel].nonNulls.toList(growable: false).join(' · ');

  @override
  bool operator ==(Object other) =>
      other is ClubMemberDetail &&
      other.userId == userId &&
      other.name == name &&
      other.email == email &&
      other.phone == phone &&
      other.role == role &&
      other.isCaptain == isCaptain &&
      other.status == status &&
      other.joinedAt == joinedAt &&
      other.positionRole == positionRole &&
      other.skillLevel == skillLevel &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(
    userId,
    name,
    email,
    phone,
    role,
    isCaptain,
    status,
    joinedAt,
    positionRole,
    skillLevel,
    avatarUrl,
  );
}

/// A link that puts whoever follows it into the club, once they have an
/// account. Single use — the API refuses a second accept.
@immutable
class ClubInvite {
  const ClubInvite({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.token,
    required this.status,
    this.invitedEmail,
  });

  final String id;
  final String targetType;
  final String targetId;
  final String token;
  final String status;
  final String? invitedEmail;

  factory ClubInvite.fromJson(JsonMap json) => ClubInvite(
    id: asUuid(json['id'], key: 'id'),
    targetType: asString(json['target_type'], key: 'target_type'),
    targetId: asUuid(json['target_id'], key: 'target_id'),
    token: asString(json['token'], key: 'token'),
    status: asString(json['status'], key: 'status'),
    invitedEmail: asStringOrNull(json['invited_email'], key: 'invited_email'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'target_type': targetType,
    'target_id': targetId,
    'token': token,
    'status': status,
    'invited_email': invitedEmail,
  };

  /// The web app resolves this; it is what a secretary actually sends.
  Uri? url({required String webBase}) => Uri.tryParse('$webBase/invite/$token');

  @override
  bool operator ==(Object other) =>
      other is ClubInvite &&
      other.id == id &&
      other.targetType == targetType &&
      other.targetId == targetId &&
      other.token == token &&
      other.status == status &&
      other.invitedEmail == invitedEmail;

  @override
  int get hashCode => Object.hash(id, targetType, targetId, token, status, invitedEmail);
}

/// Something that happened which you need to know about.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.sentAt,
    this.readAt,
  });

  final String id;
  final String type;

  /// The text values of the payload. The API sends nulls (`team_name` on a
  /// club invite) and non-strings too, which a plain `Map<String, String>`
  /// refuses — and one such row used to fail the whole page.
  final Map<String, String> payload;
  final DateTime sentAt;
  final DateTime? readAt;

  factory AppNotification.fromJson(JsonMap json) {
    final Map<String, JsonValue> raw = JsonValue.mapFrom(json['payload']) ?? <String, JsonValue>{};
    return AppNotification(
      id: asUuid(json['id'], key: 'id'),
      type: asString(json['type'], key: 'type'),
      payload: <String, String>{
        for (final MapEntry<String, JsonValue> e in raw.entries)
          if (e.value.asTextOrNull case final String text) e.key: text,
      },
      sentAt: asDate(json['sent_at'], key: 'sent_at'),
      readAt: asDateOrNull(json['read_at'], key: 'read_at'),
    );
  }

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'type': type,
    'payload': payload,
    'sent_at': encodeDate(sentAt),
    'read_at': encodeDateOrNull(readAt),
  };

  bool get isUnread => readAt == null;

  /// One line of plain English. A player is not going to read
  /// `match_terms_proposed`. The same words the web uses.
  String get line {
    final String sides =
        '${payload["home_name"] ?? "A side"} v ${payload["away_name"] ?? "another"}';
    switch (type) {
      case 'match_terms_proposed':
        return '$sides — the other captain has proposed the terms. Tap to agree.';
      case 'match_pick_your_xi':
        return '$sides — the toss is done. Pick your side.';
      case 'match_terms_agreed':
        return 'Both captains have agreed the terms. You can do the toss.';
      case 'match_book_handed_over':
        return "$sides — you have the book. You're scoring from the next ball.";
      case 'fixture_scheduled':
        return '${payload["title"] ?? "A fixture"} — can you play?';
      case 'player_responded':
        return '${payload["player"] ?? "A player"} answered for '
            '${payload["title"] ?? "a fixture"}.';
      case 'invite':
        final String from = payload['inviter'] == null ? '' : ' ${payload["inviter"]} invited you.';
        if (payload['team_name'] case final String team) {
          return '${payload["club_name"] ?? "A club"} wants you in their $team.$from';
        }
        if (payload['event_title'] case final String event) {
          return "You're invited: $event.$from";
        }
        return '${payload["club_name"] ?? "A club"} wants you in the club.$from';
      case 'profile_nudge':
        final String percent = payload['percent'] == null
            ? ''
            : " — you're ${payload["percent"]}% there";
        return 'Finish your profile$percent. Captains pick players they can see.';
      case 'invite_accepted':
        final String into =
            payload['team_name'] ?? payload['event_title'] ?? payload['club_name'] ?? 'the club';
        return "${payload["player"] ?? "A player"} accepted — they're in $into.";
      default:
        return type.replaceAll('_', ' ');
    }
  }

  /// Which fixture, when there are several against the same side.
  DateTime? get when => tryDate(payload['start_at']);

  /// The match this is about, when it is about one.
  String? get matchId => tryUuid(payload['match_id']);

  /// The fixture a tap should open, when there is one.
  String? get eventId => tryUuid(payload['event_id']);

  @override
  bool operator ==(Object other) =>
      other is AppNotification &&
      other.id == id &&
      other.type == type &&
      mapEquals(other.payload, payload) &&
      other.sentAt == sentAt &&
      other.readAt == readAt;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    Object.hashAllUnordered(
      payload.entries.map((MapEntry<String, String> e) => Object.hash(e.key, e.value)),
    ),
    sentAt,
    readAt,
  );
}

/// A page of anything the API pages.
@immutable
class ApiPage<T> {
  const ApiPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.hasMore,
  });

  final List<T> items;
  final int total;
  final int page;
  final int perPage;
  final bool hasMore;

  factory ApiPage.fromJson(JsonMap json, T Function(JsonMap) item) => ApiPage<T>(
    items: asList(json['items'], (Object? v) => item(asMap(v, key: 'items'))),
    total: asInt(json['total'], key: 'total'),
    page: asInt(json['page'], key: 'page'),
    perPage: asInt(json['per_page'], key: 'per_page'),
    hasMore: asBool(json['has_more'], key: 'has_more'),
  );

  JsonMap toJson(JsonMap Function(T) item) => <String, dynamic>{
    'items': items.map(item).toList(growable: false),
    'total': total,
    'page': page,
    'per_page': perPage,
    'has_more': hasMore,
  };

  @override
  bool operator ==(Object other) =>
      other is ApiPage<T> &&
      listEquals(other.items, items) &&
      other.total == total &&
      other.page == page &&
      other.perPage == perPage &&
      other.hasMore == hasMore;

  @override
  int get hashCode => Object.hash(Object.hashAll(items), total, page, perPage, hasMore);
}

@immutable
class NotificationFeed {
  const NotificationFeed({
    required this.unread,
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.hasMore,
    required this.kinds,
  });

  final int unread;
  final List<AppNotification> items;

  /// How many match the current filter, across every page.
  final int total;
  final int page;
  final int perPage;
  final bool hasMore;

  /// Every kind this person has been sent, so a filter only offers what would
  /// actually match something.
  final List<String> kinds;

  /// An older API answered with just `unread` and `items`. Defaulting rather
  /// than failing means an app already on somebody's phone keeps working
  /// against a server that has not been deployed yet.
  factory NotificationFeed.fromJson(JsonMap json) {
    final List<AppNotification> items = asListOrEmpty(
      json['items'],
      (Object? v) => AppNotification.fromJson(asMap(v, key: 'items')),
    );
    return NotificationFeed(
      unread: asIntOrNull(json['unread'], key: 'unread') ?? 0,
      items: items,
      total: asIntOrNull(json['total'], key: 'total') ?? items.length,
      page: asIntOrNull(json['page'], key: 'page') ?? 1,
      perPage: asIntOrNull(json['per_page'], key: 'per_page') ?? items.length,
      hasMore: asBoolOrNull(json['has_more'], key: 'has_more') ?? false,
      kinds: asListOrEmpty(json['kinds'], (Object? v) => asString(v, key: 'kinds')),
    );
  }

  JsonMap toJson() => <String, dynamic>{
    'unread': unread,
    'items': items.map((AppNotification n) => n.toJson()).toList(growable: false),
    'total': total,
    'page': page,
    'per_page': perPage,
    'has_more': hasMore,
    'kinds': kinds,
  };

  @override
  bool operator ==(Object other) =>
      other is NotificationFeed &&
      other.unread == unread &&
      listEquals(other.items, items) &&
      other.total == total &&
      other.page == page &&
      other.perPage == perPage &&
      other.hasMore == hasMore &&
      listEquals(other.kinds, kinds);

  @override
  int get hashCode => Object.hash(
    unread,
    Object.hashAll(items),
    total,
    page,
    perPage,
    hasMore,
    Object.hashAll(kinds),
  );
}

/// The knobs a club secretary can turn.
@immutable
class ClubSettings {
  const ClubSettings({
    required this.selectionAutonomy,
    required this.confirmLeadHours,
    required this.dropLeadHours,
    required this.feeChaseAfterHours,
    required this.feeChaseMaxReminders,
  });

  /// `off` | `suggest` | `auto_publish`
  final String selectionAutonomy;
  final int confirmLeadHours;
  final int dropLeadHours;
  final int feeChaseAfterHours;
  final int feeChaseMaxReminders;

  factory ClubSettings.fromJson(JsonMap json) => ClubSettings(
    selectionAutonomy: asString(json['selection_autonomy'], key: 'selection_autonomy'),
    confirmLeadHours: asInt(json['confirm_lead_hours'], key: 'confirm_lead_hours'),
    dropLeadHours: asInt(json['drop_lead_hours'], key: 'drop_lead_hours'),
    feeChaseAfterHours: asInt(json['fee_chase_after_hours'], key: 'fee_chase_after_hours'),
    feeChaseMaxReminders: asInt(json['fee_chase_max_reminders'], key: 'fee_chase_max_reminders'),
  );

  JsonMap toJson() => <String, dynamic>{
    'selection_autonomy': selectionAutonomy,
    'confirm_lead_hours': confirmLeadHours,
    'drop_lead_hours': dropLeadHours,
    'fee_chase_after_hours': feeChaseAfterHours,
    'fee_chase_max_reminders': feeChaseMaxReminders,
  };

  ClubSettings copyWith({
    String? selectionAutonomy,
    int? confirmLeadHours,
    int? dropLeadHours,
    int? feeChaseAfterHours,
    int? feeChaseMaxReminders,
  }) => ClubSettings(
    selectionAutonomy: selectionAutonomy ?? this.selectionAutonomy,
    confirmLeadHours: confirmLeadHours ?? this.confirmLeadHours,
    dropLeadHours: dropLeadHours ?? this.dropLeadHours,
    feeChaseAfterHours: feeChaseAfterHours ?? this.feeChaseAfterHours,
    feeChaseMaxReminders: feeChaseMaxReminders ?? this.feeChaseMaxReminders,
  );

  @override
  bool operator ==(Object other) =>
      other is ClubSettings &&
      other.selectionAutonomy == selectionAutonomy &&
      other.confirmLeadHours == confirmLeadHours &&
      other.dropLeadHours == dropLeadHours &&
      other.feeChaseAfterHours == feeChaseAfterHours &&
      other.feeChaseMaxReminders == feeChaseMaxReminders;

  @override
  int get hashCode => Object.hash(
    selectionAutonomy,
    confirmLeadHours,
    dropLeadHours,
    feeChaseAfterHours,
    feeChaseMaxReminders,
  );
}

enum SelectionAutonomy {
  off('off'),
  suggest('suggest'),
  autoPublish('auto_publish');

  const SelectionAutonomy(this.wire);

  final String wire;

  String get label => switch (this) {
    SelectionAutonomy.off => 'Off',
    SelectionAutonomy.suggest => 'Suggests',
    SelectionAutonomy.autoPublish => 'Publishes',
  };

  String get blurb => switch (this) {
    SelectionAutonomy.off => 'The assistant does not pick sides. Captains use the ranking instead.',
    SelectionAutonomy.suggest => 'The assistant proposes a side; a captain publishes it.',
    SelectionAutonomy.autoPublish => 'The assistant names and announces the side on its own.',
  };

  static SelectionAutonomy? named(String? raw) =>
      enumFromRaw(SelectionAutonomy.values, raw, (SelectionAutonomy a) => a.wire);
}
