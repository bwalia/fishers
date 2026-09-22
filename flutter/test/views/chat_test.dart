import 'dart:async';
import 'dart:convert';

import 'package:fishers/config/app_config.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/network_service.dart';
import 'package:fishers/stores/chat_store.dart';
import 'package:fishers/theme/fishers_theme.dart';
import 'package:fishers/views/chat/chat_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';
import '../support/stub_client.dart';

/// The chat list and the thread — `ios/Fishers/Views/Chat/`.
void main() {
  late List<RecordedRequest> sent;

  void serve(FutureOr<(int, String)> Function(RecordedRequest) handler) {
    final StubClient client = StubClient(handler);
    sent = client.requests;
    NetworkService.shared = NetworkService(
      client: client,
      store: InMemoryTokenStore(<String, String>{TokenStore.accessTokenKey: 'at'}),
      config: AppConfig(
        store: InMemoryConfigStore(),
        environment: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ChatStore>(
        create: (_) => ChatStore(),
        child: MaterialApp(theme: FishersTheme.light, home: const ChatListView()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final Map<String, dynamic> conversation = loadFixture('conversation_summary');
  final Map<String, dynamic> message = loadFixture('chat_message');
  final Map<String, dynamic> poll = loadFixture('motm_poll_view');

  String listOf(List<Map<String, dynamic>> rows) => jsonEncode(rows);

  testWidgets('an empty list says so rather than showing nothing', (WidgetTester tester) async {
    serve((RecordedRequest _) => (200, '[]'));
    await pump(tester);

    expect(find.text('No chats yet'), findsOneWidget);
    expect(find.textContaining('availability and squads'), findsOneWidget);
  });

  testWidgets('a thread that will not load says why', (WidgetTester tester) async {
    serve((RecordedRequest _) => (500, '{"error":"the chats could not be read"}'));
    await pump(tester);

    expect(find.text('the chats could not be read'), findsOneWidget);
  });

  testWidgets('threads show their unread count', (WidgetTester tester) async {
    serve(
      (RecordedRequest _) => (
        200,
        listOf(<Map<String, dynamic>>[
          <String, dynamic>{...conversation, 'title': 'Hemel — club chat', 'unread_count': 3},
        ]),
      ),
    );
    await pump(tester);

    expect(find.text('Hemel — club chat'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  /// The card renders under the message that announced the vote, so a member
  /// finds it where the conversation left it rather than on a screen of its
  /// own.
  testWidgets('opening a thread shows the man-of-the-match card', (WidgetTester tester) async {
    final Map<String, dynamic> announcement = <String, dynamic>{
      ...message,
      'kind': 'system',
      'sender_id': null,
      'sender_name': null,
      'body': 'Hemel won by 7 wickets. Who was your man of the match?',
      'metadata': <String, dynamic>{
        'kind': 'motm_poll',
        'motm_poll_id': '40c55245-c945-4ead-aa69-0160a8cce0db',
      },
    };

    serve((RecordedRequest r) {
      if (r.path.endsWith('/conversations')) {
        return (
          200,
          listOf(<Map<String, dynamic>>[
            <String, dynamic>{...conversation, 'title': 'Hemel — club chat'},
          ]),
        );
      }
      if (r.path.contains('/messages')) {
        return (200, listOf(<Map<String, dynamic>>[announcement]));
      }
      if (r.path.contains('/motm/polls/')) {
        return (
          200,
          jsonEncode(<String, dynamic>{
            ...poll,
            'closes_at': DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
          }),
        );
      }
      return (200, '{}');
    });
    await pump(tester);

    await tester.tap(find.text('Hemel — club chat'));
    await tester.pumpAndSettle();

    // The announcement, and then the card under it — the card's own prompt
    // asks the same question, so these are matched exactly rather than by
    // substring.
    expect(
      find.text('Hemel won by 7 wickets. Who was your man of the match?'),
      findsOneWidget,
    );
    expect(find.text('Man of the match'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Vote for ')), findsNWidgets(22));
  });

  /// The result and the correction carry the same poll id. Drawing a card for
  /// each would put three of them in the thread.
  testWidgets('only the opening message draws a card', (WidgetTester tester) async {
    Map<String, dynamic> announcing(String kind) => <String, dynamic>{
      ...message,
      'id': '$kind-0000-0000-0000-000000000000'.substring(0, 36),
      'kind': 'system',
      'sender_id': null,
      'sender_name': null,
      'metadata': <String, dynamic>{
        'kind': kind,
        'motm_poll_id': '40c55245-c945-4ead-aa69-0160a8cce0db',
      },
    };

    serve((RecordedRequest r) {
      if (r.path.endsWith('/conversations')) {
        return (
          200,
          listOf(<Map<String, dynamic>>[
            <String, dynamic>{...conversation, 'title': 'Hemel — club chat'},
          ]),
        );
      }
      if (r.path.contains('/messages')) {
        return (
          200,
          listOf(<Map<String, dynamic>>[
            announcing('motm_result_changed'),
            announcing('motm_result'),
          ]),
        );
      }
      return (200, '{}');
    });
    await pump(tester);

    await tester.tap(find.text('Hemel — club chat'));
    await tester.pumpAndSettle();

    expect(find.text('Man of the match'), findsNothing);
    expect(
      sent.any((RecordedRequest r) => r.path.contains('/motm/polls/')),
      isFalse,
      reason: 'no card was drawn, so no poll was fetched',
    );
  });

  testWidgets('sending a message posts it and clears the box', (WidgetTester tester) async {
    serve((RecordedRequest r) {
      if (r.path.endsWith('/conversations')) {
        return (
          200,
          listOf(<Map<String, dynamic>>[
            <String, dynamic>{...conversation, 'title': 'Hemel — club chat'},
          ]),
        );
      }
      if (r.method == 'POST' && r.path.contains('/messages')) {
        return (200, jsonEncode(<String, dynamic>{...message, 'body': 'On my way'}));
      }
      if (r.path.contains('/messages')) return (200, '[]');
      return (200, '{}');
    });
    await pump(tester);

    await tester.tap(find.text('Hemel — club chat'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat.composer')), 'On my way');
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();

    final RecordedRequest post = sent.firstWhere(
      (RecordedRequest r) => r.method == 'POST' && r.path.contains('/messages'),
    );
    expect(post.json['body'], 'On my way');
    expect(
      tester.widget<TextField>(find.byKey(const Key('chat.composer'))).controller?.text,
      isEmpty,
    );
  });
}
