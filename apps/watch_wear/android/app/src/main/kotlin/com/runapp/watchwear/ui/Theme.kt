package com.runapp.watchwear.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Typography

/// Design tokens mirroring `packages/ui_kit/lib/src/theme/app_theme.dart`
/// and `apps/watch_ios/WatchApp/AppTheme.swift`. Keep hex values in sync
/// with those files — every platform's colour palette is one thing with
/// three language bindings.
object DuskPalette {
    val dusk = Color(0xFF3A2E5C)
    val duskDeep = Color(0xFF241B3D)
    val midnight = Color(0xFF120D22)
    val coral = Color(0xFFF2A07B)
    val coralDeep = Color(0xFFD97A54)
    val lilac = Color(0xFFB9A7E8)
    val parchment = Color(0xFFF7F3EC)
    val parchmentDim = Color(0xFFEBE5D8)
    val ink = Color(0xFF1B1628)
    val haze = Color(0xFF6B6380)
    val error = Color(0xFFD8594C)
    val success = Color(0xFF66BB6A)
    val warning = Color(0xFFE0A44D)
}

/// The wordmark's two ends — the launcher icon's ember-to-magenta ramp —
/// mirroring `--brand-ember` / `--brand-magenta` in `apps/web/src/app.css`.
/// Kept apart from `DuskPalette` on purpose: Dusk is the shared UI palette
/// (`primary` stays coral so every other screen is unchanged), this is the
/// brand mark, and it is spent on exactly one control — the pre-run Start.
///
/// Ink is white, as on web. White on the ember end alone is 3.1:1, so the
/// ramp runs ember -> magenta across the button and the label sits over its
/// middle (~4.7:1) at a large, semibold size.
object BrandPalette {
    val ember = Color(0xFFFE5932)
    val magenta = Color(0xFFA01E77)
    val onBrand = Color(0xFFFFFFFF)
    val ramp: Brush = Brush.horizontalGradient(listOf(ember, magenta))
}

/// Wear Compose Material colour slots mapped onto the Dusk palette.
///
/// Primary = coral (warm, the "action" colour — selected and confirm chips;
/// the pre-run Start wears `BrandPalette` instead).
/// Secondary = lilac (softer accent, used for informational chips).
/// Background / surface = midnight / duskDeep for depth layering.
/// Error = the shared brand red (not Material's stock red).
private val DuskColors = Colors(
    primary = DuskPalette.coral,
    primaryVariant = DuskPalette.coralDeep,
    secondary = DuskPalette.lilac,
    secondaryVariant = DuskPalette.dusk,
    background = DuskPalette.midnight,
    surface = DuskPalette.duskDeep,
    error = DuskPalette.error,
    onPrimary = DuskPalette.ink,
    onSecondary = DuskPalette.ink,
    onBackground = DuskPalette.parchment,
    onSurface = DuskPalette.parchment,
    onSurfaceVariant = DuskPalette.haze,
    onError = DuskPalette.parchment,
)

/// Tighter numeric-heavy typography for a watch face. Tabular figures
/// would be ideal (stop digits jittering as seconds tick) but Android's
/// default sans doesn't expose them without a font file. Using Default
/// SansSerif and relying on the close-to-fixed-width rendering of
/// Google's Wear OS system font.
private val DuskTypography = Typography(
    defaultFontFamily = FontFamily.SansSerif,
    display1 = androidx.compose.ui.text.TextStyle(
        fontSize = 40.sp,
        fontWeight = FontWeight.Light,
        letterSpacing = (-0.5).sp,
    ),
    display2 = androidx.compose.ui.text.TextStyle(
        fontSize = 32.sp,
        fontWeight = FontWeight.Normal,
    ),
    display3 = androidx.compose.ui.text.TextStyle(
        fontSize = 26.sp,
        fontWeight = FontWeight.Normal,
    ),
    title1 = androidx.compose.ui.text.TextStyle(
        fontSize = 18.sp,
        fontWeight = FontWeight.SemiBold,
    ),
    title2 = androidx.compose.ui.text.TextStyle(
        fontSize = 20.sp,
        fontWeight = FontWeight.Medium,
    ),
    title3 = androidx.compose.ui.text.TextStyle(
        fontSize = 16.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.15.sp,
    ),
)

@Composable
fun DuskTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = DuskColors,
        typography = DuskTypography,
        content = content,
    )
}
