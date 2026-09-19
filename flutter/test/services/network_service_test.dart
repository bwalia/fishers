import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fishers/config/app_config.dart';
import 'package:fishers/models/json.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/network_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_client.dart';

/// The Android half of `ios/FishersTests/NetworkRefreshTests.swift`, plus the
/// rest of what `NetworkService.swift` promises: the `/api/v1` prefix, the
/// bearer token, refresh-then-retry **once**, the multipart upload, and the
/// error the person holding the phone actually reads.
void main() {
  AppConfig configAt(String base) => AppConfig(
    store: InMemoryConfigStore(),
    environment: <String, String>{AppConfig.apiEnvKey: base},
  );

  ({NetworkService service, StubClient client, InMemoryTokenStore store}) build(
    FutureOr<(int, String)> Function(RecordedRequest) handler, {
    String base = 'https://int.fishers.cloud',
  }) {
    final StubClient client = StubClient(handler);
    final InMemoryTokenStore store = InMemoryTokenStore();
    return (
      service: NetworkService(client: client, store: store, config: configAt(base)),
      client: client,
      store: store,
    );
  }

  group('the shape of a request', () {
    test('carries the base URL, the /api/v1 prefix and the bearer token', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{"ok":true}'),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');
      await t.service.request('GET', '/clubs');

      expect(t.client.lastRequest.url.toString(), 'https://int.fishers.cloud/api/v1/clubs');
      expect(t.client.lastRequest.bearer, 'Bearer at');
      expect(t.client.lastRequest.headers['Content-Type'], 'application/json');
      expect(t.client.lastRequest.method, 'GET');
    });

    test('an unauthorized call carries no token, even when one is held', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{}'),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');
      await t.service.request('POST', '/auth/login', body: <String, dynamic>{}, authorized: false);
      expect(t.client.lastRequest.bearer, isNull);
    });

    test('a body is JSON, and a GET has none', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{}'),
      );
      await t.service.request('POST', '/clubs', body: <String, dynamic>{'name': 'Lords'});
      expect(t.client.lastRequest.json, <String, dynamic>{'name': 'Lords'});

      await t.service.request('GET', '/clubs');
      expect(t.client.lastRequest.body, isEmpty);
    });

    test('a query string survives the prefix', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{}'),
      );
      await t.service.request('GET', '/events?page=1&per_page=200&');
      expect(
        t.client.lastRequest.url.toString(),
        'https://int.fishers.cloud/api/v1/events?page=1&per_page=200&',
      );
    });
  });

  group('tokens', () {
    test('are written to secure storage under the keys iOS uses', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{}'),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');
      expect(t.store.values, <String, String>{'access_token': 'at', 'refresh_token': 'rt'});
    });

    test('are reloaded on launch', () async {
      final StubClient client = StubClient((RecordedRequest _) => (200, '{"ok":true}'));
      final InMemoryTokenStore store = InMemoryTokenStore(<String, String>{
        'access_token': 'from-disk',
        'refresh_token': 'refresh-from-disk',
      });
      final NetworkService service = NetworkService(
        client: client,
        store: store,
        config: configAt('https://int.fishers.cloud'),
      );
      expect(service.hasSession, isFalse, reason: 'nothing is read until it is asked for');

      await service.loadTokensFromStore();
      expect(service.hasSession, isTrue);
      await service.request('GET', '/me');
      expect(client.lastRequest.bearer, 'Bearer from-disk');
    });

    test('clearing takes them off the device', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{}'),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');
      await t.service.clearTokens();
      expect(t.store.values, isEmpty);
      expect(t.service.hasSession, isFalse);
    });
  });

  group('refresh on 401, then one retry', () {
    test('the refreshed token is the one used afterwards', () async {
      String? lastBearer;
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build((
        RecordedRequest request,
      ) {
        if (request.path.endsWith('/auth/refresh')) {
          return (200, '{"access_token":"fresh","refresh_token":"rt-2"}');
        }
        if (request.bearer == 'Bearer stale') return (401, '{}');
        lastBearer = request.bearer;
        return (200, '{"ok":true}');
      });
      await t.service.setTokens(access: 'stale', refresh: 'rt-1');

      final Object? reply = await t.service.request('GET', '/clubs');
      expect(reply, <String, dynamic>{'ok': true});
      expect(lastBearer, 'Bearer fresh');
      expect(t.client.countOf('/auth/refresh'), 1);
      expect(
        t.store.values,
        <String, String>{'access_token': 'fresh', 'refresh_token': 'rt-2'},
        reason: 'the rotated pair has to reach storage, or the next launch is signed out',
      );
    });

    test('refresh goes to POST /api/v1/auth/refresh with the refresh token', () async {
      late RecordedRequest refresh;
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build((
        RecordedRequest request,
      ) {
        if (request.path.endsWith('/auth/refresh')) {
          refresh = request;
          return (200, '{"access_token":"fresh","refresh_token":"rt-2"}');
        }
        return request.bearer == 'Bearer stale' ? (401, '{}') : (200, '{"ok":true}');
      });
      await t.service.setTokens(access: 'stale', refresh: 'rt-1');
      await t.service.request('GET', '/clubs');

      expect(refresh.method, 'POST');
      expect(refresh.url.toString(), 'https://int.fishers.cloud/api/v1/auth/refresh');
      expect(refresh.json, <String, dynamic>{'refresh_token': 'rt-1'});
      expect(refresh.bearer, isNull, reason: 'the refresh call must not recurse through auth');
    });

    test('six calls refreshing together share one refresh', () async {
      // The API rotates refresh tokens — issuing a new pair revokes the old
      // one — so sending the same token six times would sign a scorer out in
      // the middle of an over.
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build((
        RecordedRequest request,
      ) async {
        if (request.path.endsWith('/auth/refresh')) {
          // A real refresh takes a round trip; the race only shows up if this
          // one does too.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return (200, '{"access_token":"fresh","refresh_token":"rt-2"}');
        }
        if (request.bearer == 'Bearer stale') return (401, '{"error":"invalid token"}');
        return (200, '{"ok":true}');
      });
      await t.service.setTokens(access: 'stale', refresh: 'rt-1');

      final List<Object?> replies = await Future.wait<Object?>(<Future<Object?>>[
        for (int i = 0; i < 6; i++) t.service.request('GET', '/clubs'),
      ]);

      expect(replies.every((Object? r) => (r! as Map<String, dynamic>)['ok'] == true), isTrue);
      expect(
        t.client.countOf('/auth/refresh'),
        1,
        reason: 'six calls refreshing together must share one refresh',
      );
    });

    test('a server that keeps answering 401 does not recurse', () async {
      int refreshes = 0;
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build((
        RecordedRequest request,
      ) {
        if (request.path.endsWith('/auth/refresh')) {
          refreshes += 1;
          return (200, '{"access_token":"still-no","refresh_token":"rt-2"}');
        }
        return (401, '{"error":"nope"}');
      });
      await t.service.setTokens(access: 'stale', refresh: 'rt-1');

      await expectLater(
        t.service.request('GET', '/clubs'),
        throwsA(
          isA<ApiException>().having((ApiException e) => e.kind, 'kind', ApiErrorKind.unauthorized),
        ),
      );
      expect(refreshes, 1, reason: 'refresh once, retry once, then give up');
      expect(t.client.countOf('/clubs'), 2);
    });

    test('a failed refresh clears the session rather than leaving it half-signed-in', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build((
        RecordedRequest request,
      ) {
        if (request.path.endsWith('/auth/refresh')) return (401, '{"error":"revoked"}');
        return (401, '{}');
      });
      await t.service.setTokens(access: 'stale', refresh: 'rt-1');

      await expectLater(t.service.request('GET', '/clubs'), throwsA(isA<ApiException>()));
      expect(t.store.values, isEmpty);
      expect(t.service.hasSession, isFalse);
    });

    test('with no refresh token, a 401 is simply a 401', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (401, '{}'),
      );
      await t.service.setTokens(access: 'at');

      await expectLater(t.service.request('GET', '/clubs'), throwsA(isA<ApiException>()));
      expect(t.client.countOf('/auth/refresh'), 0);
      expect(t.client.countOf('/clubs'), 1);
    });

    test('an unauthorized call is never retried', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (401, '{}'),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');
      await expectLater(
        t.service.request('POST', '/auth/login', authorized: false),
        throwsA(isA<ApiException>()),
      );
      expect(t.client.countOf('/auth/refresh'), 0);
    });
  });

  group('the stream is signed like any other request', () {
    test('a signed request carries the bearer and the /api/v1 path', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{}'),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');
      final request = await t.service.signedRequest('/stream');
      expect(request, isNotNull);
      expect(request!.url.toString(), 'https://int.fishers.cloud/api/v1/stream');
      expect(request.headers['Authorization'], 'Bearer at');
    });

    test('with only a refresh token, it renews first', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build((
        RecordedRequest request,
      ) {
        if (request.path.endsWith('/auth/refresh')) {
          return (200, '{"access_token":"fresh","refresh_token":"rt-2"}');
        }
        return (200, '{}');
      });
      await t.service.setTokens(refresh: 'rt-1');

      final request = await t.service.signedRequest('/stream');
      expect(request!.headers['Authorization'], 'Bearer fresh');
    });

    test('with no session at all, there is nothing to sign', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{}'),
      );
      expect(await t.service.signedRequest('/stream'), isNull);
    });

    test('renewSession swallows a failure — the reader retries on its own', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (401, '{}'),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');
      await t.service.renewSession();
      expect(t.service.hasSession, isFalse, reason: 'a revoked pair is cleared');
    });
  });

  group('errors say something useful', () {
    test('the API\'s own sentence is what a person reads', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (400, '{"error":"that is not a JPEG — try a photo"}'),
      );
      try {
        await t.service.request('GET', '/me');
        fail('expected a refusal');
      } on ApiException catch (error) {
        expect(error.friendlyMessage, 'that is not a JPEG — try a photo');
        expect(error.errorDescription, startsWith('HTTP 400'));
      }
    });

    test('an unverified account is recognised, so the app can ask for the code', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) =>
            (403, '{"code":"unverified","error":"confirm your email or phone number first"}'),
      );
      try {
        await t.service.request('POST', '/clubs');
        fail('expected a refusal');
      } on ApiException catch (error) {
        expect(error.isUnverified, isTrue);
        expect(error.code, 'unverified');
      }
    });

    test('a body that is not JSON falls back to the plumbing', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (502, '<html>gateway</html>'),
      );
      try {
        await t.service.request('GET', '/me');
        fail('expected a refusal');
      } on ApiException catch (error) {
        expect(error.friendlyMessage, 'HTTP 502: <html>gateway</html>');
        expect(error.code, isNull);
      }
    });

    test('a server that cannot be reached names the host it tried', () async {
      final StubClient client = StubClient((RecordedRequest _) => throw const SocketishError());
      final NetworkService service = NetworkService(
        client: client,
        store: InMemoryTokenStore(),
        config: configAt('https://acc.fishers.cloud'),
      );
      try {
        await service.request('GET', '/me');
        fail('expected a refusal');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.unreachable);
        expect(error.errorDescription, contains('acc.fishers.cloud'));
      }
    });

    test('a body that is not the shape the model wants is a decode error', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{"not":"a club"}'),
      );
      await expectLater(
        t.service.requestObject('GET', '/clubs/x', (JsonMap json) => asString(json['name'])),
        throwsA(
          isA<ApiException>().having((ApiException e) => e.kind, 'kind', ApiErrorKind.decoding),
        ),
      );
    });
  });

  group('decoding', () {
    test('reads a timestamp with or without fractional seconds', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (
          200,
          '{"a":"2026-09-14T08:00:00.123456Z","b":"2026-09-14T08:00:00Z",'
              '"c":"2026-09-14T09:00:00+01:00"}',
        ),
      );
      final JsonMap json = asMap(await t.service.request('GET', '/x'));
      expect(asDate(json['a']), DateTime.utc(2026, 9, 14, 8, 0, 0, 123, 456));
      expect(asDate(json['b']), DateTime.utc(2026, 9, 14, 8));
      expect(
        asDate(json['c']),
        DateTime.utc(2026, 9, 14, 8),
        reason: 'an offset is honoured, not ignored',
      );
    });

    test('refuses a day where an instant was promised', () {
      expect(() => asDate('2026-09-14'), throwsA(isA<JsonDecodeException>()));
      expect(() => asDate('sometime on Tuesday'), throwsA(isA<JsonDecodeException>()));
    });

    test('an empty body is null, not a crash', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (204, ''),
      );
      expect(await t.service.request('DELETE', '/x'), isNull);
      await t.service.requestVoid('DELETE', '/x');
    });

    test('a list comes back typed', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '[{"n":"a"},{"n":"b"}]'),
      );
      final List<String> names = await t.service.requestList(
        'GET',
        '/x',
        (JsonMap json) => asString(json['n']),
      );
      expect(names, <String>['a', 'b']);
    });

    test('an object where a list was promised is a decode error', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (200, '{"n":"a"}'),
      );
      await expectLater(
        t.service.requestList('GET', '/x', (JsonMap json) => asString(json['n'])),
        throwsA(
          isA<ApiException>().having((ApiException e) => e.kind, 'kind', ApiErrorKind.decoding),
        ),
      );
    });
  });

  group('the multipart upload', () {
    test('sends one file, one field, with the boundary in the header', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (
          200,
          '{"id":"11111111-1111-1111-1111-111111111111",'
              '"name":"Pat","sports_played":[]}',
        ),
      );
      await t.service.setTokens(access: 'at', refresh: 'rt');

      await t.service.upload(
        path: '/me/avatar',
        fileName: 'avatar.jpg',
        mimeType: 'image/jpeg',
        data: Uint8List.fromList(<int>[1, 2, 3, 4]),
        decode: (JsonMap json) => asString(json['name']),
      );

      final RecordedRequest request = t.client.lastRequest;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/me/avatar');
      expect(request.bearer, 'Bearer at');

      final String contentType = request.headers['Content-Type']!;
      expect(contentType, startsWith('multipart/form-data; boundary=fishers.'));
      final String boundary = contentType.split('boundary=').last;

      final String body = latin1.decode(request.bodyBytes);
      expect(body, startsWith('--$boundary\r\n'));
      expect(body, contains('Content-Disposition: form-data; name="file"; filename="avatar.jpg"'));
      expect(body, contains('Content-Type: image/jpeg'));
      expect(body, endsWith('\r\n--$boundary--\r\n'));
      expect(request.bodyBytes, containsAllInOrder(<int>[1, 2, 3, 4]));
    });

    test('renews before sending, rather than rebuilding a photo\'s body', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build((
        RecordedRequest request,
      ) {
        if (request.path.endsWith('/auth/refresh')) {
          return (200, '{"access_token":"fresh","refresh_token":"rt-2"}');
        }
        return (200, '{"name":"Pat"}');
      });
      await t.service.setTokens(refresh: 'rt-1');

      await t.service.upload(
        path: '/me/avatar',
        fileName: 'avatar.jpg',
        mimeType: 'image/jpeg',
        data: Uint8List.fromList(<int>[9]),
        decode: (JsonMap json) => asString(json['name']),
      );

      expect(t.client.paths.first, endsWith('/auth/refresh'));
      expect(t.client.lastRequest.bearer, 'Bearer fresh');
      expect(t.client.countOf('/me/avatar'), 1, reason: 'the photo is never sent twice');
    });

    test('a refusal carries the API\'s sentence', () async {
      final ({NetworkService service, StubClient client, InMemoryTokenStore store}) t = build(
        (RecordedRequest _) => (415, '{"error":"that is not a photo"}'),
      );
      await t.service.setTokens(access: 'at');
      try {
        await t.service.upload(
          path: '/me/avatar',
          fileName: 'avatar.jpg',
          mimeType: 'image/jpeg',
          data: Uint8List.fromList(<int>[1]),
          decode: (JsonMap json) => json,
        );
        fail('expected a refusal');
      } on ApiException catch (error) {
        expect(error.friendlyMessage, 'that is not a photo');
      }
    });
  });
}

/// Stands in for whatever the platform throws when there is no route to a host.
class SocketishError implements Exception {
  const SocketishError();

  @override
  String toString() => 'Connection refused';
}
