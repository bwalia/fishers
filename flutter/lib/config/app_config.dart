import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which server this install talks to — a port of
/// `ios/Fishers/Config/AppConfig.swift`.
///
/// Resolution order, most specific first, the same four sources as iOS:
///
///   1. `FISHERS_API_URL` in the environment — `--dart-define`, or the process
///      environment when running under the Dart VM (`flutter test`, CI).
///      Wins over the settings panel, as the Xcode scheme does on iOS.
///   2. `FishersAPIBaseURL` in the key–value store — the settings panel.
///      iOS keeps this in `UserDefaults`; here it is `shared_preferences`.
///   3. `FishersAPIBaseURL` from the build — `--dart-define` at build time,
///      which is what Info.plist is on iOS (Release / TestFlight / App Store).
///   4. Fallback: a debug build reaches for the host machine's loopback; a
///      release build reaches for production.
///
/// iOS re-reads every source on every access so a settings change applies to
/// the next request without a restart. `shared_preferences` is asynchronous, so
/// [load] reads the store once at launch and [setApiBaseUrlOverride] keeps the
/// cached value in step — the accessors below stay synchronous, which is what
/// lets a request builder call them.
class AppConfig {
  AppConfig({AppConfigStore? store, Map<String, String>? environment})
    : _store = store ?? const _UnloadedStore(),
      _environment = environment ?? _processEnvironment();

  /// The one the app uses. Tests build their own rather than touching this.
  static AppConfig instance = AppConfig();

  AppConfigStore _store;
  final Map<String, String> _environment;

  /// Emulator fallback: the host machine's loopback as seen from an Android
  /// emulator. `127.0.0.1` inside the emulator is the emulator itself, so the
  /// address that reaches `scripts/start.sh` on the Mac is `10.0.2.2`.
  ///
  /// (iOS says `127.0.0.1` here because the Simulator shares the Mac's network
  /// stack. An emulator does not, which is the one substantive difference in
  /// this file.)
  static const String emulatorApiBase = 'http://10.0.2.2:7312';
  static const String emulatorWebBase = 'http://10.0.2.2:7311';

  /// Release fallback: production. A phone in someone else's hands cannot use
  /// a loopback address — that is the phone itself — and a LAN address shipped
  /// to a tester's network has no such host (or worse, some unrelated box
  /// answering on it). Prod is the only fallback that is right for a build that
  /// has left this machine; point a device at a local API with the settings
  /// panel or `FISHERS_API_URL`.
  static const String deviceApiBase = 'https://www.fishers.cloud';
  static const String deviceWebBase = 'https://www.fishers.cloud';

  /// Store / launch-argument key written by the settings panel.
  static const String apiDefaultsKey = 'FishersAPIBaseURL';
  static const String webDefaultsKey = 'FishersWebBaseURL';

  static const String apiEnvKey = 'FISHERS_API_URL';
  static const String webEnvKey = 'FISHERS_WEB_URL';

  static const String apiVersionPrefix = '/api/v1';

  /// The build-time equivalent of iOS's Info.plist entries. Empty unless a
  /// build passes `--dart-define=FishersAPIBaseURL=…`, which is how CI points
  /// a ring build at its own host.
  static const String _buildApiBase = String.fromEnvironment(apiDefaultsKey);
  static const String _buildWebBase = String.fromEnvironment(webDefaultsKey);

  /// `--dart-define=FISHERS_API_URL=…`. Read as a compile-time constant so it
  /// survives into a release build, where there is no process environment.
  static const String _definedApiEnv = String.fromEnvironment(apiEnvKey);
  static const String _definedWebEnv = String.fromEnvironment(webEnvKey);

  static Map<String, String> _processEnvironment() {
    // A release APK has no useful process environment, and reading it on some
    // platforms throws; the dart-define constants above cover that case.
    try {
      return Platform.environment;
    } on Object {
      return const <String, String>{};
    }
  }

  /// Read the stored override once, so the synchronous accessors have it.
  /// Called at launch, before the first request.
  Future<void> load() async {
    _store = await SharedPreferencesConfigStore.open();
  }

  /// Swap the backing store — how a test drives resolution without plugins.
  @visibleForTesting
  void useStore(AppConfigStore store) => _store = store;

  /// Where the API lives.
  Uri get apiBaseUrl => _resolve(
    env: _envValue(apiEnvKey, _definedApiEnv),
    key: apiDefaultsKey,
    build: _buildApiBase,
    fallback: _fallback(api: true),
  );

  /// Public web host, for live scoreboard links shared into chat.
  Uri get webBaseUrl => _resolve(
    env: _envValue(webEnvKey, _definedWebEnv),
    key: webDefaultsKey,
    build: _buildWebBase,
    fallback: _fallback(api: false),
  );

  /// Built-in default the settings panel's "Reset" restores to (ignores env).
  Uri get defaultApiBaseUrl => Uri.parse(_fallback(api: true));

  /// True when `FISHERS_API_URL` is pinning the API — a stored override cannot
  /// win over that for this process.
  bool get environmentPinsApi => _usableUrl(_envValue(apiEnvKey, _definedApiEnv)) != null;

  /// The raw stored override, if any. May differ from [apiBaseUrl] when the
  /// environment wins.
  String? get storedApiOverride => _store.getString(apiDefaultsKey);

  /// Shown when a build cannot reach its API, so whoever is holding the phone
  /// can say which server it was trying.
  String get displayHost {
    final Uri url = apiBaseUrl;
    if (url.host.isEmpty) return url.toString();
    return url.hasPort ? '${url.host}:${url.port}' : url.host;
  }

  /// A full URL for a path below `/api/v1`, which is every request the app
  /// makes. `/clubs` → `https://int.fishers.cloud/api/v1/clubs`.
  Uri apiUrl(String path) => Uri.parse('$apiBaseUrl$apiVersionPrefix$path');

  /// Persist an API base URL for subsequent requests. Rejects empty,
  /// unsubstituted and — in a release build — loopback values.
  Future<Uri> setApiBaseUrlOverride(String raw) async {
    final Uri? url = _usableUrl(raw);
    if (url == null) throw const ApiConfigException();
    final String scheme = url.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') throw const ApiConfigException();
    final String normalised = url.toString();
    await _store.setString(apiDefaultsKey, normalised);
    debugPrint('[Fishers] API base URL → $normalised (from settings)');
    return url;
  }

  /// Remove the stored override so the build's value and the fallback apply.
  Future<void> clearApiBaseUrlOverride() async {
    await _store.remove(apiDefaultsKey);
    debugPrint('[Fishers] API base URL override cleared → $apiBaseUrl');
  }

  String? _envValue(String key, String defined) {
    final String fromProcess = _environment[key] ?? '';
    return fromProcess.isNotEmpty ? fromProcess : (defined.isEmpty ? null : defined);
  }

  /// A debug build reaches for the host machine; a release build reaches for
  /// production. iOS splits this on Simulator vs device; Android has no such
  /// compile-time flag, and "is this a release build" is the same question in
  /// every case that matters — a release build is the one that leaves here.
  String _fallback({required bool api}) {
    if (kReleaseMode) return api ? deviceApiBase : deviceWebBase;
    return api ? emulatorApiBase : emulatorWebBase;
  }

  Uri _resolve({
    required String? env,
    required String key,
    required String build,
    required String fallback,
  }) {
    for (final String? raw in <String?>[env, _store.getString(key), build]) {
      final Uri? url = _usableUrl(raw);
      if (url != null) return url;
    }
    assert(!kReleaseMode, '$key is not set for this build configuration');
    return Uri.parse(fallback);
  }

  /// Empty and unsubstituted (`$(FISHERS_API_BASE_URL)`) values are not hosts.
  /// In a debug build loopback is honoured — that is the right address when the
  /// stack is running on this machine. In a release build, loopback is the
  /// phone itself, so it must not win over the fallback; it is rejected here so
  /// resolution falls through to production (or to an explicit override that
  /// names a real host).
  static Uri? _usableUrl(String? raw) {
    final String trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.startsWith(r'$(')) return null;
    final Uri? url = Uri.tryParse(trimmed);
    if (url == null || url.host.isEmpty || !url.hasScheme) return null;
    if (kReleaseMode) {
      const Set<String> loopback = <String>{'127.0.0.1', 'localhost', '::1'};
      if (loopback.contains(url.host)) return null;
    }
    return url;
  }

  /// Exposed for the tests, which exercise the same rules the panel relies on.
  @visibleForTesting
  static Uri? usableUrl(String? raw) => _usableUrl(raw);
}

/// The rings a build can be pointed at.
///
/// `devops/ring-promoter/fishers-apps.yaml` deploys all four; iOS's settings
/// panel only offers `int` and `www` as quick picks, alongside a LAN address
/// and Simulator loopback. All four are listed here because the brief calls for
/// testers to be able to reach int, test and acc — see `flutter/PARITY.md`.
enum FishersRing {
  int_('int', 'int.fishers.cloud'),
  test('test', 'test.fishers.cloud'),
  acc('acc', 'acc.fishers.cloud'),
  prod('prod', 'www.fishers.cloud');

  const FishersRing(this.id, this.host);

  final String id;
  final String host;

  String get label => host;
  Uri get baseUrl => Uri.parse('https://$host');

  /// The one a release build lands on with nothing else configured.
  static const FishersRing fallback = FishersRing.prod;

  static FishersRing? forUrl(Uri url) {
    for (final FishersRing ring in values) {
      if (url.host == ring.host) return ring;
    }
    return null;
  }
}

/// Raised when the settings panel is handed something that is not a host.
class ApiConfigException implements Exception {
  const ApiConfigException();

  /// The same sentence iOS shows, minus the Simulator variant.
  String get message =>
      'Enter a full URL such as https://int.fishers.cloud or '
      'http://192.168.1.10:7312 — not localhost on a phone';

  @override
  String toString() => message;
}

/// The synchronous key–value store [AppConfig] resolves against —
/// `UserDefaults` on iOS.
abstract class AppConfigStore {
  const AppConfigStore();

  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// Before [AppConfig.load] has run there is nothing stored, and writing would
/// be lost. Reads fall through to the build value and the fallback.
class _UnloadedStore extends AppConfigStore {
  const _UnloadedStore();

  @override
  String? getString(String key) => null;

  @override
  Future<void> setString(String key, String value) async {
    assert(false, 'AppConfig.load() has not run — the override would be lost');
  }

  @override
  Future<void> remove(String key) async {}
}

/// `shared_preferences`, read into memory once so the getters stay synchronous.
class SharedPreferencesConfigStore extends AppConfigStore {
  SharedPreferencesConfigStore(this._prefs);

  static Future<SharedPreferencesConfigStore> open() async =>
      SharedPreferencesConfigStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// A store a test can write to without a platform channel.
class InMemoryConfigStore extends AppConfigStore {
  InMemoryConfigStore([Map<String, String>? initial]) : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
