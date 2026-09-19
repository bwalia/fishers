import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the session lives between launches — a port of
/// `ios/Fishers/Services/KeychainStore.swift`.
///
/// iOS puts the two tokens in the keychain under the service `com.fishers.app`.
/// The Android half of that is `flutter_secure_storage`, which is
/// `EncryptedSharedPreferences` backed by the Android Keystore. Same two keys,
/// same names, so a reader of either app finds the same thing.
abstract class TokenStore {
  const TokenStore();

  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The real one.
class KeychainStore extends TokenStore {
  KeychainStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // `EncryptedSharedPreferences` is what makes this the Keystore
            // rather than a plain preferences file, which is the whole point.
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// A store with no platform channel behind it, for tests.
class InMemoryTokenStore extends TokenStore {
  InMemoryTokenStore([Map<String, String>? initial]) : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  Map<String, String> get values => Map<String, String>.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
