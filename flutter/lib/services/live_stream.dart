import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'network_service.dart';

/// What changed, pushed from the API as it happens — the same `GET /stream`
/// the web reads. A port of `ios/Fishers/Services/LiveStream.swift`.
///
/// Events say what changed, **never the content**. Listeners re-fetch through
/// the normal endpoints, which do their own access checks.
@immutable
sealed class LiveEvent {
  const LiveEvent();
}

/// A new message in one of your threads.
@immutable
class LiveMessage extends LiveEvent {
  const LiveMessage({required this.conversationId, required this.id});

  final String conversationId;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is LiveMessage && other.conversationId == conversationId && other.id == id;

  @override
  int get hashCode => Object.hash('message', conversationId, id);

  @override
  String toString() => 'LiveMessage($conversationId, $id)';
}

/// A notification arrived for you, or one was read on another device.
@immutable
class LiveNotification extends LiveEvent {
  const LiveNotification();

  @override
  bool operator ==(Object other) => other is LiveNotification;

  @override
  int get hashCode => 'notification'.hashCode;

  @override
  String toString() => 'LiveNotification()';
}

/// You joined or left a thread.
@immutable
class LiveConversations extends LiveEvent {
  const LiveConversations();

  @override
  bool operator ==(Object other) => other is LiveConversations;

  @override
  int get hashCode => 'conversations'.hashCode;

  @override
  String toString() => 'LiveConversations()';
}

/// A match changed — a ball, the toss, a handover, the result.
@immutable
class LiveMatch extends LiveEvent {
  const LiveMatch({required this.id, required this.seq});

  final String id;
  final int seq;

  @override
  bool operator ==(Object other) => other is LiveMatch && other.id == id && other.seq == seq;

  @override
  int get hashCode => Object.hash('match', id, seq);

  @override
  String toString() => 'LiveMatch($id, seq $seq)';
}

/// Connected (or reconnected), or events may have been missed: re-fetch.
@immutable
class LiveResync extends LiveEvent {
  const LiveResync();

  @override
  bool operator ==(Object other) => other is LiveResync;

  @override
  int get hashCode => 'resync'.hashCode;

  @override
  String toString() => 'LiveResync()';
}

/// The SSE wire format: `event:` and `data:` lines, a blank line ends an event,
/// and lines starting with ":" are keep-alive comments.
class LiveEventParser {
  String _name = 'message';
  String _data = '';

  /// One line, without its newline. An event comes back when a blank line
  /// finishes one.
  LiveEvent? feed(String line) {
    if (line.isEmpty) {
      final String name = _name;
      final String data = _data;
      _name = 'message';
      _data = '';
      return event(name: name, data: data);
    }
    if (line.startsWith(':')) return null;

    String field = line;
    String value = '';
    final int colon = line.indexOf(':');
    if (colon >= 0) {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }
    switch (field) {
      case 'event':
        _name = value;
      case 'data':
        _data += (_data.isEmpty ? '' : '\n') + value;
      default:
        break;
    }
    return null;
  }

  /// A finished event, or null when the app does not understand it — a newer
  /// server's event is ignored rather than guessed at.
  static LiveEvent? event({required String name, required String data}) {
    if (data.isEmpty) return null;
    final Object? parsed;
    try {
      parsed = jsonDecode(data);
    } on FormatException {
      return null;
    }
    final Map<String, dynamic> payload = parsed is Map
        ? parsed.cast<String, dynamic>()
        : const <String, dynamic>{};

    switch (name) {
      // Connected: whatever happened while we were not is only in a fetch.
      case 'ready':
      case 'resync':
        return const LiveResync();
      case 'message':
        final String? conversation = tryUuid(payload['conversation_id']);
        final String? id = tryUuid(payload['id']);
        if (conversation == null || id == null) return null;
        return LiveMessage(conversationId: conversation, id: id);
      case 'notification':
        return const LiveNotification();
      case 'conversations':
        return const LiveConversations();
      case 'match':
        final String? id = tryUuid(payload['id']);
        if (id == null) return null;
        final Object? seq = payload['seq'];
        return LiveMatch(id: id, seq: seq is num ? seq.toInt() : 0);
      default:
        return null;
    }
  }
}

/// One connection for the whole app, shared by every screen that listens: a
/// thread, the chat list, the bell, a scorecard.
///
/// ```dart
/// final StreamSubscription<LiveEvent> sub = LiveStream.shared.events().listen(…);
/// ```
///
/// The connection opens with the first listener and closes with the last, so
/// cancelling a subscription is all the unsubscribing there is. It drops while
/// the app is in the background — Android would cut it anyway — and comes back,
/// with a [LiveResync], when the app does.
class LiveStream with WidgetsBindingObserver {
  LiveStream({NetworkService? network, http.Client Function()? clientFactory})
    : _network = network ?? NetworkService.shared,
      _clientFactory = clientFactory ?? http.Client.new;

  static LiveStream shared = LiveStream();

  final NetworkService _network;
  final http.Client Function() _clientFactory;

  final Set<StreamController<LiveEvent>> _listeners = <StreamController<LiveEvent>>{};
  Future<void>? _connection;
  bool _closing = false;
  bool _backgrounded = false;
  bool _observing = false;

  /// The server sends a keep-alive every 20s, so 50s of silence ends a
  /// connection that died without saying so — a network change, a Wi-Fi
  /// hand-off. The same window `URLSession.timeoutIntervalForRequest` gives it
  /// on iOS.
  static const Duration idleTimeout = Duration(seconds: 50);

  /// 1s, 2s, 4s … up to 30s, with jitter so a server restart does not bring
  /// every phone back in the same instant.
  static Duration backoff(int retry, {double Function()? jitter}) {
    final double base = min(30, pow(2, retry).toDouble());
    final double factor = jitter?.call() ?? (0.75 + Random().nextDouble() * 0.5);
    return Duration(milliseconds: (base * factor * 1000).round());
  }

  Stream<LiveEvent> events() {
    late final StreamController<LiveEvent> controller;
    controller = StreamController<LiveEvent>.broadcast(
      onListen: () {
        _listeners.add(controller);
        _openIfNeeded();
      },
      onCancel: () {
        _listeners.remove(controller);
        unawaited(controller.close());
        if (_listeners.isEmpty) _close();
      },
    );
    return controller.stream;
  }

  /// Watch the app's lifecycle, so the stream drops in the background and comes
  /// back with a resync. Called once, from the root widget.
  void observeLifecycle() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _backgrounded = true;
        _close();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        _backgrounded = false;
        _openIfNeeded();
    }
  }

  void _deliver(LiveEvent event) {
    for (final StreamController<LiveEvent> listener in _listeners.toList(growable: false)) {
      if (!listener.isClosed) listener.add(event);
    }
  }

  void _close() {
    _closing = true;
    _connection = null;
  }

  void _openIfNeeded() {
    if (_connection != null || _listeners.isEmpty || _backgrounded) return;
    _closing = false;
    _connection = _readLoop();
  }

  Future<void> _readLoop() async {
    int retry = 0;
    while (!_closing) {
      final bool connected = await _read();
      if (connected) retry = 0;
      if (_closing) return;
      final Duration wait = backoff(retry);
      retry += 1;
      await Future<void>.delayed(wait);
    }
  }

  /// One connection, read until it ends. True when it got as far as a stream,
  /// so the next attempt starts from the shortest wait.
  Future<bool> _read() async {
    final http.Request? request = await _network.signedRequest('/stream');
    if (request == null) return false;
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    final http.Client client = _clientFactory();
    try {
      final http.StreamedResponse response = await client.send(request);
      if (response.statusCode == 401) {
        await _network.renewSession();
        return false;
      }
      if (response.statusCode != 200) return false;

      final LiveEventParser parser = LiveEventParser();
      // Line by line, keeping the blank lines — `LineSplitter` emits them, and
      // they are what ends each event.
      final Stream<String> lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(idleTimeout);

      await for (final String line in lines) {
        if (_closing) break;
        final LiveEvent? event = parser.feed(line);
        if (event != null) _deliver(event);
      }
      return true;
    } on Object {
      // A dropped connection, a timeout, a refused TLS handshake: the loop
      // waits and tries again, which is the whole contract.
      return false;
    } finally {
      client.close();
    }
  }

  @visibleForTesting
  bool get isConnected => _connection != null;

  @visibleForTesting
  int get listenerCount => _listeners.length;
}
