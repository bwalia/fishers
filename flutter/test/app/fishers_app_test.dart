import 'package:fishers/app/fishers_app.dart';
import 'package:fishers/theme/fishers_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The palette screen exists to prove one thing: the theme is wired up, in
/// both appearances, and nothing else has to be running for it to render.
///
/// It is no longer the app's home — [RootView] is, and it gates on the
/// session — so these pump it directly through `FishersApp.home`. That is
/// what the parameter is for: one screen, without the session in front of it.
void main() {
  testWidgets('renders in light', (WidgetTester tester) async {
    await tester.pumpWidget(const FishersApp(home: PaletteProof()));
    expect(find.text('Fishers'), findsWidgets);
    expect(find.text('Available'), findsOneWidget);

    final BuildContext context = tester.element(find.text('Available'));
    expect(Theme.of(context).colorScheme.brightness, Brightness.light);
    expect(Theme.of(context).colorScheme.primary, FishersTheme.sage600);
    expect(FishersColors.of(context).mist, FishersTheme.mistLight);
  });

  testWidgets('renders in dark', (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const FishersApp(home: PaletteProof()));
    await tester.pump();

    final BuildContext context = tester.element(find.text('Available'));
    expect(Theme.of(context).colorScheme.brightness, Brightness.dark);
    expect(Theme.of(context).colorScheme.primary, FishersTheme.sage);
    expect(FishersColors.of(context).mist, FishersTheme.mistDark);
  });

  testWidgets('says which server this build is pointed at', (WidgetTester tester) async {
    await tester.pumpWidget(const FishersApp(home: PaletteProof()));
    expect(find.textContaining('API · '), findsOneWidget);
  });
}
