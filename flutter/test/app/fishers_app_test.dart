import 'package:fishers/app/fishers_app.dart';
import 'package:fishers/theme/fishers_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The placeholder root exists to prove one thing: the theme is wired up, in
/// both appearances, and nothing else in the foundation has to be running for
/// it to render.
void main() {
  testWidgets('renders in light', (WidgetTester tester) async {
    await tester.pumpWidget(const FishersApp());
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

    await tester.pumpWidget(const FishersApp());
    await tester.pump();

    final BuildContext context = tester.element(find.text('Available'));
    expect(Theme.of(context).colorScheme.brightness, Brightness.dark);
    expect(Theme.of(context).colorScheme.primary, FishersTheme.sage);
    expect(FishersColors.of(context).mist, FishersTheme.mistDark);
  });

  testWidgets('says which server this build is pointed at', (WidgetTester tester) async {
    await tester.pumpWidget(const FishersApp());
    expect(find.textContaining('API · '), findsOneWidget);
  });
}
