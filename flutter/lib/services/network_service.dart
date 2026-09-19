import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/json.dart';
import 'keychain_store.dart';
import 'uuid.dart';

/// What went wrong with a request — a port of `APIError` in
/// `ios/Fishers/Services/NetworkService.swift`.
class ApiException implements Exception {
  const ApiException.invalidUrl()
    : kind = ApiErrorKind.invalidUrl,
      statusCode = null,
      body = '',
      host = null;
  const ApiException.http(int code, this.body)
    : kind = ApiErrorKind.http,
      statusCode = code,
      host = null;
  const ApiException.decoding(this.body)
    : kind = ApiErrorKind.decoding,
      statusCode = null,
      host = null;
  const ApiException.unauthorized()
    : kind = ApiErrorKind.unauthorized,
      statusCode = 401,
      body = '',
      host = null;
  const ApiException.empty() : kind = ApiErrorKind.empty, statusCode = null, body = '', host = null;

  /// [host] is the server the request actually went to. iOS reads the current
  /// `AppConfig.apiBaseURL` when it builds this sentence; carrying the host on
  /// the error says the same thing without depending on the config not having
  /// changed in between.
  const ApiException.unreachable(this.body, {this.host})
    : kind = ApiErrorKind.unreachable,
      statusCode = null;

  final ApiErrorKind kind;
  final int? statusCode;
  final String body;
  final String? host;

  String get errorDescription => switch (kind) {
    ApiErrorKind.invalidUrl => 'Invalid URL',
    ApiErrorKind.http => 'HTTP $statusCode: $body',
    ApiErrorKind.decoding => 'Decode error: $body',
    ApiErrorKind.unauthorized => 'Please sign in again',
    ApiErrorKind.empty => 'Empty response',
    ApiErrorKind.unreachable =>
      'Cannot reach API at ${host ?? AppConfig.instance.apiBaseUrl} — is it running? '
          '($body)',
  };

  /// The sentence to put in front of somebody.
  ///
  /// The API answers a refusal as `{"error": "..."}`, written for a person to
  /// read. Showing `HTTP 400: {"error":"that is not a JPEG…"}` throws that away
  /// and hands them the plumbing instead.
  String get friendlyMessage {
    if (kind == ApiErrorKind.http) {
      final String? message = _field('error');
      if (message != null && message.isNotEmpty) return message;
    }
    return errorDescription;
  }

  /// The machine-readable reason, when the API gives one — `"unverified"` is
  /// the one the app acts on, by asking for the code right there.
  String? get code => kind == ApiErrorKind.http ? _field('code') : null;

  bool get isUnverified => code == 'unverified';

  String? _field(String key) {
    try {
      final Object? parsed = jsonDecode(body);
      if (parsed is Map && parsed[key] is String) return parsed[key] as String;
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  String toString() => errorDescription;
}

enum ApiErrorKind { invalidUrl, http, decoding, unauthorized, empty, unreachable }

/// The one client every request goes through — a port of `NetworkService`.
///
/// Base URL from [AppConfig], the `/api/v1` prefix, a bearer access token, and
/// **one** refresh-then-retry on a 401. The tokens live in secure storage and
/// are reloaded on launch, as `loadTokensFromKeychain()` does on iOS.
class NetworkService {
  NetworkService({http.Client? client, TokenStore? store, AppConfig? config})
    : _client = client ?? http.Client(),
      _store = store ?? KeychainStore(),
      _config = config ?? AppConfig.instance;

  /// The one the app uses. A test builds its own with a stub client.
  static NetworkService shared = NetworkService();

  final http.Client _client;
  final TokenStore _store;
  final AppConfig _config;

  String? _accessToken;
  String? _refreshToken;

  /// The refresh in flight, if there is one. See [_refreshAccessToken].
  Future<void>? _refreshInFlight;

  String? get accessToken => _accessToken;
  bool get hasSession => _accessToken != null || _refreshToken != null;

  Future<void> setTokens({String? access, String? refresh}) async {
    _accessToken = access;
    _refreshToken = refresh;
    if (access != null) {
      await _store.write(TokenStore.accessTokenKey, access);
    } else {
      await _store.delete(TokenStore.accessTokenKey);
    }
    if (refresh != null) {
      await _store.write(TokenStore.refreshTokenKey, refresh);
    } else {
      await _store.delete(TokenStore.refreshTokenKey);
    }
  }

  Future<void> loadTokensFromStore() async {
    _accessToken = await _store.read(TokenStore.accessTokenKey);
    _refreshToken = await _store.read(TokenStore.refreshTokenKey);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    await _store.delete(TokenStore.accessTokenKey);
    await _store.delete(TokenStore.refreshTokenKey);
  }

  /// A signed GET for something read with its own connection — the live
  /// stream, which outlives any access token and so is signed afresh on each
  /// connect. Null when there is no session to sign with.
  Future<http.Request?> signedRequest(String path) async {
    if (_accessToken == null && _refreshToken != null) {
      try {
        await _refreshAccessToken();
      } on ApiException {
        return null;
      }
    }
    final String? token = _accessToken;
    if (token == null) return null;
    final http.Request request = http.Request('GET', _config.apiUrl(path));
    request.headers['Authorization'] = 'Bearer $token';
    return request;
  }

  /// The stream was answered 401: renew, so the next connect is signed with a
  /// token the server accepts.
  Future<void> renewSession() async {
    try {
      await _refreshAccessToken();
    } on ApiException {
      // The caller retries on its own schedule; a failure here is not fatal.
    }
  }

  // MARK: Requests

  /// The decoded body of a request — a `Map`, a `List`, or null.
  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    bool authorized = true,
  }) async {
    final Uint8List data = await _rawRequest(method, path, body: body, authorized: authorized);
    if (data.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException catch (error) {
      throw ApiException.decoding(error.message);
    }
  }

  /// A reply the caller decodes itself — a page, or a body with one key worth
  /// reading. Wraps whatever the decoder throws in [ApiException.decoding], so
  /// a call site only ever has to catch one kind of failure.
  Future<T> requestDecoded<T>(
    String method,
    String path,
    T Function(Object? json) decode, {
    Object? body,
    bool authorized = true,
  }) async {
    final Object? json = await request(method, path, body: body, authorized: authorized);
    return _decode(() => decode(json));
  }

  /// One object.
  Future<T> requestObject<T>(
    String method,
    String path,
    T Function(JsonMap) decode, {
    Object? body,
    bool authorized = true,
  }) async {
    final Object? json = await request(method, path, body: body, authorized: authorized);
    return _decode(() => decode(asMap(json)));
  }

  /// An array of objects.
  Future<List<T>> requestList<T>(
    String method,
    String path,
    T Function(JsonMap) decode, {
    Object? body,
    bool authorized = true,
  }) async {
    final Object? json = await request(method, path, body: body, authorized: authorized);
    return _decode(() {
      if (json is! List) throw JsonDecodeException('expected an array', value: json);
      return json.map((Object? item) => decode(asMap(item))).toList(growable: false);
    });
  }

  /// A reply whose body the caller does not need.
  Future<void> requestVoid(
    String method,
    String path, {
    Object? body,
    bool authorized = true,
  }) async {
    await _rawRequest(method, path, body: body, authorized: authorized);
  }

  /// Send one file as multipart/form-data.
  ///
  /// Separate from [_rawRequest] because the body is not JSON and the
  /// Content-Type has to carry the boundary. Deliberately not general: one
  /// file, one field, which is every upload the app makes.
  Future<T> upload<T>({
    required String path,
    required String fileName,
    required String mimeType,
    required Uint8List data,
    required T Function(JsonMap) decode,
    String fieldName = 'file',
  }) async {
    final Uri url = _config.apiUrl(path);

    // A fresh token first: a multipart retry would mean rebuilding the body,
    // and a photo is big enough that sending it twice is worth avoiding.
    if (_accessToken == null && _refreshToken != null) {
      await _refreshAccessToken();
    }

    final String boundary = 'fishers.${newUuid()}';
    final BytesBuilder body = BytesBuilder();
    void write(String text) => body.add(utf8.encode(text));
    write('--$boundary\r\n');
    write('Content-Disposition: form-data; name="$fieldName"; filename="$fileName"\r\n');
    write('Content-Type: $mimeType\r\n\r\n');
    body.add(data);
    write('\r\n--$boundary--\r\n');

    final http.Request request = http.Request('POST', url);
    request.headers['Content-Type'] = 'multipart/form-data; boundary=$boundary';
    final String? token = _accessToken;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.bodyBytes = body.takeBytes();

    final http.Response response = await _send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) throw const ApiException.unauthorized();
      throw ApiException.http(response.statusCode, response.body);
    }
    return _decode(() => decode(asMap(jsonDecode(response.body))));
  }

  Future<Uint8List> _rawRequest(
    String method,
    String path, {
    Object? body,
    required bool authorized,
    bool hasRefreshed = false,
  }) async {
    final Uri url = _config.apiUrl(path);
    final http.Request request = http.Request(method, url);
    request.headers['Content-Type'] = 'application/json';
    final String? token = _accessToken;
    if (authorized && token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) request.body = jsonEncode(body);

    final http.Response response = await _send(request);

    // Refresh once and retry once. Without the guard, a server that keeps
    // answering 401 sends this into an unbounded recursion.
    if (response.statusCode == 401 && authorized && !hasRefreshed && _refreshToken != null) {
      await _refreshAccessToken();
      return _rawRequest(method, path, body: body, authorized: true, hasRefreshed: true);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) throw const ApiException.unauthorized();
      throw ApiException.http(response.statusCode, response.body);
    }
    return response.bodyBytes;
  }

  Future<http.Response> _send(http.Request request) async {
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      // Anything the transport throws — no route to host, DNS, a TLS refusal —
      // is the same story to the person holding the phone.
      throw ApiException.unreachable(error.toString(), host: _config.apiBaseUrl.toString());
    }
  }

  /// Renew the session, one at a time.
  ///
  /// Dart runs one thing at a time, but every `await` is still a suspension
  /// point, so two requests answered 401 together would each reach the network
  /// with the same refresh token. The server rotates them — issuing a new pair
  /// revokes the old one — so the second would be refused and the loser would
  /// clear the store and sign the scorer out mid-match. Whoever asks second
  /// waits on the refresh already running instead.
  Future<void> _refreshAccessToken() {
    final Future<void>? inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final Future<void> task = _performRefresh();
    _refreshInFlight = task;
    return task.whenComplete(() => _refreshInFlight = null);
  }

  Future<void> _performRefresh() async {
    final String? refreshToken = _refreshToken;
    if (refreshToken == null) throw const ApiException.unauthorized();

    // Bypass the authorized path to avoid recursion.
    final http.Request request = http.Request('POST', _config.apiUrl('/auth/refresh'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(<String, dynamic>{'refresh_token': refreshToken});

    final http.Response response = await _send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await clearTokens();
      throw const ApiException.unauthorized();
    }
    final JsonMap tokens = asMap(jsonDecode(response.body));
    await setTokens(
      access: asString(tokens['access_token'], key: 'access_token'),
      refresh: asString(tokens['refresh_token'], key: 'refresh_token'),
    );
  }

  T _decode<T>(T Function() body) {
    try {
      return body();
    } on JsonDecodeException catch (error) {
      throw ApiException.decoding(error.toString());
    } on TypeError catch (error) {
      throw ApiException.decoding(error.toString());
    } on FormatException catch (error) {
      throw ApiException.decoding(error.message);
    }
  }

  void close() => _client.close();
}
