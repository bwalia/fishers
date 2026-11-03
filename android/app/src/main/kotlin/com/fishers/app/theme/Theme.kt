package com.fishers.app.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.fishers.app.R

/**
 * The palette comes from the brand.
 *
 * `brand_colors.xml` is written per flavour from `brands/<id>.yaml`, and the
 * ramp in it is darkened until it carries text — the same arithmetic the web
 * does, checked by the same tool. Nothing here picks a colour, which is why a
 * brand is a flavour rather than a fork.
 *
 * Only the danger colour is fixed. A red that varies by brand is a red
 * somebody misses.
 */
private val Danger = Color(0xFFB3261E)
private val DangerDark = Color(0xFFF2B8B5)
private val DangerContainer = Color(0xFFF9DEDC)
private val DangerContainerDark = Color(0xFF8C1D18)
private val OnDangerContainer = Color(0xFF410E0B)

/**
 * The light neutrals, the same literals `web/src/app/globals.css` keeps in
 * `:root` — `--surface-2`, `--surface-3`, `--border`, `--border-strong`. They
 * are shared across brands there rather than generated, so they are shared
 * here too; a phone and a laptop showing the same club should not disagree
 * about what a card edge looks like. Dark has no equivalent list because the
 * brand file carries twelve dark tokens of its own.
 */
private val Surface2 = Color(0xFFF1EFE6)
private val Surface3 = Color(0xFFE6E6DA)
private val BorderLight = Color(0xFFE0DED1)
private val BorderStrongLight = Color(0xFFC9C8B8)

/**
 * Every colour Material 3 draws with, not the eight it was given.
 *
 * `lightColorScheme()` fills anything left out from Material's baseline, which
 * is purple. Eight roles were set and the rest defaulted, so `Card` took
 * `surfaceContainer` and the navigation bar took `surfaceContainer` plus
 * `secondaryContainer` for the selected pill — all lavender, on a cream app.
 * The brand was correct everywhere it had been named and absent everywhere it
 * had not, which is the hardest kind of wrong to notice.
 */
@Composable
private fun brandScheme(dark: Boolean): ColorScheme {
    val primary = colorResource(R.color.brand_primary_600)
    val primaryDeep = colorResource(R.color.brand_primary_900)
    val accent = colorResource(R.color.brand_accent_600)
    val accentLight = colorResource(R.color.brand_accent_400)
    val surface = colorResource(R.color.brand_source_surface)
    val pale = colorResource(R.color.brand_source_primary_pale)
    val ink = colorResource(R.color.brand_ink_900)
    val inkMuted = colorResource(R.color.brand_ink_500)

    return if (dark) {
        val bg = colorResource(R.color.brand_dark_bg)
        val panel = colorResource(R.color.brand_dark_surface)
        val panel2 = colorResource(R.color.brand_dark_surface_2)
        val panel3 = colorResource(R.color.brand_dark_surface_3)
        val fg = colorResource(R.color.brand_dark_fg)
        val fgMuted = colorResource(R.color.brand_dark_fg_muted)
        val border = colorResource(R.color.brand_dark_border)
        val raised = colorResource(R.color.brand_dark_raised)
        darkColorScheme(
            primary = colorResource(R.color.brand_source_primary),
            onPrimary = colorResource(R.color.brand_dark_on_primary),
            primaryContainer = raised,
            onPrimaryContainer = fg,
            secondary = accentLight,
            onSecondary = bg,
            secondaryContainer = colorResource(R.color.brand_dark_accent_pale),
            onSecondaryContainer = fg,
            tertiary = accentLight,
            onTertiary = bg,
            tertiaryContainer = raised,
            onTertiaryContainer = fg,
            background = bg,
            onBackground = fg,
            surface = bg,
            onSurface = fg,
            surfaceVariant = panel2,
            onSurfaceVariant = fgMuted,
            surfaceContainerLowest = bg,
            surfaceContainerLow = panel,
            surfaceContainer = panel,
            surfaceContainerHigh = panel2,
            surfaceContainerHighest = panel3,
            surfaceBright = panel3,
            surfaceDim = bg,
            outline = border,
            outlineVariant = colorResource(R.color.brand_dark_border_strong),
            inverseSurface = fg,
            inverseOnSurface = bg,
            inversePrimary = primary,
            error = DangerDark,
            onError = bg,
            errorContainer = DangerContainerDark,
            onErrorContainer = DangerContainer,
        )
    } else {
        lightColorScheme(
            primary = primary,
            onPrimary = Color.White,
            primaryContainer = pale,
            onPrimaryContainer = primaryDeep,
            secondary = accent,
            onSecondary = Color.White,
            secondaryContainer = pale,
            onSecondaryContainer = primaryDeep,
            tertiary = colorResource(R.color.brand_accent_700),
            onTertiary = Color.White,
            tertiaryContainer = pale,
            onTertiaryContainer = primaryDeep,
            // The page is cream and a card is white — `--bg` and `--surface`
            // on the web, and the same two on iOS.
            background = surface,
            onBackground = ink,
            surface = surface,
            onSurface = ink,
            surfaceVariant = Surface2,
            onSurfaceVariant = inkMuted,
            // All five white, which is not Material's tonal ladder but is what
            // the web does: `.panel` is `--surface: #ffffff` on a `--bg: cream`
            // page, told apart by `--border` rather than by tint. Material runs
            // the ladder the other way in light mode — a filled Card takes
            // `surfaceContainerHighest`, the *darkest* step — so leaving the
            // ladder in place put grey-green cards on cream.
            surfaceContainerLowest = Color.White,
            surfaceContainerLow = Color.White,
            surfaceContainer = Color.White,
            surfaceContainerHigh = Color.White,
            surfaceContainerHighest = Color.White,
            surfaceBright = Color.White,
            surfaceDim = Surface2,
            outline = BorderLight,
            outlineVariant = BorderStrongLight,
            inverseSurface = ink,
            inverseOnSurface = surface,
            inversePrimary = colorResource(R.color.brand_primary_400),
            error = Danger,
            onError = Color.White,
            errorContainer = DangerContainer,
            onErrorContainer = OnDangerContainer,
        )
    }
}

/**
 * `dynamicColor` is off by default. Material You would repaint the app from the
 * user's wallpaper, which is a lovely Android idiom and the wrong one here —
 * the brand is the point, and the iPhone app cannot follow it.
 */
@Composable
fun FishersTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val scheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        else -> brandScheme(dark = darkTheme)
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = scheme.background.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(colorScheme = scheme, content = content)
}
