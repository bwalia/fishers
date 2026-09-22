import 'package:flutter/foundation.dart';

import '../models/fishers_models.dart';
import '../services/fishers_api.dart';
import '../services/network_service.dart';

/// Who is signed in — a port of `ios/Fishers/ViewModels/SessionStore.swift`.
///
/// `ChangeNotifier` stands in for `ObservableObject`, and the fields below are
/// its `@Published` ones. Every screen reads this rather than the token store:
/// a token is plumbing, and "is anybody signed in" is a question about the
/// app, not about the keychain.
class SessionStore extends ChangeNotifier {
  /// Reads `NetworkService.shared` on each use rather than holding one.
  ///
  /// `FishersAPI` is a static facade over that same singleton, so a store
  /// holding its *own* service would take tokens from one place and send
  /// requests through another — which is a test that quietly talks to the
  /// real network. Swapping `NetworkService.shared` is how the rest of this
  /// suite stubs the wire, and this follows it.
  NetworkService get _net => NetworkService.shared;

  PublicUser? _user;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;

  PublicUser? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Sign back in from what the keychain kept, on launch.
  ///
  /// A stored token that the server no longer accepts is cleared rather than
  /// kept: the alternative is an app that looks signed in and fails every
  /// request, which is worse than an honest sign-in screen.
  Future<void> bootstrap() async {
    await _net.loadTokensFromStore();
    if (_net.accessToken == null) return;
    _setLoading(true);
    try {
      _user = await FishersAPI.me();
      _isAuthenticated = true;
      _errorMessage = null;
    } on Object {
      await _net.clearTokens();
      _isAuthenticated = false;
      _user = null;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signIn({required String identifier, required String password}) =>
      _authenticate(() => FishersAPI.login(identifier: identifier, password: password));

  Future<void> signUp({
    required String name,
    String? email,
    String? phone,
    required String password,
    RoleIntent? role,
  }) async {
    await _authenticate(
      () => FishersAPI.signup(name: name, email: email, phone: phone, password: password),
    );
    // Asked on the form, before there is an account to save it on, so it goes
    // up straight after. Failing to save it is not worth failing the signup
    // for — Home asks again when it is missing.
    if (_isAuthenticated && role != null) {
      try {
        _user = await FishersAPI.setRoleIntent(role);
        notifyListeners();
      } on Object {
        // Left for Home to ask about again.
      }
    }
  }

  Future<void> signOut() async {
    await _net.clearTokens();
    _user = null;
    _isAuthenticated = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// The API's own sentence, when it sent one. `ApiException.message` already
  /// prefers the `error` field over the status line, so a refusal reads as
  /// the server wrote it.
  Future<void> _authenticate(Future<AuthTokens> Function() work) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final AuthTokens tokens = await work();
      await _net.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken);
      _user = tokens.user;
      _isAuthenticated = true;
    } on ApiException catch (error) {
      _errorMessage = error.friendlyMessage;
      _isAuthenticated = false;
    } on Object catch (error) {
      _errorMessage = '$error';
      _isAuthenticated = false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
