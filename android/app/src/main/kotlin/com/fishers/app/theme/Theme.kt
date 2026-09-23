package com.fishers.app.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/**
 * The palette, from `ios/Fishers/Theme/`. One product, one set of colours: a
 * club that uses both phones should not see two different greens.
 */
private val Ink = Color(0xFF0B1220)
private val Surface = Color(0xFFFFFFFF)
private val SurfaceDark = Color(0xFF121A2B)
private val Primary = Color(0xFF1B7F4B)
private val PrimaryDark = Color(0xFF4ECB84)
private val Danger = Color(0xFFB3261E)
private val DangerDark = Color(0xFFF2B8B5)

private val LightScheme = lightColorScheme(
    primary = Primary,
    onPrimary = Color.White,
    background = Color(0xFFF7F9FC),
    onBackground = Ink,
    surface = Surface,
    onSurface = Ink,
    error = Danger,
)

private val DarkScheme = darkColorScheme(
    primary = PrimaryDark,
    onPrimary = Ink,
    background = Ink,
    onBackground = Color(0xFFE6EDF7),
    surface = SurfaceDark,
    onSurface = Color(0xFFE6EDF7),
    error = DangerDark,
)

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
        darkTheme -> DarkScheme
        else -> LightScheme
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
