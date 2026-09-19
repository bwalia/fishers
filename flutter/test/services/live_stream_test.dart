import 'dart:async';

import 'package:fishers/config/app_config.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/live_stream.dart';
import 'package:fishers/services/network_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_client.dart';

/// The Android half of the wire-format section of
/// `ios/FishersTests/LiveTests.swift`, plus the connection's own rules.
void main() {
  List<LiveEvent> parse(String text) {
    final LiveEventParser parser = LiveEventParser();
    return <LiveEvent>[
      for (final String line in text.split('\n'))
        if (parser.feed(line) case final LiveEvent event) event,
    ];
  }

  const String conversation = 'b1f0c2d3-4e5f-4a6b-8c9d-0e1f2a3b4c5d';
  const String message = 'c2f0c2d3-4e5f-4a6b-8c9d-0e1f2a3b4c5e';
  const String match = 'd3f0c2d3-4e5f-4a6b-8c9d-0e1f2a3b4c5f';

  group('the wire format', () {
    test('reads each event the server sends', () {
      final List<LiveEvent> events = parse('''
event: ready
data: {}

:

event: message
data: {"conversation_id":"$conversation","id":"$message"}

event: notification
data: {}

event: conversations
data: {}

event: match
data: {"id":"$match","seq":42}

event: resync
data: {}

''');
      expect(events, <LiveEvent>[
        const LiveResync(),
        const LiveMessage(conversationId: conversation, id: message),
        const LiveNotification(),
        const LiveConversations(),
        const LiveMatch(id: match, seq: 42),
        const LiveResync(),
      ]);
    });

    test('skips what it does not understand', () {
      expect(
        parse('event: something_new\ndata: {}\n\n'),
        isEmpty,
        reason: "a newer server's event is ignored",
      );
      expect(parse('event: notification\n\n'), isEmpty, reason: 'no data, no event');
      expect(
        parse('event: match\ndata: {"seq":1}\n\n'),
        isEmpty,
        reason: 'a match with no id says nothing',
      );
      expect(parse(': keep-alive\n\n'), isEmpty);
      // Nothing carries over from an event that did not finish into the next.
      expect(
        parse('event: message\ndata: not json\n\nevent: notification\ndata:{}\n\n'),
        <LiveEvent>[const LiveNotification()],
      );
    });

    test('a match with no seq is still a match', () {
      expect(parse('event: match\ndata: {"id":"$match"}\n\n'), <LiveEvent>[
        const LiveMatch(id: match, seq: 0),
      ]);
    });

    test('a data line without the conventional space still reads', () {
      expect(parse('event:notification\ndata:{}\n\n'), <LiveEvent>[const LiveNotification()]);
    });

    test('a multi-line data field is joined with newlines', () {
      expect(parse('event: match\ndata: {"id":\ndata: "$match","seq":7}\n\n'), <LiveEvent>[
        const LiveMatch(id: match, seq: 7),
      ]);
    });

    test('an event name resets to "message" after each frame', () {
      // The second frame names no event, so the SSE default applies.
      expect(
        parse(
          'event: notification\ndata: {}\n\n'
          'data: {"conversation_id":"$conversation","id":"$message"}\n\n',
        ),
        <LiveEvent>[
          const LiveNotification(),
          const LiveMessage(conversationId: conversation, id: message),
        ],
      );
    });

    test('an id that is not a UUID is not an id', () {
      expect(
        parse('event: message\ndata: {"conversation_id":"nope","id":"$message"}\n\n'),
        isEmpty,
      );
    });

    test('ready and resync both mean "go and fetch"', () {
      expect(LiveEventParser.event(name: 'ready', data: '{}'), const LiveResync());
      expect(LiveEventParser.event(name: 'resync', data: '{}'), const LiveResync());
    });

    test('a payload that is not an object is tolerated, not fatal', () {
      // `JSONSerialization` with `.fragmentsAllowed` reads these on iOS too.
      expect(LiveEventParser.event(name: 'notification', data: '7'), const LiveNotification());
      expect(LiveEventParser.event(name: 'match', data: '7'), isNull);
    });
  });

  group('reconnecting', () {
    test('backs off 1s, 2s, 4s … to a 30s ceiling', () {
      double noJitter() => 1;
      expect(LiveStream.backoff(0, jitter: noJitter), const Duration(seconds: 1));
      expect(LiveStream.backoff(1, jitter: noJitter), const Duration(seconds: 2));
      expect(LiveStream.backoff(2, jitter: noJitter), const Duration(seconds: 4));
      expect(LiveStream.backoff(4, jitter: noJitter), const Duration(seconds: 16));
      expect(LiveStream.backoff(5, jitter: noJitter), const Duration(seconds: 30));
      expect(LiveStream.backoff(50, jitter: noJitter), const Duration(seconds: 30));
    });

    test('jitters, so a server restart does not bring every phone back at once', () {
      final Set<int> waits = <int>{
        for (int i = 0; i < 50; i++) LiveStream.backoff(3).inMilliseconds,
      };
      expect(waits.length, greaterThan(1), reason: 'the wait must not be fixed');
      for (final int wait in waits) {
        // 8s ± 25%.
        expect(wait, inInclusiveRange(6000, 10000));
      }
    });

    test('the gap allowed between packets is longer than the keep-alive', () {
      // The server sends one every 20s; 50s of silence means the connection
      // died without saying so.
      expect(LiveStream.idleTimeout, const Duration(seconds: 50));
      expect(LiveStream.idleTimeout.inSeconds, greaterThan(20 * 2));
    });
  });

  group('the connection', () {
    NetworkService signedService(StubClient client) => NetworkService(
      client: client,
      store: InMemoryTokenStore(<String, String>{'access_token': 'at', 'refresh_token': 'rt'}),
      config: AppConfig(
        store: InMemoryConfigStore(),
        environment: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      ),
    );

    test('opens with the first listener and carries the bearer', () async {
      final StubClient auth = StubClient((RecordedRequest _) => (200, '{}'));
      final NetworkService network = signedService(auth);
      await network.loadTokensFromStore();

      final StubStreamClient stream = StubStreamClient();
      final LiveStream live = LiveStream(network: network, clientFactory: () => stream);

      final List<LiveEvent> seen = <LiveEvent>[];
      final StreamSubscription<LiveEvent> sub = live.events().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(stream.requests, hasLength(1));
      expect(stream.requests.single.url.toString(), 'https://int.fishers.cloud/api/v1/stream');
      expect(stream.requests.single.headers['Authorization'], 'Bearer at');
      expect(stream.requests.single.headers['Accept'], 'text/event-stream');

      stream.emit('event: notification\ndata: {}\n\n');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen, <LiveEvent>[const LiveNotification()]);

      await sub.cancel();
      expect(live.listenerCount, 0);
    });

    test('every listener sees every event', () async {
      final StubClient auth = StubClient((RecordedRequest _) => (200, '{}'));
      final NetworkService network = signedService(auth);
      await network.loadTokensFromStore();

      final StubStreamClient stream = StubStreamClient();
      final LiveStream live = LiveStream(network: network, clientFactory: () => stream);

      final List<LiveEvent> bell = <LiveEvent>[];
      final List<LiveEvent> scorecard = <LiveEvent>[];
      final StreamSubscription<LiveEvent> a = live.events().listen(bell.add);
      final StreamSubscription<LiveEvent> b = live.events().listen(scorecard.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      stream.emit('event: match\ndata: {"id":"$match","seq":3}\n\n');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bell, <LiveEvent>[const LiveMatch(id: match, seq: 3)]);
      expect(scorecard, bell);
      expect(
        stream.requests,
        hasLength(1),
        reason: 'one connection for the whole app, not one per screen',
      );

      await a.cancel();
      await b.cancel();
    });

    test('a 401 renews the session rather than reconnecting with a dead token', () async {
      int refreshes = 0;
      final StubClient auth = StubClient((RecordedRequest request) {
        if (request.path.endsWith('/auth/refresh')) {
          refreshes += 1;
          return (200, '{"access_token":"fresh","refresh_token":"rt-2"}');
        }
        return (200, '{}');
      });
      final NetworkService network = signedService(auth);
      await network.loadTokensFromStore();

      final StubStreamClient stream = StubStreamClient(status: 401);
      final LiveStream live = LiveStream(network: network, clientFactory: () => stream);

      final StreamSubscription<LiveEvent> sub = live.events().listen((LiveEvent _) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(refreshes, greaterThanOrEqualTo(1));
    });

    test('with no session there is nothing to connect', () async {
      final StubClient auth = StubClient((RecordedRequest _) => (200, '{}'));
      final NetworkService network = NetworkService(
        client: auth,
        store: InMemoryTokenStore(),
        config: AppConfig(store: InMemoryConfigStore()),
      );
      final StubStreamClient stream = StubStreamClient();
      final LiveStream live = LiveStream(network: network, clientFactory: () => stream);

      final StreamSubscription<LiveEvent> sub = live.events().listen((LiveEvent _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stream.requests, isEmpty);
      await sub.cancel();
    });
  });
}
