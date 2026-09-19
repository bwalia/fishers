import 'dart:math';

/// A v4 UUID, lower-cased, from the platform's secure random source.
///
/// Small enough not to be worth a dependency, and needed in three places: the
/// multipart boundary in `NetworkService.upload`, the `client_event_id` on a
/// scoring event, and — the one that matters — the match id the device mints
/// **before the API is involved**, so a scorer can start a match on a ground
/// with no signal.
String newUuid() {
  final Random random = _random;
  final List<int> bytes = List<int>.generate(16, (int _) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final String hex = bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final Random _random = _secureOrNot();

Random _secureOrNot() {
  try {
    return Random.secure();
  } on UnsupportedError {
    // No secure source on this platform. An id that is merely unique is still
    // a working id — these are not secrets.
    return Random();
  }
}
