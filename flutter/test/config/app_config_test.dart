import 'package:fishers/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Android half of `ios/FishersTests/AppConfigTests.swift`, plus the ring
/// table the brief asks for.
///
/// These run under the Dart VM, where `kReleaseMode` is false — so the
/// debug-build behaviour is what is exercised: loopback is a usable host and
/// the fallback is the emulator's view of this machine.
void main() {
  AppConfig configWith({
    Map<String, String> stored = const <String, String>{},
    Map<String, String> env = const <String, String>{},
  }) {
    return AppConfig(store: InMemoryConfigStore(stored), environment: env);
  }

  group('resolution order', () {
    test('falls back when nothing is set', () {
      expect(configWith().apiBaseUrl.toString(), configWith().emulatorApiBase);
      expect(configWith().webBaseUrl.toString(), configWith().emulatorWebBase);
    });

    /// The ports live in `.env`, which moves them — `API_PORT=8080` is enough
    /// to make a hard-coded 7312 point at nothing. A build passes the same
    /// file with `--dart-define-from-file=../.env`; under the Dart VM the
    /// process environment does the same job.
    test('the fallback follows the ports the stack is actually on', () {
      final AppConfig config = configWith(
        env: <String, String>{AppConfig.apiPortKey: '8080', AppConfig.webPortKey: '3000'},
      );
      expect(config.apiBaseUrl.toString(), 'http://10.0.2.2:8080');
      expect(config.webBaseUrl.toString(), 'http://10.0.2.2:3000');
    });

    test('without them, the fallback is what scripts/start.sh defaults to', () {
      final AppConfig config = configWith();
      expect(config.apiBaseUrl.toString(), 'http://10.0.2.2:${AppConfig.defaultApiPort}');
      expect(config.webBaseUrl.toString(), 'http://10.0.2.2:${AppConfig.defaultWebPort}');
    });

    test('a stored override beats the fallback', () async {
      final AppConfig config = configWith();
      final Uri url = await config.setApiBaseUrlOverride('https://int.fishers.cloud');
      expect(url.toString(), 'https://int.fishers.cloud');
      expect(config.apiBaseUrl.toString(), 'https://int.fishers.cloud');
      expect(config.storedApiOverride, 'https://int.fishers.cloud');
    });

    test('the environment beats a stored override', () {
      final AppConfig config = configWith(
        stored: <String, String>{AppConfig.apiDefaultsKey: 'https://acc.fishers.cloud'},
        env: <String, String>{AppConfig.apiEnvKey: 'https://test.fishers.cloud'},
      );
      expect(config.apiBaseUrl.toString(), 'https://test.fishers.cloud');
      expect(
        config.storedApiOverride,
        'https://acc.fishers.cloud',
        reason: 'the override is still stored, it just does not win',
      );
      expect(config.environmentPinsApi, isTrue);
    });

    test('an unusable environment value does not pin anything', () {
      final AppConfig config = configWith(
        stored: <String, String>{AppConfig.apiDefaultsKey: 'https://acc.fishers.cloud'},
        env: <String, String>{AppConfig.apiEnvKey: r'$(FISHERS_API_BASE_URL)'},
      );
      expect(config.environmentPinsApi, isFalse);
      expect(config.apiBaseUrl.toString(), 'https://acc.fishers.cloud');
    });

    test('clearing the override drops back to the fallback', () async {
      final AppConfig config = configWith();
      await config.setApiBaseUrlOverride('https://www.fishers.cloud');
      expect(config.apiBaseUrl.toString(), 'https://www.fishers.cloud');

      await config.clearApiBaseUrlOverride();
      expect(config.storedApiOverride, isNull, reason: 'the override survived the clear');
      expect(
        config.apiBaseUrl.toString(),
        isNot('https://www.fishers.cloud'),
        reason: 'requests still go to it',
      );
    });
  });

  group('what counts as a host', () {
    test('rejects garbage', () async {
      final AppConfig config = configWith();
      for (final String bad in <String>['not a url', '', r'$(FISHERS_API_BASE_URL)', '   ']) {
        await expectLater(
          config.setApiBaseUrlOverride(bad),
          throwsA(isA<ApiConfigException>()),
          reason: '"$bad" is not a host',
        );
      }
    });

    test('rejects a scheme that is not http(s)', () async {
      final AppConfig config = configWith();
      await expectLater(
        config.setApiBaseUrlOverride('ftp://int.fishers.cloud'),
        throwsA(isA<ApiConfigException>()),
      );
    });

    test('accepts a LAN address with a port', () async {
      final AppConfig config = configWith();
      final Uri url = await config.setApiBaseUrlOverride('http://192.168.1.177:7312');
      expect(url.host, '192.168.1.177');
      expect(url.port, 7312);
      expect(config.displayHost, '192.168.1.177:7312');
    });

    test('trims what was pasted', () async {
      final AppConfig config = configWith();
      final Uri url = await config.setApiBaseUrlOverride('  https://int.fishers.cloud  ');
      expect(url.toString(), 'https://int.fishers.cloud');
    });

    test('honours loopback in a debug build', () {
      expect(AppConfig.usableUrl('http://127.0.0.1:7312')?.host, '127.0.0.1');
    });
  });

  group('the URL a request is built from', () {
    test('carries the /api/v1 prefix', () {
      final AppConfig config = configWith(
        env: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      );
      expect(config.apiUrl('/clubs').toString(), 'https://int.fishers.cloud/api/v1/clubs');
      expect(
        config.apiUrl('/cricket/matches/abc/events').toString(),
        'https://int.fishers.cloud/api/v1/cricket/matches/abc/events',
      );
    });

    test('keeps a query string intact', () {
      final AppConfig config = configWith(
        env: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      );
      expect(
        config.apiUrl('/events?page=1&per_page=200&').toString(),
        'https://int.fishers.cloud/api/v1/events?page=1&per_page=200&',
      );
    });

    test('displayHost drops the port when there is none', () {
      final AppConfig config = configWith(
        env: <String, String>{AppConfig.apiEnvKey: 'https://www.fishers.cloud'},
      );
      expect(config.displayHost, 'www.fishers.cloud');
    });
  });

  group('rings', () {
    test('are the four devops deploys', () {
      expect(FishersRing.values.map((FishersRing r) => r.host), <String>[
        'int.fishers.cloud',
        'test.fishers.cloud',
        'acc.fishers.cloud',
        'www.fishers.cloud',
      ]);
    });

    test('each resolves to an https base URL', () {
      for (final FishersRing ring in FishersRing.values) {
        expect(ring.baseUrl.scheme, 'https');
        expect(ring.baseUrl.host, ring.host);
      }
    });

    test('a URL is matched back to its ring', () {
      expect(FishersRing.forUrl(Uri.parse('https://int.fishers.cloud')), FishersRing.int_);
      expect(FishersRing.forUrl(Uri.parse('https://acc.fishers.cloud/api/v1')), FishersRing.acc);
      expect(FishersRing.forUrl(Uri.parse('http://192.168.1.177:7312')), isNull);
    });

    test('production is the release fallback', () {
      expect(FishersRing.fallback, FishersRing.prod);
      expect(FishersRing.fallback.baseUrl.toString(), AppConfig.deviceApiBase);
    });

    test('a ring can be selected through the override', () async {
      final AppConfig config = configWith();
      for (final FishersRing ring in FishersRing.values) {
        await config.setApiBaseUrlOverride(ring.baseUrl.toString());
        expect(config.apiBaseUrl.host, ring.host);
        expect(config.apiUrl('/me').toString(), 'https://${ring.host}/api/v1/me');
      }
    });
  });
}
