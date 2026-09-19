import 'dart:math' as math;

import 'package:fishers/theme/fishers_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The palette is the club's, not Material's default, and the hex values are
/// the ones in `ios/Fishers/Theme/FishersTheme.swift`. If one of these fails,
/// somebody re-derived a colour instead of copying it.
void main() {
  group('the ramp', () {
    test('the four, as given', () {
      expect(FishersTheme.sage, const Color(0xFF8FA28A));
      expect(FishersTheme.sagePale, const Color(0xFFC7D3C0));
      expect(FishersTheme.creamPaper, const Color(0xFFF7F4ED));
      expect(FishersTheme.gold, const Color(0xFFC8A96B));
    });

    test('darkened until they carry text', () {
      expect(FishersTheme.sage500, const Color(0xFF798C76));
      expect(FishersTheme.sage600, const Color(0xFF667964));
      expect(FishersTheme.sage700, const Color(0xFF556754));
      expect(FishersTheme.sage800, const Color(0xFF445645));
      expect(FishersTheme.sage900, const Color(0xFF2C3A2D));
      expect(FishersTheme.gold600, const Color(0xFF927947));
      expect(FishersTheme.gold700, const Color(0xFF7E673A));
      expect(FishersTheme.red600, const Color(0xFFB3402F));
      expect(FishersTheme.red500, const Color(0xFFC8533F));
    });

    test('sage600 on white clears AA for body text', () {
      expect(_contrast(FishersTheme.sage600, Colors.white), closeTo(4.68, 0.02));
    });

    test('gold700 on white clears AA for body text', () {
      expect(_contrast(FishersTheme.gold700, Colors.white), closeTo(5.40, 0.02));
    });
  });

  group('light and dark', () {
    test('dark mixes its surfaces from the sage hue, not from grey', () {
      for (final Color surface in <Color>[
        FishersTheme.mistDark,
        FishersTheme.creamDark,
        FishersTheme.raisedDark,
      ]) {
        final HSLColor hsl = HSLColor.fromColor(surface);
        expect(
          hsl.saturation,
          greaterThan(0.05),
          reason: '${surface.toString()} has been flattened to grey',
        );
        expect(
          hsl.hue,
          closeTo(HSLColor.fromColor(FishersTheme.sage).hue, 30),
          reason: '${surface.toString()} is not the sage hue',
        );
      }
    });

    test('the accent lightens in dark, as the dashboard does', () {
      expect(FishersTheme.accentLight, FishersTheme.sage600);
      expect(FishersTheme.accentDark, FishersTheme.sage);
      expect(
        HSLColor.fromColor(FishersTheme.accentDark).lightness,
        greaterThan(HSLColor.fromColor(FishersTheme.accentLight).lightness),
      );
    });

    test('availability keeps three distinguishable states in both appearances', () {
      final List<Color> light = <Color>[
        FishersColors.light.available,
        FishersColors.light.maybe,
        FishersColors.light.unavailable,
      ];
      final List<Color> dark = <Color>[
        FishersColors.dark.available,
        FishersColors.dark.maybe,
        FishersColors.dark.unavailable,
      ];
      expect(light.toSet(), hasLength(3));
      expect(dark.toSet(), hasLength(3));
    });

    test('a four and a six are told apart, not both read as pitch green', () {
      expect(FishersTheme.four, isNot(FishersTheme.six));
      final double fourHue = HSLColor.fromColor(FishersTheme.four).hue;
      final double sixHue = HSLColor.fromColor(FishersTheme.six).hue;
      expect((fourHue - sixHue).abs(), greaterThan(60));
    });

    test('both schemes are built and carry the palette', () {
      expect(FishersTheme.light.colorScheme.brightness, Brightness.light);
      expect(FishersTheme.light.colorScheme.primary, FishersTheme.sage600);
      expect(FishersTheme.light.scaffoldBackgroundColor, FishersTheme.mistLight);

      expect(FishersTheme.dark.colorScheme.brightness, Brightness.dark);
      expect(FishersTheme.dark.colorScheme.primary, FishersTheme.sage);
      expect(FishersTheme.dark.scaffoldBackgroundColor, FishersTheme.mistDark);
    });

    test('Material 3 is on in both', () {
      expect(FishersTheme.light.useMaterial3, isTrue);
      expect(FishersTheme.dark.useMaterial3, isTrue);
    });

    test('the FishersColors extension is attached to both themes', () {
      expect(FishersTheme.light.extension<FishersColors>(), FishersColors.light);
      expect(FishersTheme.dark.extension<FishersColors>(), FishersColors.dark);
    });
  });

  group('metrics', () {
    test('match the Swift file, with Android\'s bigger touch target', () {
      expect(FishersTheme.space1, 8);
      expect(FishersTheme.space2, 16);
      expect(FishersTheme.space3, 24);
      expect(FishersTheme.space4, 32);
      expect(FishersTheme.corner, 14);
      expect(FishersTheme.minTapIOS, 44);
      expect(FishersTheme.minTap, 48, reason: 'Material asks for 48dp where iOS asks for 44pt');
    });
  });

  group('type', () {
    testWidgets('honours the system text scale', (WidgetTester tester) async {
      Future<double> renderedSize(double scale) async {
        late double size;
        await tester.pumpWidget(
          MaterialApp(
            theme: FishersTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Builder(
                builder: (BuildContext context) {
                  final TextStyle style = Theme.of(context).textTheme.bodyMedium!;
                  size = MediaQuery.textScalerOf(context).scale(style.fontSize!);
                  return Text('Boom Blast', style: style);
                },
              ),
            ),
          ),
        );
        return size;
      }

      final double normal = await renderedSize(1.0);
      final double large = await renderedSize(2.0);
      expect(large, greaterThan(normal));
      expect(
        large,
        closeTo(normal * 2, 0.01),
        reason: 'nothing may pin a font size against the system setting',
      );
    });

    testWidgets('figures are tabular so a score column does not jitter', (
      WidgetTester tester,
    ) async {
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: FishersTheme.light,
          home: Builder(
            builder: (BuildContext context) {
              style = FishersTheme.figure(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.fontWeight, FontWeight.bold);
    });

    testWidgets('the overline is a short, spaced, muted label', (WidgetTester tester) async {
      late TextStyle style;
      late ColorScheme scheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: FishersTheme.light,
          home: Builder(
            builder: (BuildContext context) {
              style = FishersTheme.overline(context);
              scheme = Theme.of(context).colorScheme;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(style.letterSpacing, 0.8);
      expect(style.color, scheme.onSurfaceVariant);
    });
  });
}

/// WCAG relative-luminance contrast, so the comments in the Swift file can be
/// checked rather than taken on trust.
double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

double _luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}
