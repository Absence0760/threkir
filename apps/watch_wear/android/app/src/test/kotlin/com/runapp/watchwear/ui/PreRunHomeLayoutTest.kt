package com.runapp.watchwear.ui

import com.runapp.watchwear.KotlinSources
import com.runapp.watchwear.WearLocales
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard over the pre-run home layout: one brand Start pinned to
/// the bottom bezel, a scrolling list of label-plus-value setting chips above
/// it, and account actions inside that list rather than floating on the face.
///
/// Compose layout is not host-JVM testable here (no Robolectric, by module
/// convention), so this pins the structure the design rests on. Each
/// assertion names the regression it exists to refuse — Start drifting back
/// into the list where overflow can push it off-frame, a chip that names a
/// setting without its value, sign-out becoming unreachable, a colour literal
/// replacing a theme token.
class PreRunHomeLayoutTest {

    private val ui: String = File(KotlinSources.mainRoot(), "com/runapp/watchwear/ui/RunWatchApp.kt").readText()
    private val edge: String = File(KotlinSources.mainRoot(), "com/runapp/watchwear/ui/BrandEdgeButton.kt").readText()
    private val theme: String = File(KotlinSources.mainRoot(), "com/runapp/watchwear/ui/Theme.kt").readText()

    /// PreRunScreen's own text, signature to the next top-level `private fun`.
    private fun preRun(): String {
        val start = ui.indexOf("private fun PreRunScreen(")
        assertTrue("PreRunScreen is gone or renamed — this guard reads nothing", start >= 0)
        val end = ui.indexOf("\nprivate fun ", start + 1)
        assertTrue("could not find the end of PreRunScreen", end > start)
        return ui.substring(start, end)
    }

    /// The home list's content lambda, brace-matched on a view where braces in
    /// strings and comments do not count.
    private fun listContent(body: String): String {
        val structure = KotlinSources.structureView(body)
        val call = structure.indexOf("ScalingLazyColumn(")
        assertTrue("the pre-run home is no longer a ScalingLazyColumn", call >= 0)
        var depth = 0
        var i = structure.indexOf('(', call)
        while (i < structure.length) {
            when (structure[i]) {
                '(' -> depth++
                ')' -> { depth--; if (depth == 0) break }
            }
            i++
        }
        val open = structure.indexOf('{', i)
        val close = KotlinSources.blockEnd(structure, open)
        assertTrue("could not brace-match the list's content lambda", open > i && close > open)
        return body.substring(open, close + 1)
    }

    @Test
    fun `Start is pinned to the bottom edge and is not a list item`() {
        val body = preRun()
        val list = listContent(body)
        assertTrue(
            "Start must not live inside the scrolling list — status text stacking up " +
                "above it would scroll it off-frame, the bug the old anchored Box fixed",
            !list.contains("onStart"),
        )
        assertEquals(
            "onStart must be bound exactly once on the home screen",
            1,
            Regex("""onClick\s*=\s*onStart\b""").findAll(body).count(),
        )
        val start = body.indexOf("BrandEdgeButton(")
        assertTrue("the home screen's primary action is no longer the brand edge button", start >= 0)
        val call = body.substring(start, body.indexOf("\n        )", start))
        assertTrue("the edge button must fire onStart", call.contains("onClick = onStart"))
        assertTrue(
            "the edge button must hug the bottom bezel — its shape assumes its bottom " +
                "edge is the screen's",
            call.contains(".align(Alignment.BottomCenter)"),
        )
        assertTrue(
            "the list must reserve the edge button's MEASURED height, or its last item " +
                "(Sign out) scrolls to a resting place underneath Start",
            call.contains(".onSizeChanged") && body.contains("bottom = startHeight"),
        )
    }

    @Test
    fun `every setting chip states its current value`() {
        val list = listContent(preRun())
        assertEquals(
            "Activity, Pace and Route each render as a label-plus-value chip",
            3,
            Regex("""PreRunSettingChip\(""").findAll(list).count(),
        )
        assertTrue("Activity must show the current activity", list.contains("value = label") && list.contains("activityLabel(activityType)"))
        assertTrue("Pace must say Off rather than go blank", list.contains("R.string.pace_off"))
        assertTrue("Pace must carry its unit", list.contains("R.string.pace_per_km"))
        assertTrue("Route must say None rather than go blank", list.contains("R.string.route_none"))
        assertTrue("Route must show the selected route's name", list.contains("selectedRouteName"))
        val chip = ui.substring(ui.indexOf("private fun PreRunSettingChip("))
        assertTrue(
            "the value is the secondary label of a full chip, not a second control",
            chip.contains("secondaryLabel = {"),
        )
        assertTrue(
            "the chip's spoken description must be set, or TalkBack reads label and " +
                "value with no action",
            chip.contains("this.contentDescription = contentDescription"),
        )
    }

    @Test
    fun `account actions are reachable from the list and nowhere else on the face`() {
        val body = preRun()
        val list = listContent(body)
        assertTrue(
            "Sign out must be a labelled chip in the list",
            Regex("""Chip\([\s\S]{0,40}onClick = onSignOut[\s\S]{0,200}R\.string\.sign_out""").containsMatchIn(list),
        )
        assertEquals(
            "Sign out must have exactly one entry point on the home screen",
            1,
            Regex("""onClick\s*=\s*onSignOut\b""").findAll(body).count(),
        )
        assertTrue("the old unlabelled corner icon button is back", !body.contains("CompactButton("))
        val signedOut = list.indexOf("if (!authed) {")
        assertTrue("the list must branch on a signed-out watch", signedOut >= 0)
        assertTrue(
            "a signed-out watch must be offered Sign in — without it a standalone LTE " +
                "watch has no way to authenticate at all",
            Regex("""item\(key = "sign-in"\)[\s\S]{0,200}onClick = onSignIn""")
                .containsMatchIn(list.substring(signedOut)),
        )
    }

    @Test
    fun `the battery remediation is a labelled control, not a bare glyph`() {
        val list = listContent(preRun())
        assertTrue(
            "the battery-optimisation fix must be in the list and carry its words",
            Regex("""if \(batteryOptimised\)[\s\S]{0,600}onClick = onFixBattery[\s\S]{0,300}R\.string\.battery_allow_background""")
                .containsMatchIn(list),
        )
        assertTrue(
            "the unlabelled \"!\" glyph is back",
            !KotlinSources.codeView(list).contains("\"!\""),
        )
    }

    @Test
    fun `the home screen paints from tokens, never literals`() {
        val literal = Regex("""Color\(0x|Color\.(?:White|Black|Red|Gray)\b""")
        val body = KotlinSources.codeView(preRun())
        assertTrue(
            "PreRunScreen paints a colour literal — use MaterialTheme.colors, DuskPalette " +
                "or BrandPalette: ${literal.find(body)?.value}",
            !literal.containsMatchIn(body),
        )
        assertTrue(
            "BrandEdgeButton paints a colour literal — the ramp and its ink are BrandPalette tokens",
            !literal.containsMatchIn(KotlinSources.codeView(edge)),
        )
        assertTrue("the edge button must fill with the brand ramp", edge.contains("background(BrandPalette.ramp)"))
        assertTrue("the edge button's ink must be the brand's", edge.contains("color = BrandPalette.onBrand"))
    }

    @Test
    fun `the brand ramp is the web wordmark's, byte for byte`() {
        val css = WearLocales.findUp("apps/web/src/app.css")
        assertNotNull("could not locate apps/web/src/app.css", css)
        val cssText = css!!.readText()
        for ((token, kotlin) in listOf("--brand-ember" to "ember", "--brand-magenta" to "magenta")) {
            val web = Regex("""${Regex.escape(token)}:\s*#([0-9A-Fa-f]{6});""").find(cssText)
                ?.groupValues?.get(1)?.uppercase()
            assertNotNull("app.css no longer declares $token", web)
            val wear = Regex("""val $kotlin = Color\(0xFF([0-9A-Fa-f]{6})\)""").find(theme)
                ?.groupValues?.get(1)?.uppercase()
            assertEquals("BrandPalette.$kotlin drifted from web's $token", web, wear)
        }
    }

    @Test
    fun `the edge button clears the minimum touch target`() {
        val dp = Regex("""val MinHeight: Dp = (\d+)\.dp""").find(edge)?.groupValues?.get(1)?.toInt()
        assertNotNull("BrandEdgeButtonDefaults.MinHeight is gone", dp)
        assertTrue("the edge button must be at least 48 dp tall, is $dp", dp!! >= 48)
        assertTrue(
            "the edge button must announce itself as a button",
            edge.contains("clickable(role = Role.Button"),
        )
    }
}
