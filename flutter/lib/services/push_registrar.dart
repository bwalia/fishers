import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fishers_api.dart';

/// Remote push: asking for permission, handing the FCM token to the API, and
/// routing a tap — the Android half of
/// `ios/Fishers/Services/PushRegistrar.swift`.
///
/// There is no shared layer with the iOS one, only a shared endpoint. Both
/// register a token with `/notifications/register-device` and let the server
/// pick the transport from the `platform` column; what produces the token is
/// entirely different on each side.
///
/// Registration is deliberately late and quiet, for the same reason it is on
/// iOS: Android 13 shows the notification prompt once, so asking on the very
/// first launch — before anybody has joined a club or has a reason to want to
/// hear from us — spends that one chance on a stranger.
class PushRegistrar extends ChangeNotifier {
  PushRegistrar({FirebaseMessagingLike? messaging, bool? firebaseAvailable})
    : _injected = messaging,
      _forcedAvailability = firebaseAvailable;

  static final PushRegistrar shared = PushRegistrar();

  final FirebaseMessagingLike? _injected;
  final bool? _forcedAvailability;

  /// The token last sent to the API, so a relaunch does not re-POST the same
  /// one on every cold start.
  String? _registeredToken;

  /// Where a tapped notification wants to go. The app watches these and opens
  /// the thread; whoever handles one clears it.
  String? pendingConversationId;
  String? pendingMotmPollId;

  /// Whether this build has a Firebase project behind it.
  ///
  /// `false` on a checkout with no google-services.json, which is every
  /// machine that has not been given one — see `android/app/build.gradle.kts`.
  /// It is the same state the server calls "Android push is off".
  bool get isConfigured => _forcedAvailability ?? Firebase.apps.isNotEmpty;

  /// Called once the app has a signed-in account.
  ///
  /// A refusal is final and silent: Android will not ask again, and pestering
  /// somebody through an in-app alert for a permission the system has already
  /// recorded is worse than doing without.
  Future<void> start() async {
    final FirebaseMessagingLike? messaging = await _messaging();
    if (messaging == null) return;

    final bool granted = await messaging.requestPermission();
    if (!granted) return;

    final String? token = await messaging.getToken();
    if (token != null) await _register(token);

    // Tokens rotate — on reinstall, on a restore to a new device, and on
    // Firebase's own schedule. A rotated token that is never re-registered is
    // a phone that silently stops hearing anything.
    messaging.onTokenRefresh.listen(_register);
    messaging.onMessageOpenedApp.listen(route);

    // A notification that started the app cold arrives here rather than on
    // the stream, and is the whole reason somebody is looking at the screen.
    final Map<String, String>? initial = await messaging.initialMessageData();
    if (initial != null) route(initial);
  }

  /// Stop pushing to this phone when somebody signs out of it. A shared
  /// family tablet would otherwise keep buzzing with the last person's club.
  Future<void> unregister() async {
    final String? token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await FishersAPI.unregisterDevice(token: token);
    } on Object {
      // The server drops a token it cannot deliver to anyway.
    }
  }

  /// The two ids Fishers puts in a notification's data.
  ///
  /// FCM's `data` carries strings and nothing else, which is why the server
  /// stringifies the payload before sending it — so these arrive as strings
  /// whatever they were on the way in.
  void route(Map<String, String> data) {
    final String? conversation = data['conversation_id'];
    final String? poll = data['motm_poll_id'];
    if (conversation != null) pendingConversationId = conversation;
    if (poll != null) pendingMotmPollId = poll;
    if (conversation != null || poll != null) notifyListeners();
  }

  Future<void> _register(String token) async {
    if (token == _registeredToken) return;
    _registeredToken = token;
    try {
      await FishersAPI.registerDevice(token: token, platform: 'android');
    } on Object catch (error) {
      // Worth a line and nothing else: the notification is stored server-side
      // regardless, so the bell still fills up and the only thing lost is the
      // buzz in the pocket.
      _registeredToken = null;
      debugPrint('push: could not register this device — $error');
    }
  }

  /// `null` when this build has no Firebase project, which is not an error.
  Future<FirebaseMessagingLike?> _messaging() async {
    if (_injected != null) return isConfigured ? _injected : null;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } on Object catch (error) {
      // No google-services.json, so no default options. The same state the
      // server reports as "Android push is off".
      debugPrint('push: no Firebase project in this build — push is off ($error)');
      return null;
    }
    return _RealFirebaseMessaging(FirebaseMessaging.instance);
  }
}

/// The slice of `FirebaseMessaging` this app uses.
///
/// Named so a test can stand in for it: the real one reaches for a platform
/// channel the moment it is touched, and there is no Android under a widget
/// test.
abstract class FirebaseMessagingLike {
  Future<bool> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<Map<String, String>> get onMessageOpenedApp;

  /// The notification that started the app cold, if one did.
  Future<Map<String, String>?> initialMessageData();
}

class _RealFirebaseMessaging implements FirebaseMessagingLike {
  _RealFirebaseMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<bool> requestPermission() async {
    final NotificationSettings settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, String>> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_dataOf);

  @override
  Future<Map<String, String>?> initialMessageData() async {
    final RemoteMessage? message = await _messaging.getInitialMessage();
    return message == null ? null : _dataOf(message);
  }

  static Map<String, String> _dataOf(RemoteMessage message) => <String, String>{
    for (final MapEntry<String, dynamic> e in message.data.entries)
      e.key: e.value?.toString() ?? '',
  };
}
