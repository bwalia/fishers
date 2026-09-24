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

@Composable
private fun brandScheme(dark: Boolean): ColorScheme {
    val primary = colorResource(R.color.brand_primary_600)
    val primaryDeep = colorResource(R.color.brand_primary_900)
    val accent = colorResource(R.color.brand_accent_600)
    val surface = colorResource(R.color.brand_source_surface)
    val raised = colorResource(R.color.brand_source_primary_pale)
    val ink = colorResource(R.color.brand_ink_900)

    return if (dark) {
        darkColorScheme(
            primary = colorResource(R.color.brand_source_primary),
            onPrimary = primaryDeep,
            secondary = accent,
            background = primaryDeep,
            onBackground = surface,
            surface = primaryDeep,
            onSurface = surface,
            surfaceVariant = colorResource(R.color.brand_primary_700),
            error = DangerDark,
        )
    } else {
        lightColorScheme(
            primary = primary,
            onPrimary = Color.White,
            secondary = accent,
            background = surface,
            onBackground = ink,
            surface = Color.White,
            onSurface = ink,
            surfaceVariant = raised,
            error = Danger,
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
