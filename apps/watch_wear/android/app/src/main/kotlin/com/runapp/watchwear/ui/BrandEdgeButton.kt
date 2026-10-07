package com.runapp.watchwear.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text

/// The screen's one primary action, hugging the bottom bezel.
///
/// Wear Compose Material 3 ships this as `EdgeButton`; this module is on Wear
/// Compose Material 1.x, which has no equivalent, so this is the same shape
/// built from foundation: a rounded top, and a bottom that IS the display's
/// own circle, so the fill runs into the bezel instead of floating above it.
/// On a square display the bottom is simply flat.
///
/// Callers anchor it with `Alignment.BottomCenter` and nothing below it — the
/// shape assumes its bottom edge is the screen's.
@Composable
fun BrandEdgeButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val config = LocalConfiguration.current
    val screenRadius = config.screenWidthDp.dp / 2
    val shape = EdgeButtonShape(screenRadius = screenRadius, round = config.isScreenRound)
    Box(
        modifier = modifier
            .fillMaxWidth(BrandEdgeButtonDefaults.WidthFraction)
            .heightIn(min = BrandEdgeButtonDefaults.MinHeight)
            .clip(shape)
            .background(BrandPalette.ramp)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.title2.copy(fontWeight = FontWeight.SemiBold),
            color = BrandPalette.onBrand,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            // The bezel arc eats the lower corners, so the visible face of the
            // button sits higher than its box — bias the label up to match.
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 14.dp),
        )
    }
}

object BrandEdgeButtonDefaults {
    val MinHeight: Dp = 56.dp
    const val WidthFraction: Float = 0.7f
}

/// Rounded top corners intersected with the display circle. The circle's
/// centre is placed `screenRadius` above the shape's bottom edge, which is
/// exactly where it is when the shape sits flush on the bottom of the screen.
private class EdgeButtonShape(
    private val screenRadius: Dp,
    private val round: Boolean,
) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val top = size.height / 2f
        val body = Path().apply {
            addRoundRect(
                RoundRect(
                    rect = Rect(0f, 0f, size.width, size.height),
                    topLeft = CornerRadius(top, top),
                    topRight = CornerRadius(top, top),
                    bottomRight = CornerRadius(if (round) 0f else top / 2f),
                    bottomLeft = CornerRadius(if (round) 0f else top / 2f),
                )
            )
        }
        if (!round) return Outline.Generic(body)
        val r = with(density) { screenRadius.toPx() }
        val cx = size.width / 2f
        val cy = size.height - r
        val bezel = Path().apply { addOval(Rect(cx - r, cy - r, cx + r, cy + r)) }
        return Outline.Generic(Path.combine(PathOperation.Intersect, body, bezel))
    }

    override fun equals(other: Any?): Boolean =
        other is EdgeButtonShape && other.screenRadius == screenRadius && other.round == round

    override fun hashCode(): Int = 31 * screenRadius.hashCode() + round.hashCode()
}
