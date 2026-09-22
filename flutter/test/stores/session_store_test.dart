import 'dart:async';
import 'dart:convert';

import 'package:fishers/config/app_config.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/network_service.dart';
import 'package:fishers/stores/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/stub_client.dart';

/// Who is signed in — `ios/Fishers/ViewModels/SessionStore.swift`.
void main() {
  late InMemoryTokenStore tokens;

  /// `FishersAPI` rides on `NetworkService.shared`, so that is what a test
  /// swaps — the same way `test/services/fishers_api_test.dart` does.
  StubClient serveWith(
    FutureOr<(int, String)> Function(RecordedRequest) handler, {
    Map<String, String> stored = const <String, String>{},
  }) {
    tokens = InMemoryTokenStore(Map<String, String>.of(stored));
    final StubClient client = StubClient(handler);
    NetworkService.shared = NetworkService(
      client: client,
      store: tokens,
      config: AppConfig(
        store: InMemoryConfigStore(),
        environment: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      ),
    );
    return client;
  }

  final String authTokens = jsonEncode(loadFixture('auth_tokens'));
  final String me = jsonEncode(loadFixture('public_user'));

  test('signing in keeps the tokens and the user', () async {
    serveWith((RecordedRequest _) => (200, authTokens));
    final SessionStore session = SessionStore();

    await session.signIn(identifier: 'someone@club.test', password: 'password123');

    expect(session.isAuthenticated, isTrue);
    expect(session.user, isNotNull);
    expect(session.errorMessage, isNull);
    expect(await tokens.read(TokenStore.accessTokenKey), isNotNull);
  });

  /// A wrong password is a 401, and `NetworkService` turns every 401 into
  /// `unauthorized` — "Please sign in again" — whoever asked and whether or
  /// not the call was authenticated. iOS does exactly the same
  /// (`if http.statusCode == 401 { throw APIError.unauthorized }`), so this
  /// asserts the behaviour rather than diverging from it.
  ///
  /// It reads oddly on the sign-in screen: the API said "invalid
  /// credentials" and the person is told to sign in again, which is what they
  /// were doing. Worth fixing — on both platforms at once, since the wording
  /// is not the port's to change on its own.
  test('a wrong password is refused, in the shared 401 wording', () async {
    serveWith((RecordedRequest _) => (401, '{"error":"invalid credentials"}'));
    final SessionStore session = SessionStore();

    await session.signIn(identifier: 'someone@club.test', password: 'wrong');

    expect(session.isAuthenticated, isFalse);
    expect(session.errorMessage, 'Please sign in again');
    expect(session.user, isNull);
  });

  /// A refusal that is *not* a 401 keeps the API's own sentence, which is
  /// written for a person to read.
  test('any other refusal is shown in the API own words', () async {
    serveWith((RecordedRequest _) => (400, '{"error":"that is not an email address"}'));
    final SessionStore session = SessionStore();

    await session.signIn(identifier: 'nonsense', password: 'password123');

    expect(session.isAuthenticated, isFalse);
    expect(session.errorMessage, 'that is not an email address');
  });

  test('bootstrap signs back in from what the store kept', () async {
    serveWith(
      (RecordedRequest _) => (200, me),
      stored: <String, String>{TokenStore.accessTokenKey: 'kept'},
    );
    final SessionStore session = SessionStore();

    await session.bootstrap();

    expect(session.isAuthenticated, isTrue);
    expect(session.user, isNotNull);
  });

  /// A stored token the server no longer accepts is cleared rather than kept:
  /// an app that looks signed in and fails every request is worse than an
  /// honest sign-in screen.
  test('a token the server refuses is thrown away, not kept', () async {
    serveWith(
      (RecordedRequest _) => (401, '{"error":"expired"}'),
      stored: <String, String>{TokenStore.accessTokenKey: 'stale'},
    );
    final SessionStore session = SessionStore();

    await session.bootstrap();

    expect(session.isAuthenticated, isFalse);
    expect(session.user, isNull);
    expect(await tokens.read(TokenStore.accessTokenKey), isNull);
  });

  test('bootstrap with nothing stored asks the server nothing', () async {
    final StubClient client = serveWith((RecordedRequest _) => (200, me));
    final SessionStore session = SessionStore();

    await session.bootstrap();

    expect(client.requests, isEmpty, reason: 'nothing to sign in with');
    expect(session.isAuthenticated, isFalse);
  });

  /// A shared phone must not keep the last person signed in.
  test('signing out clears the tokens', () async {
    serveWith((RecordedRequest _) => (200, authTokens));
    final SessionStore session = SessionStore();
    await session.signIn(identifier: 'someone@club.test', password: 'password123');
    expect(await tokens.read(TokenStore.accessTokenKey), isNotNull);

    await session.signOut();

    expect(session.isAuthenticated, isFalse);
    expect(session.user, isNull);
    expect(await tokens.read(TokenStore.accessTokenKey), isNull);
  });
}
