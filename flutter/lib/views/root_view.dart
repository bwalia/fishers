import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/push_registrar.dart';
import '../stores/session_store.dart';
import 'auth/auth_view.dart';
import 'main_tab_view.dart';

/// Signed in or not — a port of `ios/Fishers/Views/RootView.swift`.
///
/// The quick start sits between the two on iOS; it is not ported yet, so this
/// gates on authentication alone.
class RootView extends StatefulWidget {
  const RootView({super.key});

  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> {
  /// What the session was last time this built, so the change is acted on
  /// once rather than on every rebuild.
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionStore>().bootstrap();
    });
  }

  /// Registering for push is the one thing that follows the session rather
  /// than a screen: it starts when somebody signs in, because Android shows
  /// the prompt once and spending it on the launch screen wastes it, and it
  /// stops when they sign out, because a shared phone must not keep buzzing
  /// with the last person's club.
  void _followSession(bool signedIn) {
    if (signedIn) {
      PushRegistrar.shared.start();
    } else {
      PushRegistrar.shared.unregister();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool signedIn = context.select<SessionStore, bool>((SessionStore s) => s.isAuthenticated);
    if (signedIn != _wasSignedIn) {
      _wasSignedIn = signedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) => _followSession(signedIn));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: signedIn ? const MainTabView() : const AuthView(),
    );
  }
}
