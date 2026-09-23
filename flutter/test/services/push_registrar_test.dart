import 'dart:async';

import 'package:fishers/config/app_config.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/network_service.dart';
import 'package:fishers/services/push_registrar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_client.dart';

/// Registering this phone for push — the Android half of
/// `ios/Fishers/Services/PushRegistrar.swift`.
class _FakeMessaging implements FirebaseMessagingLike {
  _FakeMessaging({this.granted = true, this.initial});

  bool granted;
  String? token = 'fcm-token-1';
  Map<String, String>? initial;

  final StreamController<String> refreshes = StreamController<String>.broadcast();
  final StreamController<Map<String, String>> taps =
      StreamController<Map<String, String>>.broadcast();

  int permissionAsks = 0;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Stream<Map<String, String>> get onMessageOpenedApp => taps.stream;

  @override
  Future<Map<String, String>?> initialMessageData() async => initial;
}

void main() {
  late StubClient client;

  void serve() {
    client = StubClient((RecordedRequest _) => (200, '{"registered":true}'));
    NetworkService.shared = NetworkService(
      client: client,
      store: InMemoryTokenStore(<String, String>{TokenStore.accessTokenKey: 'at'}),
      config: AppConfig(
        store: InMemoryConfigStore(),
        environment: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      ),
    );
  }

  setUp(serve);

  PushRegistrar registrarFor(_FakeMessaging messaging, {bool configured = true}) =>
      PushRegistrar(messaging: messaging, firebaseAvailable: configured);

  test('the token is registered as android, so the server picks FCM', () async {
    final _FakeMessaging messaging = _FakeMessaging();
    await registrarFor(messaging).start();

    final RecordedRequest sent = client.lastRequest;
    expect(sent.path, endsWith('/notifications/register-device'));
    expect(sent.json['device_token'], 'fcm-token-1');
    expect(sent.json['platform'], 'android');
  });

  /// A refusal is final and silent: Android will not ask again, and pestering
  /// somebody for a permission the system has recorded is worse than doing
  /// without.
  test('a refused permission registers nothing', () async {
    final _FakeMessaging messaging = _FakeMessaging(granted: false);
    await registrarFor(messaging).start();

    expect(messaging.permissionAsks, 1);
    expect(client.requests, isEmpty);
  });

  /// A build with no google-services.json is the ordinary state of a fresh
  /// checkout. It must be quiet, not broken — and must not even ask for the
  /// permission, since nothing could be delivered through it.
  test('a build with no Firebase project is quiet', () async {
    final _FakeMessaging messaging = _FakeMessaging();
    final PushRegistrar registrar = registrarFor(messaging, configured: false);

    expect(registrar.isConfigured, isFalse);
    await registrar.start();

    expect(messaging.permissionAsks, 0);
    expect(client.requests, isEmpty);
  });

  /// Tokens rotate — on reinstall, on a restore to a new device, and on
  /// Firebase's own schedule. One that is never re-registered is a phone that
  /// silently stops hearing anything.
  test('a rotated token is registered again', () async {
    final _FakeMessaging messaging = _FakeMessaging();
    await registrarFor(messaging).start();
    expect(client.countOf('/notifications/register-device'), 1);

    messaging.refreshes.add('fcm-token-2');
    await Future<void>.delayed(Duration.zero);

    expect(client.countOf('/notifications/register-device'), 2);
    expect(client.lastRequest.json['device_token'], 'fcm-token-2');
  });

  /// The same token on every cold start is not news to the server.
  test('the same token is not sent twice', () async {
    final _FakeMessaging messaging = _FakeMessaging();
    final PushRegistrar registrar = registrarFor(messaging);
    await registrar.start();

    messaging.refreshes.add('fcm-token-1');
    await Future<void>.delayed(Duration.zero);

    expect(client.countOf('/notifications/register-device'), 1);
  });

  test('a tap is routed by the ids the server put in the data', () async {
    final _FakeMessaging messaging = _FakeMessaging();
    final PushRegistrar registrar = registrarFor(messaging);
    await registrar.start();

    int notified = 0;
    registrar.addListener(() => notified++);
    messaging.taps.add(<String, String>{
      'conversation_id': 'abc',
      'motm_poll_id': 'def',
      'url': '/chat/abc',
    });
    await Future<void>.delayed(Duration.zero);

    expect(registrar.pendingConversationId, 'abc');
    expect(registrar.pendingMotmPollId, 'def');
    expect(notified, 1);
  });

  /// A notification that started the app cold does not arrive on the stream,
  /// and it is the whole reason somebody is looking at the screen.
  test('a notification that started the app cold is routed too', () async {
    final _FakeMessaging messaging = _FakeMessaging(
      initial: <String, String>{'conversation_id': 'cold'},
    );
    final PushRegistrar registrar = registrarFor(messaging);
    await registrar.start();

    expect(registrar.pendingConversationId, 'cold');
  });

  /// Data with nothing to route is not a tap worth waking anything for.
  test('a notification with no ids changes nothing', () async {
    final _FakeMessaging messaging = _FakeMessaging();
    final PushRegistrar registrar = registrarFor(messaging);
    await registrar.start();

    int notified = 0;
    registrar.addListener(() => notified++);
    registrar.route(<String, String>{'title': 'Man of the match'});

    expect(registrar.pendingConversationId, isNull);
    expect(notified, 0);
  });

  /// A shared phone must stop buzzing with the last person's club.
  test('signing out unregisters the token', () async {
    final _FakeMessaging messaging = _FakeMessaging();
    final PushRegistrar registrar = registrarFor(messaging);
    await registrar.start();

    await registrar.unregister();

    final RecordedRequest sent = client.lastRequest;
    expect(sent.path, endsWith('/notifications/unregister-device'));
    expect(sent.json['device_token'], 'fcm-token-1');
  });

  test('unregistering without a token asks the server nothing', () async {
    final PushRegistrar registrar = registrarFor(_FakeMessaging());
    await registrar.unregister();
    expect(client.requests, isEmpty);
  });
}
