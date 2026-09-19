import 'package:flutter/foundation.dart';

import '../models/json.dart';

/// The config half of `ios/Fishers/Services/SocialAuth.swift`.
///
/// Scope: **v1 on Android ships Google and email/password only.** Sign in with
/// Apple is a deliberate gap — on Android it would be a web redirect rather
/// than a native flow, and that cost is not worth paying before the app is in
/// people's hands. So `POST /auth/apple` is never called and the button is
/// never rendered. The auth screen still drives its buttons off the server's
/// config, exactly as iOS's does, so a third provider slots in without rework.
///
/// The sign-in call itself lands with the auth layer; this file carries the
/// shape the server answers `GET /auth/google` with, which is what decides
/// whether the button is offered at all.
@immutable
class SocialAuthConfig {
  const SocialAuthConfig({required this.enabled, this.clientId, this.androidClientId});

  final bool enabled;

  /// The web OAuth client. On iOS this is the fallback when no platform client
  /// is configured; on Android it is the *server* client id that
  /// `google_sign_in` wants as its `serverClientId`, which is what makes the
  /// id token verifiable by the Fishers API.
  final String? clientId;

  /// iOS reads `ios_client_id` here. Android's equivalent key is not one the
  /// API sends today — see `flutter/PARITY.md`; until it does, [clientId] is
  /// what the button uses.
  final String? androidClientId;

  factory SocialAuthConfig.fromJson(JsonMap json) => SocialAuthConfig(
    enabled: asBool(json['enabled'], key: 'enabled'),
    clientId: asStringOrNull(json['client_id'], key: 'client_id'),
    androidClientId: asStringOrNull(json['android_client_id'], key: 'android_client_id'),
  );

  JsonMap toJson() => <String, dynamic>{
    'enabled': enabled,
    'client_id': clientId,
    'android_client_id': androidClientId,
  };

  /// Whether the Google button can be offered: the server has it switched on
  /// and has given a client id the phone can actually use.
  bool get googleAvailable => enabled && (androidClientId ?? clientId) != null;

  /// The id `google_sign_in` is configured with.
  String? get serverClientId => androidClientId ?? clientId;

  @override
  bool operator ==(Object other) =>
      other is SocialAuthConfig &&
      other.enabled == enabled &&
      other.clientId == clientId &&
      other.androidClientId == androidClientId;

  @override
  int get hashCode => Object.hash(enabled, clientId, androidClientId);
}

/// A social sign-in result ready to POST to the API.
@immutable
class SocialCredential {
  const SocialCredential({required this.provider, required this.identityToken});

  /// Only `google` in v1 — see the note on [SocialAuthConfig].
  final SocialProvider provider;
  final String identityToken;

  @override
  bool operator ==(Object other) =>
      other is SocialCredential &&
      other.provider == provider &&
      other.identityToken == identityToken;

  @override
  int get hashCode => Object.hash(provider, identityToken);
}

enum SocialProvider {
  google('google');

  const SocialProvider(this.wire);

  final String wire;
}
