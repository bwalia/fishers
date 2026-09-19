import 'package:flutter/material.dart';

/// Fishers visual language — sage, cream and gold, on Material 3.
///
/// A port of `ios/Fishers/Theme/FishersTheme.swift`. Every hex value below is
/// copied from that file rather than re-derived: the four the club chose are
/// sage #8FA28A, pale sage #C7D3C0, cream #F7F4ED and gold #C8A96B, and they
/// are all light, so none of them carries white text — sage on white is 2.7:1.
/// The ramp darkens each towards a deep bottle green until it does. The same
/// hex values the dashboard uses, so a club's phone and its laptop are the
/// same product.
///
/// Dark is not a grey inversion: the surfaces are mixed from the same sage hue,
/// so the two appearances are the same room at different times of day.
///
/// Type is Material's, sized by the platform: [FishersTheme.light] and
/// [FishersTheme.dark] leave `textScaler` alone, so Android's font-size setting
/// reaches every label the way iOS Dynamic Type does.
abstract final class FishersTheme {
  // MARK: The ramp

  /// The four, as given.
  static const Color sage = Color(0xFF8FA28A);
  static const Color sagePale = Color(0xFFC7D3C0);
  static const Color creamPaper = Color(0xFFF7F4ED);
  static const Color gold = Color(0xFFC8A96B);

  /// Darkened until they carry text.
  static const Color sage500 = Color(0xFF798C76);
  static const Color sage600 = Color(0xFF667964); // + white 4.68:1
  static const Color sage700 = Color(0xFF556754);
  static const Color sage800 = Color(0xFF445645);
  static const Color sage900 = Color(0xFF2C3A2D);

  static const Color gold600 = Color(0xFF927947);
  static const Color gold700 = Color(0xFF7E673A); // + white 5.40:1

  static const Color red600 = Color(0xFFB3402F);
  static const Color red500 = Color(0xFFC8533F);

  // MARK: Semantic
  //
  // iOS resolves these through `Color(light:dark:)`, which picks per trait
  // collection. Dart has no such type, so each is a light/dark pair and the
  // [FishersColors] theme extension is what a widget actually reads.

  /// Tints every control. Dark needs a *lighter* sage, not a darker one — the
  /// same swap the dashboard makes. (`AccentColor` in the iOS asset catalogue.)
  static const Color accentLight = sage600;
  static const Color accentDark = sage;

  static const Color pitchLight = sage600;
  static const Color pitchDark = sage;

  /// Availability has to stay legible as three states, so these are pulled
  /// towards the palette rather than replaced by it: sage for yes, gold for
  /// maybe, the ball's red for no. Never the only signal — every use pairs with
  /// a label or an icon.
  static const Color availableLight = sage600;
  static const Color availableDark = sagePale;
  static const Color maybeLight = gold700;
  static const Color maybeDark = gold;
  static const Color unavailableLight = red600;
  static const Color unavailableDark = red500;

  /// The seam on a cricket ball.
  static const Color seam = red600;

  /// Boundary colours, the same two the web uses, so blue and orange mean the
  /// same thing on a phone as on the dashboard — and so a four and a six are
  /// told apart at a glance instead of both reading as pitch green. Far enough
  /// apart for the common kinds of colour blindness.
  static const Color four = Color.fromRGBO(47, 128, 237, 1); // 0.184, 0.502, 0.929
  static const Color six = Color.fromRGBO(242, 113, 28, 1); // 0.949, 0.443, 0.110

  /// The page, and the cards on it. Grouped-background semantics, but in the
  /// club's cream rather than iOS grey.
  static const Color mistLight = creamPaper;
  static const Color mistDark = Color(0xFF111712);
  static const Color creamLight = Colors.white;
  static const Color creamDark = Color(0xFF171D17);

  /// One step raised from a card — chips, wells, table stripes.
  static const Color raisedLight = Color(0xFFF1EFE6);
  static const Color raisedDark = Color(0xFF1C231C);

  static const Color hairlineLight = Color(0xFFE0DED1);
  static const Color hairlineDark = Color(0xFF2A332A);

  /// Ink and muted follow the scheme's on-surface colours rather than being
  /// fixed, exactly as `Color.primary` / `Color.secondary` do on iOS.
  static const Color inkLight = Color(0xFF1A1C19);
  static const Color inkDark = Color(0xFFE3E5DF);
  static const Color mutedLight = Color(0xFF5C6158);
  static const Color mutedDark = Color(0xFFA9B0A4);

  // MARK: Metrics — the same numbers as the Swift file

  static const double space1 = 8;
  static const double space2 = 16;
  static const double space3 = 24;
  static const double space4 = 32;

  /// Material's minimum touch target is 48dp where iOS's is 44pt; the iOS
  /// value is kept for reference and [minTap] is the one to lay out against.
  static const double minTapIOS = 44;
  static const double minTap = 48;
  static const double corner = 14;

  // MARK: Colour schemes

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: sage600,
    onPrimary: Colors.white,
    primaryContainer: sagePale,
    onPrimaryContainer: sage900,
    secondary: gold700,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFEFE3CC),
    onSecondaryContainer: Color(0xFF3B2F16),
    tertiary: sage700,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFDCE6D6),
    onTertiaryContainer: sage900,
    error: red600,
    onError: Colors.white,
    errorContainer: Color(0xFFF7DAD4),
    onErrorContainer: Color(0xFF410E06),
    surface: creamLight,
    onSurface: inkLight,
    surfaceDim: Color(0xFFE6E3D9),
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: creamPaper,
    surfaceContainer: raisedLight,
    surfaceContainerHigh: Color(0xFFEAE7DC),
    surfaceContainerHighest: Color(0xFFE3E0D4),
    onSurfaceVariant: mutedLight,
    outline: Color(0xFF74796E),
    outlineVariant: hairlineLight,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: sage900,
    onInverseSurface: creamPaper,
    inversePrimary: sagePale,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: sage,
    onPrimary: sage900,
    primaryContainer: sage700,
    onPrimaryContainer: sagePale,
    secondary: gold,
    onSecondary: Color(0xFF3B2F16),
    secondaryContainer: gold700,
    onSecondaryContainer: Color(0xFFF3E7D2),
    tertiary: sagePale,
    onTertiary: sage900,
    tertiaryContainer: sage800,
    onTertiaryContainer: sagePale,
    error: red500,
    onError: Colors.white,
    errorContainer: Color(0xFF7A2418),
    onErrorContainer: Color(0xFFF7DAD4),
    surface: creamDark,
    onSurface: inkDark,
    surfaceDim: mistDark,
    surfaceBright: Color(0xFF323A31),
    surfaceContainerLowest: Color(0xFF0C110C),
    surfaceContainerLow: mistDark,
    surfaceContainer: raisedDark,
    surfaceContainerHigh: Color(0xFF262E26),
    surfaceContainerHighest: Color(0xFF313930),
    onSurfaceVariant: mutedDark,
    outline: Color(0xFF8C9389),
    outlineVariant: hairlineDark,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: creamPaper,
    onInverseSurface: sage900,
    inversePrimary: sage600,
  );

  static ThemeData get light => _build(_lightScheme, FishersColors.light);

  static ThemeData get dark => _build(_darkScheme, FishersColors.dark);

  static ThemeData _build(ColorScheme scheme, FishersColors colors) {
    final bool isDark = scheme.brightness == Brightness.dark;
    final TextTheme text = _textTheme(scheme);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // The page, not the card: iOS paints its grouped background in the club's
      // cream, and a Scaffold that stayed on `surface` would leave every screen
      // a shade too bright to see the cards on.
      scaffoldBackgroundColor: colors.mist,
      canvasColor: colors.mist,
      textTheme: text,
      dividerTheme: DividerThemeData(color: colors.hairline, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.mist,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.mist,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark ? sage800 : sagePale,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(text.labelMedium!),
      ),
      cardTheme: CardThemeData(
        color: colors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(corner),
          side: BorderSide(color: colors.hairline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.raised,
        side: BorderSide(color: colors.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(corner - 4)),
      ),
      listTileTheme: ListTileThemeData(tileColor: colors.cream, minVerticalPadding: space1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.raised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(corner),
          borderSide: BorderSide(color: colors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(corner),
          borderSide: BorderSide(color: colors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(corner),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, minTap),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(corner)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, minTap),
          side: BorderSide(color: colors.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(corner)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(0, minTap)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
    );
  }

  /// Type. The iOS app leans on three SF designs — SF Rounded for the wordmark
  /// and figures, New York for fixture titles, SF Text for chrome. Android has
  /// no equivalent trio in the system font, so the weights and the roles carry
  /// the distinction instead, on Material's own type scale. Sizes are left at
  /// Material's defaults so Android's font-size setting scales them.
  static TextTheme _textTheme(ColorScheme scheme) {
    final TextTheme base = Typography.material2021(
      colorScheme: scheme,
    ).let(scheme.brightness == Brightness.dark);
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w800),
      displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w800),
      displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
  }

  /// The wordmark, the one place the app shouts its own name.
  static TextStyle brand(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall!.copyWith(fontWeight: FontWeight.w900);

  static TextStyle brandInline(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w900);

  /// A fixture title. Serif on iOS (New York); here it is the one style that
  /// leaves the sans-serif chrome behind.
  static TextStyle contentTitle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600, fontFamily: 'serif', height: 1.25);

  /// A score, an average, a shirt number. Tabular figures so a column does not
  /// jitter as the number changes — the Dart equivalent of `.monospacedDigit()`.
  static TextStyle figure(BuildContext context, {TextStyle? from}) {
    final TextStyle base = from ?? Theme.of(context).textTheme.headlineSmall!;
    return base.copyWith(
      fontWeight: FontWeight.bold,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  /// A short all-caps label. Short only — long all-caps runs are hard to read.
  static TextStyle overline(BuildContext context) => Theme.of(context).textTheme.labelSmall!
      .copyWith(letterSpacing: 0.8, color: Theme.of(context).colorScheme.onSurfaceVariant);
}

/// The palette entries Material's [ColorScheme] has no slot for.
///
/// On iOS these are `Color(light:dark:)` values read straight off
/// `FishersTheme`; here they are resolved once per brightness and handed to
/// widgets through the theme, so a widget never has to ask which mode it is in.
@immutable
class FishersColors extends ThemeExtension<FishersColors> {
  const FishersColors({
    required this.mist,
    required this.cream,
    required this.raised,
    required this.hairline,
    required this.accent,
    required this.pitch,
    required this.available,
    required this.maybe,
    required this.unavailable,
    required this.seam,
    required this.four,
    required this.six,
    required this.ink,
    required this.muted,
  });

  /// The page.
  final Color mist;

  /// A card on it.
  final Color cream;

  /// One step raised from a card.
  final Color raised;
  final Color hairline;
  final Color accent;
  final Color pitch;
  final Color available;
  final Color maybe;
  final Color unavailable;
  final Color seam;
  final Color four;
  final Color six;
  final Color ink;
  final Color muted;

  static const FishersColors light = FishersColors(
    mist: FishersTheme.mistLight,
    cream: FishersTheme.creamLight,
    raised: FishersTheme.raisedLight,
    hairline: FishersTheme.hairlineLight,
    accent: FishersTheme.accentLight,
    pitch: FishersTheme.pitchLight,
    available: FishersTheme.availableLight,
    maybe: FishersTheme.maybeLight,
    unavailable: FishersTheme.unavailableLight,
    seam: FishersTheme.seam,
    four: FishersTheme.four,
    six: FishersTheme.six,
    ink: FishersTheme.inkLight,
    muted: FishersTheme.mutedLight,
  );

  static const FishersColors dark = FishersColors(
    mist: FishersTheme.mistDark,
    cream: FishersTheme.creamDark,
    raised: FishersTheme.raisedDark,
    hairline: FishersTheme.hairlineDark,
    accent: FishersTheme.accentDark,
    pitch: FishersTheme.pitchDark,
    available: FishersTheme.availableDark,
    maybe: FishersTheme.maybeDark,
    unavailable: FishersTheme.unavailableDark,
    seam: FishersTheme.seam,
    four: FishersTheme.four,
    six: FishersTheme.six,
    ink: FishersTheme.inkDark,
    muted: FishersTheme.mutedDark,
  );

  /// `FishersColors.of(context).available` — the call site a widget makes.
  static FishersColors of(BuildContext context) =>
      Theme.of(context).extension<FishersColors>() ?? light;

  @override
  FishersColors copyWith({
    Color? mist,
    Color? cream,
    Color? raised,
    Color? hairline,
    Color? accent,
    Color? pitch,
    Color? available,
    Color? maybe,
    Color? unavailable,
    Color? seam,
    Color? four,
    Color? six,
    Color? ink,
    Color? muted,
  }) {
    return FishersColors(
      mist: mist ?? this.mist,
      cream: cream ?? this.cream,
      raised: raised ?? this.raised,
      hairline: hairline ?? this.hairline,
      accent: accent ?? this.accent,
      pitch: pitch ?? this.pitch,
      available: available ?? this.available,
      maybe: maybe ?? this.maybe,
      unavailable: unavailable ?? this.unavailable,
      seam: seam ?? this.seam,
      four: four ?? this.four,
      six: six ?? this.six,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
    );
  }

  @override
  FishersColors lerp(ThemeExtension<FishersColors>? other, double t) {
    if (other is! FishersColors) return this;
    return FishersColors(
      mist: Color.lerp(mist, other.mist, t)!,
      cream: Color.lerp(cream, other.cream, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      pitch: Color.lerp(pitch, other.pitch, t)!,
      available: Color.lerp(available, other.available, t)!,
      maybe: Color.lerp(maybe, other.maybe, t)!,
      unavailable: Color.lerp(unavailable, other.unavailable, t)!,
      seam: Color.lerp(seam, other.seam, t)!,
      four: Color.lerp(four, other.four, t)!,
      six: Color.lerp(six, other.six, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension on Typography {
  TextTheme let(bool isDark) => isDark ? white : black;
}
