import 'dart:async';
import 'dart:convert';

import 'package:fishers/app/fishers_app.dart';
import 'package:fishers/config/app_config.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/network_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/stub_client.dart';

/// The gate — `ios/Fishers/Views/RootView.swift` and `Auth/AuthView.swift`.
void main() {
  late List<RecordedRequest> sent;

  void serve(
    FutureOr<(int, String)> Function(RecordedRequest) handler, {
    Map<String, String> stored = const <String, String>{},
  }) {
    final StubClient client = StubClient(handler);
    sent = client.requests;
    NetworkService.shared = NetworkService(
      client: client,
      store: InMemoryTokenStore(Map<String, String>.of(stored)),
      config: AppConfig(
        store: InMemoryConfigStore(),
        environment: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      ),
    );
  }

  final String authTokens = jsonEncode(loadFixture('auth_tokens'));
  final String me = jsonEncode(loadFixture('public_user'));

  testWidgets('with nothing stored, the app opens on sign in', (WidgetTester tester) async {
    serve((RecordedRequest _) => (200, me));
    await tester.pumpWidget(const FishersApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('auth.submit')), findsOneWidget);
    expect(sent, isEmpty, reason: 'nothing to sign in with, so nothing was asked');
  });

  /// The button stays off until there is something to send: an empty form
  /// that can be submitted is a round trip to be told what you already know.
  testWidgets('sign in is refused until both fields are filled', (WidgetTester tester) async {
    serve((RecordedRequest _) => (200, authTokens));
    await tester.pumpWidget(const FishersApp());
    await tester.pumpAndSettle();

    FilledButton submit() => tester.widget<FilledButton>(find.byKey(const Key('auth.submit')));
    expect(submit().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('auth.identifier')), 'someone@club.test');
    await tester.pump();
    expect(submit().onPressed, isNull, reason: 'a password is still needed');

    await tester.enterText(find.byKey(const Key('auth.password')), 'password123');
    await tester.pump();
    expect(submit().onPressed, isNotNull);
  });

  testWidgets('signing in sends the credentials and opens the app', (WidgetTester tester) async {
    serve((RecordedRequest r) => (200, r.path.endsWith('/auth/login') ? authTokens : me));
    await tester.pumpWidget(const FishersApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('auth.identifier')), 'someone@club.test');
    await tester.enterText(find.byKey(const Key('auth.password')), 'password123');
    await tester.pump();
    await tester.tap(find.byKey(const Key('auth.submit')));
    await tester.pumpAndSettle();

    final RecordedRequest login = sent.firstWhere((RecordedRequest r) => r.method == 'POST');
    expect(login.path, endsWith('/auth/login'));
    expect(login.json['identifier'], 'someone@club.test');
    // Past the gate: the tab bar is up, on Chats.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Chats'), findsWidgets);
  });

  testWidgets('a refusal is shown on the form, not swallowed', (WidgetTester tester) async {
    serve((RecordedRequest _) => (400, '{"error":"that is not an email address"}'));
    await tester.pumpWidget(const FishersApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('auth.identifier')), 'nonsense');
    await tester.enterText(find.byKey(const Key('auth.password')), 'password123');
    await tester.pump();
    await tester.tap(find.byKey(const Key('auth.submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth.error')), findsOneWidget);
    expect(find.text('that is not an email address'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing, reason: 'still on the gate');
  });

  testWidgets('a kept token opens the app without asking again', (WidgetTester tester) async {
    serve(
      (RecordedRequest r) => (200, r.path.endsWith('/conversations') ? '[]' : me),
      stored: <String, String>{TokenStore.accessTokenKey: 'kept'},
    );
    await tester.pumpWidget(const FishersApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('switching to sign up asks for a name and what they came to do', (
    WidgetTester tester,
  ) async {
    serve((RecordedRequest _) => (200, authTokens));
    await tester.pumpWidget(const FishersApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('auth.toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Join your club'), findsOneWidget);
    expect(find.byKey(const Key('auth.name')), findsOneWidget);
    expect(find.text('Run a club'), findsOneWidget);
  });

  /// A shared phone must not keep the last person signed in.
  testWidgets('signing out returns to the gate', (WidgetTester tester) async {
    serve(
      (RecordedRequest r) => (200, r.path.endsWith('/conversations') ? '[]' : me),
      stored: <String, String>{TokenStore.accessTokenKey: 'kept'},
    );
    await tester.pumpWidget(const FishersApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile.signOut')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });
}
