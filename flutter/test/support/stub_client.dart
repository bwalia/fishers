import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One request, as the client actually sent it.
class RecordedRequest {
  RecordedRequest(http.Request request)
    : method = request.method,
      url = request.url,
      headers = Map<String, String>.unmodifiable(request.headers),
      body = request.body,
      bodyBytes = request.bodyBytes;

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
  final List<int> bodyBytes;

  String get path => url.path;
  String? get bearer => headers['Authorization'];

  /// The JSON body, as a map. Throws if there is not one.
  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;

  @override
  String toString() => '$method ${url.path}${url.hasQuery ? "?${url.query}" : ""}';
}

/// Answers requests from a closure, so a test never touches the network — the
/// Dart half of `StubProtocol` in `ios/FishersTests/NetworkRefreshTests.swift`.
class StubClient extends http.BaseClient {
  StubClient(this.handler);

  /// Given the request, answer with a status and a body.
  final FutureOr<(int, String)> Function(RecordedRequest request) handler;

  final List<RecordedRequest> requests = <RecordedRequest>[];

  RecordedRequest get lastRequest => requests.last;

  List<String> get paths => requests.map((RecordedRequest r) => r.url.path).toList();

  int countOf(String path) =>
      requests.where((RecordedRequest r) => r.url.path.endsWith(path)).length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final RecordedRequest recorded = RecordedRequest(request as http.Request);
    requests.add(recorded);
    final (int status, String body) = await handler(recorded);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      request: request,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

/// A client whose one response is a live stream the test feeds by hand.
class StubStreamClient extends http.BaseClient {
  StubStreamClient({this.status = 200});

  final int status;
  final List<RecordedRequest> requests = <RecordedRequest>[];
  final List<StreamController<List<int>>> bodies = <StreamController<List<int>>>[];

  StreamController<List<int>> get lastBody => bodies.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(RecordedRequest(request as http.Request));
    final StreamController<List<int>> body = StreamController<List<int>>();
    bodies.add(body);
    return http.StreamedResponse(
      body.stream,
      status,
      request: request,
      headers: <String, String>{'content-type': 'text/event-stream'},
    );
  }

  /// Push one SSE frame down the open connection.
  void emit(String text) => lastBody.add(utf8.encode(text));

  Future<void> endConnection() => lastBody.close();
}
