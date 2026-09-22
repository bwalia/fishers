import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/session_store.dart';
import '../theme/fishers_theme.dart';
import 'chat/chat_list_view.dart';

/// Top-level destinations — a port of `ios/Fishers/Views/MainTabView.swift`.
///
/// Five, in the same order, because the order is the app's shape and a
/// reordered bar is a different app. Only Chats is built: the other four are
/// named and reachable so the bar is honest about what is coming, and each
/// says so rather than rendering an empty screen that looks broken.
class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  /// Chats, because it is the one that works.
  int _index = 2;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = <Widget>[
      const _NotYet(title: 'Home', detail: 'The feed, the live match and what is coming up.'),
      const _NotYet(title: 'Fixtures', detail: 'The calendar, availability and selection.'),
      const ChatListView(),
      const _NotYet(title: 'Clubs', detail: 'Your clubs, their teams and the people in them.'),
      const _ProfileTab(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Fixtures'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Clubs'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// A destination that exists in the bar but not yet behind it. It says which
/// screen is missing rather than showing a blank one, because a blank screen
/// reads as a bug.
class _NotYet extends StatelessWidget {
  const _NotYet({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(FishersTheme.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.construction, size: 36, color: Theme.of(context).disabledColor),
            const SizedBox(height: FishersTheme.space2),
            Text('$title is not built yet', style: FishersTheme.contentTitle(context)),
            const SizedBox(height: FishersTheme.space1),
            Text(detail, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ),
  );
}

/// Enough of Profile to sign out, which is the one thing a signed-in person
/// needs that no other screen offers.
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final SessionStore session = context.watch<SessionStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: <Widget>[
          if (session.user != null)
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(session.user!.name),
              subtitle: Text(session.user!.email ?? session.user!.phone ?? ''),
            ),
          const Divider(),
          ListTile(
            key: const Key('profile.signOut'),
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: session.signOut,
          ),
        ],
      ),
    );
  }
}
