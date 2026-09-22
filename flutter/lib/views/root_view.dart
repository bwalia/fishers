import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionStore>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool signedIn = context.select<SessionStore, bool>((SessionStore s) => s.isAuthenticated);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: signedIn ? const MainTabView() : const AuthView(),
    );
  }
}
