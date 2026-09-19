/// The decoding layer every model in this folder is built on.
///
/// Swift gets this for free: `Codable` plus a `CodingKeys` enum, and a
/// `JSONDecoder` configured once with a date strategy that every `Date` field
/// in every payload then goes through. Dart has no such thing, so the rules
/// live here and each model's `fromJson` reaches for them:
///
///   * [asDate] is the multi-format ISO-8601 reader from
///     `FishersJSONDecoder.decodeISO8601Date` in
///     `ios/Fishers/Services/NetworkService.swift` — with or without
///     fractional seconds, because chrono and Postgres disagree about whether
///     to write them and Foundation's plain `.iso8601` strategy rejects one of
///     the two.
///   * [encodeDate] writes the format `JSONEncoder.dateEncodingStrategy =
///     .iso8601` writes, which is the one without fractional seconds. Encoding
///     is therefore lossy in the same way iOS's is; a round trip preserves the
///     value to the second, not the microsecond.
///   * [asUuid] keeps ids as strings, lower-cased. Swift's `UUID` encodes
///     upper-case, and the API — Postgres, case-insensitively — accepts
///     either; lower case is what it sends, so it is what goes back.
library;

import 'package:flutter/foundation.dart';

/// Raised when a payload is not the shape the model needs. The network layer
/// turns this into `ApiError.decoding`, as `DecodingError` does on iOS.
class JsonDecodeException implements Exception {
  JsonDecodeException(this.message, {this.key, this.value});

  final String message;
  final String? key;
  final Object? value;

  @override
  String toString() {
    final StringBuffer out = StringBuffer('JsonDecodeException: $message');
    if (key != null) out.write(' (key "$key")');
    if (value != null) out.write(' — got ${value.runtimeType}: $value');
    return out.toString();
  }
}

/// The JSON object a `fromJson` is handed.
typedef JsonMap = Map<String, dynamic>;

JsonMap asMap(Object? value, {String? key}) {
  if (value is JsonMap) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw JsonDecodeException('expected an object', key: key, value: value);
}

JsonMap? asMapOrNull(Object? value, {String? key}) => value == null ? null : asMap(value, key: key);

/// A required string.
String asString(Object? value, {String? key}) {
  if (value is String) return value;
  throw JsonDecodeException('expected a string', key: key, value: value);
}

String? asStringOrNull(Object? value, {String? key}) =>
    value == null ? null : asString(value, key: key);

/// A required int. The API writes whole numbers as JSON numbers, which Dart may
/// hand back as a double when they came through a float path.
int asInt(Object? value, {String? key}) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  if (value is String) {
    final int? parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw JsonDecodeException('expected an integer', key: key, value: value);
}

int? asIntOrNull(Object? value, {String? key}) => value == null ? null : asInt(value, key: key);

double asDouble(Object? value, {String? key}) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final double? parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw JsonDecodeException('expected a number', key: key, value: value);
}

double? asDoubleOrNull(Object? value, {String? key}) =>
    value == null ? null : asDouble(value, key: key);

bool asBool(Object? value, {String? key}) {
  if (value is bool) return value;
  throw JsonDecodeException('expected a boolean', key: key, value: value);
}

bool? asBoolOrNull(Object? value, {String? key}) => value == null ? null : asBool(value, key: key);

/// An id. Kept as a string — see the library comment — and lower-cased so two
/// ids from different endpoints always compare equal.
String asUuid(Object? value, {String? key}) {
  final String raw = asString(value, key: key);
  if (!_looksLikeUuid(raw)) {
    throw JsonDecodeException('expected a UUID', key: key, value: value);
  }
  return raw.toLowerCase();
}

String? asUuidOrNull(Object? value, {String? key}) =>
    value == null ? null : asUuid(value, key: key);

/// The same, but a value that is present and malformed reads as absent rather
/// than sinking the row — what `UUID.init(uuidString:)` inside a `flatMap` does
/// on iOS, in `AppNotification` and the live-stream parser.
String? tryUuid(Object? value) {
  if (value is! String) return null;
  return _looksLikeUuid(value) ? value.toLowerCase() : null;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _looksLikeUuid(String raw) => _uuidPattern.hasMatch(raw);

/// Lower-case an id for use as a map key — `MatchState.nameKey` on iOS, where
/// Rust writes lower-case keys and Swift's `UUID` would write upper-case.
String uuidKey(String id) => id.toLowerCase();

/// ISO-8601, with or without fractional seconds.
///
/// `ios/Fishers/Services/NetworkService.swift` tries a formatter configured
/// `[.withInternetDateTime, .withFractionalSeconds]` and then one configured
/// `[.withInternetDateTime]`, and throws when neither reads it. `DateTime.parse`
/// accepts both of those, so the work here is rejecting what it would otherwise
/// wave through — a bare `2026-09-14` is a day, not an instant, and reading one
/// as midnight local time is how a fixture ends up on the wrong date.
DateTime asDate(Object? value, {String? key}) {
  final DateTime? parsed = tryDate(value);
  if (parsed != null) return parsed;
  throw JsonDecodeException('Unrecognized date', key: key, value: value);
}

DateTime? asDateOrNull(Object? value, {String? key}) =>
    value == null ? null : asDate(value, key: key);

/// A date that reads as absent when it cannot be parsed, rather than failing
/// the payload — `PlayCricketPlayerLink.lossyDate` and friends in
/// `ios/Fishers/Models/SeasonStats.swift`.
DateTime? tryDate(Object? value) {
  if (value is! String) return null;
  final String raw = value.trim();
  if (!_internetDateTime.hasMatch(raw)) return null;
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    return null;
  }
}

/// `YYYY-MM-DDThh:mm:ss[.sss…][Z|±hh:mm]` — the two formats iOS accepts, and
/// nothing else.
final RegExp _internetDateTime = RegExp(
  r'^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:?\d{2})$',
);

/// What `JSONEncoder.dateEncodingStrategy = .iso8601` writes: UTC, to the
/// second, with a `Z`.
String encodeDate(DateTime value) {
  final DateTime utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
      'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

String? encodeDateOrNull(DateTime? value) => value == null ? null : encodeDate(value);

/// A required list, mapped element by element.
List<T> asList<T>(Object? value, T Function(Object?) item, {String? key}) {
  if (value is! List) {
    throw JsonDecodeException('expected an array', key: key, value: value);
  }
  return value.map(item).toList(growable: false);
}

/// A list that reads as empty when the key is absent or null — the shape of
/// `decodeIfPresent([...].self, forKey:) ?? []`, which most of the models use.
List<T> asListOrEmpty<T>(Object? value, T Function(Object?) item, {String? key}) =>
    value == null ? const <Never>[] : asList<T>(value, item, key: key);

/// `[String: String]`, as `SportProfile.stats` wants it.
Map<String, String> asStringMap(Object? value, {String? key}) {
  if (value == null) return const <String, String>{};
  final JsonMap raw = asMap(value, key: key);
  return <String, String>{
    for (final MapEntry<String, dynamic> e in raw.entries)
      if (e.value is String) e.key: e.value as String,
  };
}

/// A `[String: Int]`-shaped map — `MatchState.pendingPenalties`.
Map<String, int> asIntMap(Object? value, {String? key}) {
  if (value == null) return const <String, int>{};
  final JsonMap raw = asMap(value, key: key);
  return <String, int>{
    for (final MapEntry<String, dynamic> e in raw.entries) e.key: asInt(e.value, key: e.key),
  };
}

/// Drop the nulls from a map that is about to be encoded.
///
/// Swift's `encodeIfPresent` leaves a nil key out of the payload altogether;
/// `encode` writes an explicit null. The models below use [compactJson] for the
/// first and write the null themselves for the second, because the API reads
/// the difference — `PATCH /clubs/{id}/page` treats a JSON null as "not
/// touched", which is why `ClubPageSettings.noIconPlayer` exists at all.
JsonMap compactJson(JsonMap map) {
  map.removeWhere((String _, dynamic value) => value == null);
  return map;
}

/// A string-backed enum, read the way Swift reads a `String`-raw-value enum.
T? enumFromRaw<T extends Enum>(List<T> values, String? raw, String Function(T) rawOf) {
  if (raw == null) return null;
  for (final T value in values) {
    if (rawOf(value) == raw) return value;
  }
  return null;
}

/// The same, but a value the app does not know about is an error rather than a
/// silent null — what `try container.decode(SomeEnum.self …)` does.
T enumFromRawOrThrow<T extends Enum>(
  List<T> values,
  Object? raw,
  String Function(T) rawOf, {
  String? key,
}) {
  final String text = asString(raw, key: key);
  final T? found = enumFromRaw<T>(values, text, rawOf);
  if (found != null) return found;
  throw JsonDecodeException('not a known value', key: key, value: raw);
}

/// Lightweight JSON value for event metadata — `JSONValue` in
/// `ios/Fishers/Models/Models.swift`.
///
/// Anything may arrive under `Event.metadata` and `ChatMessage.metadata`; this
/// holds it without deciding what it means, and gives it back unchanged.
@immutable
sealed class JsonValue {
  const JsonValue();

  /// The decoder is ordered as the Swift one is — bool before number before
  /// string — so `true` does not come back as a string.
  factory JsonValue.from(Object? raw) {
    if (raw == null) return const JsonNull();
    if (raw is bool) return JsonBool(raw);
    if (raw is num) return JsonNumber(raw.toDouble());
    if (raw is String) return JsonString(raw);
    if (raw is Map) {
      return JsonObject(<String, JsonValue>{
        for (final MapEntry<dynamic, dynamic> e in raw.entries)
          e.key.toString(): JsonValue.from(e.value),
      });
    }
    if (raw is List) {
      return JsonArray(raw.map(JsonValue.from).toList(growable: false));
    }
    // Swift's `init(from:)` ends `self = .null` rather than throwing.
    return const JsonNull();
  }

  static Map<String, JsonValue>? mapFrom(Object? raw) {
    if (raw == null) return null;
    final JsonMap object = asMap(raw);
    return <String, JsonValue>{
      for (final MapEntry<String, dynamic> e in object.entries) e.key: JsonValue.from(e.value),
    };
  }

  static Map<String, dynamic>? mapToJson(Map<String, JsonValue>? value) {
    if (value == null) return null;
    return <String, dynamic>{
      for (final MapEntry<String, JsonValue> e in value.entries) e.key: e.value.toJson(),
    };
  }

  Object? toJson();

  /// The text of a scalar, which is all `AppNotification` keeps.
  String? get asTextOrNull => switch (this) {
    JsonString(:final String value) => value,
    JsonNumber(:final double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString(),
    JsonBool(:final bool value) => value.toString(),
    _ => null,
  };
}

@immutable
class JsonString extends JsonValue {
  const JsonString(this.value);
  final String value;
  @override
  Object? toJson() => value;
  @override
  bool operator ==(Object other) => other is JsonString && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

@immutable
class JsonNumber extends JsonValue {
  const JsonNumber(this.value);
  final double value;
  @override
  Object? toJson() => value == value.roundToDouble() ? value.toInt() : value;
  @override
  bool operator ==(Object other) => other is JsonNumber && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

@immutable
class JsonBool extends JsonValue {
  const JsonBool(this.value);
  final bool value;
  @override
  Object? toJson() => value;
  @override
  bool operator ==(Object other) => other is JsonBool && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

@immutable
class JsonObject extends JsonValue {
  const JsonObject(this.value);
  final Map<String, JsonValue> value;
  @override
  Object? toJson() => <String, dynamic>{
    for (final MapEntry<String, JsonValue> e in value.entries) e.key: e.value.toJson(),
  };
  @override
  bool operator ==(Object other) =>
      other is JsonObject && mapEquals<String, JsonValue>(other.value, value);
  @override
  int get hashCode => Object.hashAllUnordered(
    value.entries.map((MapEntry<String, JsonValue> e) => Object.hash(e.key, e.value)),
  );
}

@immutable
class JsonArray extends JsonValue {
  const JsonArray(this.value);
  final List<JsonValue> value;
  @override
  Object? toJson() => value.map((JsonValue v) => v.toJson()).toList(growable: false);
  @override
  bool operator ==(Object other) => other is JsonArray && listEquals<JsonValue>(other.value, value);
  @override
  int get hashCode => Object.hashAll(value);
}

@immutable
class JsonNull extends JsonValue {
  const JsonNull();
  @override
  Object? toJson() => null;
  @override
  bool operator ==(Object other) => other is JsonNull;
  @override
  int get hashCode => 0;
}
