import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../config/app_config.dart';
import '../stores/chat_store.dart';
import '../stores/session_store.dart';
import '../theme/fishers_theme.dart';
import '../views/root_view.dart';

/// The root widget — `ios/Fishers/App/FishersApp.swift`.
///
/// The stores sit above a [RootView] that gates on authentication, the way
/// Swift puts `SessionStore` and friends above its own. `CartStore` and
/// `ClubContextStore` are not ported yet and are not needed by anything that
/// is.
class FishersApp extends StatelessWidget {
  const FishersApp({super.key, this.home});

  /// Overridden by tests that want one screen without the session in front of
  /// it. Production passes nothing and gets [RootView].
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SessionStore>(create: (_) => SessionStore()),
        ChangeNotifierProvider<ChatStore>(create: (_) => ChatStore()),
      ],
      child: MaterialApp(
        title: 'Fishers',
        theme: FishersTheme.light,
        darkTheme: FishersTheme.dark,
        // Follow the phone's setting, as the iOS app follows the system
        // appearance rather than carrying a switch of its own.
        themeMode: ThemeMode.system,
        home: home ?? const RootView(),
      ),
    );
  }
}

/// The palette, on a screen of its own.
///
/// It proves the theme renders in both appearances without anything else in
/// the app having to run, which is why it outlived being the home screen.
class PaletteProof extends StatelessWidget {
  const PaletteProof({super.key});

  @override
  Widget build(BuildContext context) => const _PaletteProof();
}

/// A placeholder that proves the theme renders: the ramp, the three
/// availability states, a card, and which API this build is pointed at.
class _PaletteProof extends StatelessWidget {
  const _PaletteProof();

  @override
  Widget build(BuildContext context) {
    final FishersColors colors = FishersColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fishers')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FishersTheme.space2),
          children: <Widget>[
            Text('Fishers', style: FishersTheme.brand(context)),
            const SizedBox(height: FishersTheme.space1),
            Text(
              'Sage, cream and gold — the same ramp as the iPhone app and the '
              'dashboard.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: FishersTheme.space3),
            const _Swatches(),
            const SizedBox(height: FishersTheme.space3),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(FishersTheme.space2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('AVAILABILITY', style: FishersTheme.overline(context)),
                    const SizedBox(height: FishersTheme.space1),
                    Row(
                      children: <Widget>[
                        _State(
                          label: 'Available',
                          icon: Icons.check_circle,
                          color: colors.available,
                        ),
                        const SizedBox(width: FishersTheme.space2),
                        _State(label: 'Maybe', icon: Icons.help, color: colors.maybe),
                        const SizedBox(width: FishersTheme.space2),
                        _State(label: "Can't play", icon: Icons.cancel, color: colors.unavailable),
                      ],
                    ),
                    const Divider(height: FishersTheme.space3),
                    Text('London Lords v Watford', style: FishersTheme.contentTitle(context)),
                    const SizedBox(height: FishersTheme.space1),
                    Text('124/6 (18.2)', style: FishersTheme.figure(context)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: FishersTheme.space3),
            Text(
              'API · ${AppConfig.instance.displayHost}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches();

  @override
  Widget build(BuildContext context) {
    const List<(String, Color)> ramp = <(String, Color)>[
      ('sage', FishersTheme.sage),
      ('sage600', FishersTheme.sage600),
      ('sage900', FishersTheme.sage900),
      ('gold', FishersTheme.gold),
      ('gold700', FishersTheme.gold700),
      ('cream', FishersTheme.creamPaper),
    ];
    return Wrap(
      spacing: FishersTheme.space1,
      runSpacing: FishersTheme.space1,
      children: <Widget>[
        for (final (String name, Color colour) in ramp)
          Container(
            width: 96,
            height: 56,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(FishersTheme.corner),
            ),
            child: Text(
              name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: FishersTheme.sage900),
            ),
          ),
      ],
    );
  }
}

class _State extends StatelessWidget {
  const _State({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Never colour alone: every use pairs with a label and an icon.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
      ],
    );
  }
}
