import 'dart:convert';
import 'dart:io';

import 'package:fishers/models/json.dart';
import 'package:flutter_test/flutter_test.dart';

/// The JSON under `test/fixtures/api/` — **real responses**, captured from the
/// Fishers API running locally against a seeded database. `MANIFEST.json` names
/// the endpoint each one came from. None of it is invented.
///
/// `flutter test` runs with the package root as the working directory, so the
/// relative path below is the one to use.
const String fixtureDir = 'test/fixtures/api';

JsonMap loadFixture(String name) =>
    asMap(jsonDecode(File('$fixtureDir/$name.json').readAsStringSync()));

List<dynamic> loadFixtureList(String name) =>
    jsonDecode(File('$fixtureDir/$name.json').readAsStringSync()) as List<dynamic>;

Map<String, String> loadManifest() {
  final JsonMap raw = loadFixture('MANIFEST');
  return <String, String>{
    for (final MapEntry<String, dynamic> e in raw.entries) e.key: e.value as String,
  };
}

/// The round trip, in three assertions.
///
/// 1. **Fidelity.** Every field the model writes back matches what the server
///    sent — recursively, normalised for the two places where the wire form is
///    not canonical: a timestamp's fractional seconds, which
///    `JSONEncoder.dateEncodingStrategy = .iso8601` drops on iOS and
///    [encodeDate] drops here, and a UUID's case. This is what catches a
///    `CodingKeys` string that was typed wrong: a mismatched key reads as null
///    and the value stops matching.
/// 2. **Stability.** Encoding is idempotent after the first pass, so a value
///    the app holds can be written, read and written again unchanged.
/// 3. **Coverage.** No wire key the server sent is silently dropped, unless it
///    is listed — with a reason — in [ignoredWireKeys].
void expectRoundTrip<T>(
  String fixture,
  T Function(JsonMap) fromJson,
  JsonMap Function(T) toJson, {
  Set<String> ignoredWireKeys = const <String>{},
}) {
  final JsonMap original = loadFixture(fixture);
  _checkRoundTrip<T>(fixture, original, fromJson, toJson, ignoredWireKeys);
}

/// The same, for a fixture that is a bare array.
void expectListRoundTrip<T>(
  String fixture,
  T Function(JsonMap) fromJson,
  JsonMap Function(T) toJson, {
  Set<String> ignoredWireKeys = const <String>{},
}) {
  final List<dynamic> original = loadFixtureList(fixture);
  expect(original, isNotEmpty, reason: '$fixture captured nothing to check');
  for (final dynamic raw in original) {
    _checkRoundTrip<T>(fixture, asMap(raw), fromJson, toJson, ignoredWireKeys);
  }
}

void _checkRoundTrip<T>(
  String fixture,
  JsonMap original,
  T Function(JsonMap) fromJson,
  JsonMap Function(T) toJson,
  Set<String> ignoredWireKeys,
) {
  final T once = fromJson(original);
  final JsonMap written = jsonDecode(jsonEncode(toJson(once))) as JsonMap;

  _expectMatchesSource(written, original, path: fixture);

  final T twice = fromJson(written);
  final JsonMap rewritten = jsonDecode(jsonEncode(toJson(twice))) as JsonMap;
  expect(
    jsonEncode(rewritten),
    jsonEncode(written),
    reason: '$fixture does not encode to the same JSON the second time',
  );
  expect(
    fromJson(rewritten),
    twice,
    reason: '$fixture: two identical payloads decode to unequal values — check ==',
  );

  final Set<String> dropped = original.keys.toSet()
    ..removeAll(written.keys)
    ..removeAll(ignoredWireKeys);
  expect(
    dropped,
    isEmpty,
    reason:
        '$fixture has wire keys the model never reads or writes: $dropped — '
        'either add them or list them in ignoredWireKeys with a reason',
  );
}

/// Every value in [written] must match [source] at the same path.
void _expectMatchesSource(Object? written, Object? source, {required String path}) {
  if (written == null) {
    expect(source, isNull, reason: '$path: the model dropped a value the server sent');
    return;
  }
  if (written is Map) {
    expect(source, isA<Map>(), reason: '$path: expected an object from the server');
    final Map<dynamic, dynamic> from = source! as Map<dynamic, dynamic>;
    for (final MapEntry<dynamic, dynamic> entry in written.entries) {
      if (entry.value == null && !from.containsKey(entry.key)) continue;
      expect(
        from.containsKey(entry.key),
        isTrue,
        reason: '$path.${entry.key}: written but never sent — is the wire name right?',
      );
      _expectMatchesSource(entry.value, from[entry.key], path: '$path.${entry.key}');
    }
    return;
  }
  if (written is List) {
    expect(source, isA<List>(), reason: '$path: expected an array from the server');
    final List<dynamic> from = source! as List<dynamic>;
    expect(written, hasLength(from.length), reason: '$path: the array changed length');
    for (int i = 0; i < written.length; i++) {
      _expectMatchesSource(written[i], from[i], path: '$path[$i]');
    }
    return;
  }
  expect(
    _normalise(written),
    _normalise(source),
    reason: '$path: the value the model writes is not the value it was sent',
  );
}

/// Timestamps lose their fractional seconds on the way out (iOS does the same),
/// and ids come back lower-cased. Nothing else is allowed to change.
Object? _normalise(Object? value) {
  if (value is String) {
    final DateTime? date = tryDate(value);
    if (date != null) return encodeDate(date);
    return tryUuid(value) ?? value;
  }
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return value;
}
