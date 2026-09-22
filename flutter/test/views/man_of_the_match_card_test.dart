import 'dart:async';
import 'dart:convert';

import 'package:fishers/config/app_config.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/network_service.dart';
import 'package:fishers/theme/fishers_theme.dart';
import 'package:fishers/views/chat/man_of_the_match_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/stub_client.dart';

/// The vote card, driven the way the iOS tour drives it on a phone: somebody
/// who did not play opens the thread, votes, changes their mind, takes it
/// back, and is refused the close.
void main() {
  late List<RecordedRequest> sent;

  /// Serves the fixture, and lets a test decide what each call answers with.
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
      MaterialApp(
        theme: FishersTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ManOfTheMatchCard(pollId: '40c55245-c945-4ead-aa69-0160a8cce0db'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The ballot rows, by the label a screen reader reads out — the same way
  /// `ManOfTheMatchTour` finds them on iOS. Matching on InkWell would also
  /// catch the chip and the close button.
  ///
  /// A function rather than a value: `find.bySemanticsLabel` reaches for the
  /// binding, which does not exist until a test is running.
  Finder ballot() => find.bySemanticsLabel(RegExp('^Vote for '));

  /// The row you have already chosen reads differently — it is the one to tap
  /// to take a vote back, and `ballot()` deliberately does not include it.
  ///
  /// Not anchored at the end: once the tally is out, the row's vote count
  /// merges into the same semantics node, so the label is "Name, your vote 1".
  Finder myVote() => find.bySemanticsLabel(RegExp(', your vote'));

  final Map<String, dynamic> open = loadFixture('motm_poll_view');
  final Map<String, dynamic> closed = loadFixture('motm_poll_view_closed');

  /// The open fixture is captured with a `closes_at` that has since passed, so
  /// it is pushed forward — the card reads the clock, not just the status.
  String openNow({Map<String, dynamic> overrides = const <String, dynamic>{}}) =>
      jsonEncode(<String, dynamic>{
        ...open,
        'closes_at': DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
        ...overrides,
      });

  testWidgets('both elevens are on the ballot, with the tally hidden', (WidgetTester tester) async {
    serve((RecordedRequest _) => (200, openNow()));
    await pump(tester);

    expect(find.text('Man of the match'), findsOneWidget);
    expect(find.text('Votes are hidden until you have voted.'), findsOneWidget);
    // 22 names, and the two sheets headed by the sides from the fixture title.
    expect(ballot(), findsNWidgets(22));
    expect(find.textContaining('HEMEL', findRichText: false), findsOneWidget);
  });

  testWidgets('voting sends the candidate and reveals the tally', (WidgetTester tester) async {
    final String voted = openNow(
      overrides: <String, dynamic>{
        'my_vote': (open['candidates'] as List<dynamic>).first['user_id'],
        'tally_visible': true,
        'total_votes': 1,
      },
    );
    serve((RecordedRequest r) => (200, r.method == 'POST' ? voted : openNow()));
    await pump(tester);

    await tester.tap(ballot().first);
    await tester.pumpAndSettle();

    final RecordedRequest vote = sent.firstWhere((RecordedRequest r) => r.method == 'POST');
    expect(vote.path, endsWith('/vote'));
    expect(vote.json['candidate_user_id'], (open['candidates'] as List<dynamic>).first['user_id']);
    expect(find.text('1 vote so far.'), findsOneWidget);
  });

  /// Tapping the name you already chose takes the vote back, so a mis-tap is
  /// undone by the tap that made it.
  testWidgets('tapping your own vote again withdraws it', (WidgetTester tester) async {
    final String mine = (open['candidates'] as List<dynamic>).first['user_id'] as String;
    serve((RecordedRequest r) {
      if (r.method == 'DELETE') return (200, openNow());
      return (200, openNow(overrides: <String, dynamic>{'my_vote': mine, 'tally_visible': true}));
    });
    await pump(tester);

    expect(myVote(), findsOneWidget, reason: 'the card marks the vote already cast');
    await tester.tap(myVote());
    await tester.pumpAndSettle();

    expect(
      sent.any((RecordedRequest r) => r.method == 'DELETE' && r.path.endsWith('/vote')),
      isTrue,
      reason: 'the card withdrew rather than voting again',
    );
  });

  /// Most of a club cannot close a vote, so the refusal is said plainly rather
  /// than passing on the permission's own name.
  testWidgets('a member is told plainly that the close is not theirs', (WidgetTester tester) async {
    serve((RecordedRequest r) {
      if (r.path.endsWith('/close')) {
        return (403, '{"error":"Member cannot manage_events — ask a club secretary"}');
      }
      return (200, openNow());
    });
    await pump(tester);

    // Twenty-two names is taller than the test viewport, so the button has to
    // be brought on screen before it can be tapped — the same scroll the iOS
    // tour does for the ballot.
    await tester.ensureVisible(find.byKey(const Key('motm.close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('motm.close')));
    await tester.pumpAndSettle();

    expect(find.text('Only a captain or club secretary can close the vote.'), findsOneWidget);
    expect(find.textContaining('manage_events'), findsNothing);
    // Refused, not closed: the ballot is still there.
    expect(ballot(), findsNWidgets(22));
  });

  testWidgets('a closed vote names its winner instead of a ballot', (WidgetTester tester) async {
    serve((RecordedRequest _) => (200, jsonEncode(closed)));
    await pump(tester);

    expect(find.text('Closed'), findsOneWidget);
    expect(find.textContaining('of 1 vote'), findsOneWidget);
    // Nothing to tap: the vote is over.
    expect(find.byKey(const Key('motm.close')), findsNothing);
  });

  testWidgets('a card that cannot load says so rather than sitting empty', (
    WidgetTester tester,
  ) async {
    serve((RecordedRequest _) => (500, '{"error":"the vote could not be read"}'));
    await pump(tester);

    expect(find.byKey(const Key('motm.error')), findsOneWidget);
    expect(find.text('the vote could not be read'), findsOneWidget);
  });
}
