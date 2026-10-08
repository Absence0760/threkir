package com.runapp.watchwear.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Typography
import com.runapp.watchwear.R

/// Design tokens mirroring the dark half of
/// `packages/ui_kit/lib/src/theme/app_theme.dart` ("Dusk, refined",
/// decisions § 1768) and `apps/watch_ios/WatchApp/AppTheme.swift`. Keep hex
/// values in sync with those files — every platform's colour palette is one
/// thing with three language bindings. The watch is dark-only.
object DuskPalette {
    val night = Color(0xFF121117)
    val nightRaised = Color(0xFF1C1A24)
    val nightHigh = Color(0xFF24212E)
    val coral = Color(0xFFF08A5D)
    val coralDeep = Color(0xFFC24E24)
    val onCoral = Color(0xFF1A0E08)
    val lilac = Color(0xFFB9A7E8)
    val mist = Color(0xFFF3F1F7)
    val mistMuted = Color(0xFFA9A4B6)
    val error = Color(0xFFD8594C)
    val success = Color(0xFF66BB6A)
    val warning = Color(0xFFE0A44D)
}

/// The wordmark's gradient — deep coral through rose to violet (decisions
/// § 1769) — mirroring `--brand-coral` / `--brand-rose` / `--brand-violet` in
/// `apps/web/src/app.css`. Kept apart from `DuskPalette` on purpose: Dusk is
/// the shared UI palette, this is the brand mark, and it is spent on exactly
/// one control — the pre-run Start.
///
/// Ink is white, as on web: 4.76:1 on the coral end, higher on the rest.
object BrandPalette {
    val coral = Color(0xFFC24E24)
    val rose = Color(0xFFA8426A)
    val violet = Color(0xFF5B4B8A)
    val onBrand = Color(0xFFFFFFFF)
    val ramp: Brush = Brush.horizontalGradient(listOf(coral, rose, violet))
}

/// Wear Compose Material colour slots mapped onto the Dusk palette.
///
/// Primary = coral (warm, the "action" colour — selected and confirm chips;
/// the pre-run Start wears `BrandPalette` instead).
/// Secondary = lilac (softer accent, used for informational chips).
/// Background / surface = night / nightRaised for depth layering.
/// Error = the shared brand red (not Material's stock red).
private val DuskColors = Colors(
    primary = DuskPalette.coral,
    primaryVariant = DuskPalette.coralDeep,
    secondary = DuskPalette.lilac,
    secondaryVariant = DuskPalette.nightHigh,
    background = DuskPalette.night,
    surface = DuskPalette.nightRaised,
    error = DuskPalette.error,
    onPrimary = DuskPalette.onCoral,
    onSecondary = DuskPalette.onCoral,
    onBackground = DuskPalette.mist,
    onSurface = DuskPalette.mist,
    onSurfaceVariant = DuskPalette.mistMuted,
    onError = DuskPalette.mist,
)

/// Manrope, the product face (decisions § 1768), bundled as font resources
/// by `assets/fonts/gen-manrope.py` (SIL OFL 1.1, `assets/licenses/`).
private val Manrope = FontFamily(
    Font(R.font.manrope_light, FontWeight.Light),
    Font(R.font.manrope_regular, FontWeight.Normal),
    Font(R.font.manrope_medium, FontWeight.Medium),
    Font(R.font.manrope_semibold, FontWeight.SemiBold),
    Font(R.font.manrope_bold, FontWeight.Bold),
    Font(R.font.manrope_extrabold, FontWeight.ExtraBold),
)

/// Tighter numeric-heavy typography for a watch face.
private val DuskTypography = Typography(
    defaultFontFamily = Manrope,
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
