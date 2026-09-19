import 'package:flutter/foundation.dart';

import 'json.dart';

/// A port of `ios/Fishers/Models/Onboarding.swift`.

/// The two ways into Fishers: one builds a club, the other joins one. Asked
/// once, so the first screens can walk the right path.
enum RoleIntent {
  secretary('secretary'),
  player('player');

  const RoleIntent(this.wire);

  final String wire;

  String get title => switch (this) {
    RoleIntent.secretary => 'I run a club',
    RoleIntent.player => 'I play for a club',
  };

  String get detail => switch (this) {
    RoleIntent.secretary =>
      'Secretary or organiser. You set up the club, its teams and fixtures, '
          'and bring the players in.',
    RoleIntent.player =>
      "Set up your player profile, send it to your club's secretary, and "
          'accept their invite.',
  };

  static RoleIntent? named(String? raw) =>
      enumFromRaw(RoleIntent.values, raw, (RoleIntent r) => r.wire);

  String toJson() => wire;
}

/// `GET /me/verification`.
@immutable
class VerificationStatus {
  const VerificationStatus({
    required this.enabled,
    required this.email,
    required this.phone,
    required this.verificationRequired,
  });

  /// Whether the server asks for confirmation at all.
  final bool enabled;
  final VerificationChannelStatus email;
  final VerificationChannelStatus phone;

  /// Starting a club or accepting an invite is refused until one is verified.
  final bool verificationRequired;

  factory VerificationStatus.fromJson(JsonMap json) => VerificationStatus(
    enabled: asBool(json['enabled'], key: 'enabled'),
    email: VerificationChannelStatus.fromJson(asMap(json['email'], key: 'email')),
    phone: VerificationChannelStatus.fromJson(asMap(json['phone'], key: 'phone')),
    verificationRequired: asBool(json['verification_required'], key: 'verification_required'),
  );

  JsonMap toJson() => <String, dynamic>{
    'enabled': enabled,
    'email': email.toJson(),
    'phone': phone.toJson(),
    'verification_required': verificationRequired,
  };

  VerificationChannelStatus operator [](VerificationChannel channel) =>
      channel == VerificationChannel.email ? email : phone;

  /// The ways a code can actually be sent, email first.
  List<VerificationChannel> get channels => <VerificationChannel>[
    for (final VerificationChannel channel in VerificationChannel.values)
      if (this[channel].available) channel,
  ];

  /// A step worth showing: the server asks, and can send a code.
  bool get canVerify => enabled && channels.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is VerificationStatus &&
      other.enabled == enabled &&
      other.email == email &&
      other.phone == phone &&
      other.verificationRequired == verificationRequired;

  @override
  int get hashCode => Object.hash(enabled, email, phone, verificationRequired);
}

/// `VerificationStatus.Channel` on iOS.
@immutable
class VerificationChannelStatus {
  const VerificationChannelStatus({required this.verified, required this.available, this.address});

  final String? address;
  final bool verified;

  /// The server can send a code this way (it has the address, and a sender
  /// configured for it).
  final bool available;

  factory VerificationChannelStatus.fromJson(JsonMap json) => VerificationChannelStatus(
    address: asStringOrNull(json['address'], key: 'address'),
    verified: asBool(json['verified'], key: 'verified'),
    available: asBool(json['available'], key: 'available'),
  );

  JsonMap toJson() => <String, dynamic>{
    'address': address,
    'verified': verified,
    'available': available,
  };

  @override
  bool operator ==(Object other) =>
      other is VerificationChannelStatus &&
      other.address == address &&
      other.verified == verified &&
      other.available == available;

  @override
  int get hashCode => Object.hash(address, verified, available);
}

enum VerificationChannel {
  email('email'),
  phone('phone');

  const VerificationChannel(this.wire);

  final String wire;

  String get noun => this == VerificationChannel.email ? 'email' : 'phone number';

  /// How the code travels, for the sentence under the field.
  String get sentVerb => this == VerificationChannel.email ? 'emailed' : 'sent on WhatsApp';
}

/// `POST /me/verification/{channel}`.
@immutable
class VerificationSent {
  const VerificationSent({required this.sentTo, required this.resendAfter});

  final String sentTo;
  final int resendAfter;

  factory VerificationSent.fromJson(JsonMap json) => VerificationSent(
    sentTo: asString(json['sent_to'], key: 'sent_to'),
    resendAfter: asInt(json['resend_after'], key: 'resend_after'),
  );

  JsonMap toJson() => <String, dynamic>{'sent_to': sentTo, 'resend_after': resendAfter};

  @override
  bool operator ==(Object other) =>
      other is VerificationSent && other.sentTo == sentTo && other.resendAfter == resendAfter;

  @override
  int get hashCode => Object.hash(sentTo, resendAfter);
}

/// An invitation addressed to this account, from `GET /invites/mine`.
@immutable
class PendingInvite {
  const PendingInvite({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.token,
    required this.status,
    required this.createdAt,
    this.targetName,
    this.invitedByName,
  });

  final String id;
  final String targetType;
  final String targetId;
  final String token;
  final String status;
  final DateTime createdAt;

  /// The club, "team · club", or fixture — present on your own invites.
  final String? targetName;
  final String? invitedByName;

  factory PendingInvite.fromJson(JsonMap json) => PendingInvite(
    id: asUuid(json['id'], key: 'id'),
    targetType: asString(json['target_type'], key: 'target_type'),
    targetId: asUuid(json['target_id'], key: 'target_id'),
    token: asString(json['token'], key: 'token'),
    status: asString(json['status'], key: 'status'),
    createdAt: asDate(json['created_at'], key: 'created_at'),
    targetName: asStringOrNull(json['target_name'], key: 'target_name'),
    invitedByName: asStringOrNull(json['invited_by_name'], key: 'invited_by_name'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'target_type': targetType,
    'target_id': targetId,
    'token': token,
    'status': status,
    'created_at': encodeDate(createdAt),
    'target_name': targetName,
    'invited_by_name': invitedByName,
  };

  bool get isPending => status == 'pending';

  String get title =>
      targetName ?? 'A ${targetType == "event" ? "fixture" : targetType} invitation';

  @override
  bool operator ==(Object other) =>
      other is PendingInvite &&
      other.id == id &&
      other.targetType == targetType &&
      other.targetId == targetId &&
      other.token == token &&
      other.status == status &&
      other.createdAt == createdAt &&
      other.targetName == targetName &&
      other.invitedByName == invitedByName;

  @override
  int get hashCode =>
      Object.hash(id, targetType, targetId, token, status, createdAt, targetName, invitedByName);
}

/// `POST /me/share-link`.
@immutable
class ShareLinkToken {
  const ShareLinkToken({required this.token});

  final String token;

  factory ShareLinkToken.fromJson(JsonMap json) =>
      ShareLinkToken(token: asString(json['token'], key: 'token'));

  JsonMap toJson() => <String, dynamic>{'token': token};

  @override
  bool operator ==(Object other) => other is ShareLinkToken && other.token == token;

  @override
  int get hashCode => token.hashCode;
}
