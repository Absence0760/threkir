// Debug-build-only tool for the timing-line calibration session (#1304 § 6),
// the watch's twin of the phone's Settings > Line calibration. Reached only
// from the pre-run list behind `BuildConfig.DEBUG`. Its copy is English on
// purpose, as the phone's is: no runner ever sees it.

package com.runapp.watchwear.ui

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.AutoCenteringParams
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.runapp.watchwear.CalibrationApproach
import com.runapp.watchwear.CalibrationCell
import com.runapp.watchwear.CalibrationClock
import com.runapp.watchwear.CalibrationPace
import com.runapp.watchwear.CalibrationResult
import com.runapp.watchwear.GATE_HALF_WIDTH_RACE_M
import com.runapp.watchwear.Gate
import com.runapp.watchwear.GpsPoint
import com.runapp.watchwear.LineCalibrationCapture
import com.runapp.watchwear.RaceSessionClient
import com.runapp.watchwear.analyseCalibration
import com.runapp.watchwear.calibrationCsv
import com.runapp.watchwear.gateUsable
import com.runapp.watchwear.parseCalibrationInstants
import com.runapp.watchwear.writeCalibrationCsv
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.launch

/// Round trips per clock measurement; the shortest wins.
private const val CLOCK_SAMPLES = 10

private fun typedDecimal(text: String): Double? =
    text.trim().replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() }

@Composable
internal fun LineCalibrationScreen(
    capture: LineCalibrationCapture,
    sampleServerClock: suspend () -> RaceSessionClient.ClockSample?,
    lastPosition: suspend () -> GpsPoint?,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()
    var lat by remember { mutableStateOf("") }
    var lng by remember { mutableStateOf("") }
    var bearing by remember { mutableStateOf("") }
    var halfWidth by remember { mutableStateOf(GATE_HALF_WIDTH_RACE_M.toInt().toString()) }
    var offset by remember { mutableStateOf("") }
    var measuredText by remember { mutableStateOf<String?>(null) }
    var measuredRttMs by remember { mutableStateOf<Long?>(null) }
    var instants by remember { mutableStateOf("") }
    var approach by remember { mutableStateOf(CalibrationApproach.DEG90) }
    var pace by remember { mutableStateOf(CalibrationPace.RUN) }
    var problem by remember { mutableStateOf<String?>(null) }
    var saved by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    val results = remember { mutableStateListOf<CalibrationResult>() }

    fun score() {
        val la = typedDecimal(lat)
        val ln = typedDecimal(lng)
        val br = typedDecimal(bearing)
        val hw = typedDecimal(halfWidth)
        val off = offset.trim().toLongOrNull()
        val zone = ZoneId.systemDefault()
        val day = capture.firstFixMs?.let { Instant.ofEpochMilli(it.toLong()).atZone(zone).toLocalDate() }
            ?: LocalDate.now(zone)
        val truth = parseCalibrationInstants(instants, day, zone)
        problem = when {
            la == null || ln == null || br == null || hw == null ->
                "Enter the line: centre, bearing of travel, half-width."
            off == null -> "Measure or enter the clock offset."
            truth == null -> "Instants: HH:MM:SS.fff or ISO-8601, comma between."
            capture.fixCount < 2 -> "The capture holds fewer than two fixes."
            else -> null
        }
        if (problem != null) return
        val gate = Gate(la!!, ln!!, br!!, hw!!)
        if (!gateUsable(gate)) {
            problem = "That line is not usable."
            return
        }
        results.add(
            analyseCalibration(
                cell = CalibrationCell(approach, pace),
                recordings = capture.recordings,
                gate = gate,
                trueCrossingsMs = truth!!,
                clockOffsetMs = off!!,
                offsetRttMs = if (offset == measuredText) measuredRttMs else null,
            ),
        )
        instants = ""
    }

    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        autoCentering = AutoCenteringParams(itemIndex = 0),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 24.dp),
    ) {
        item {
            Text("Line calibration (debug)", style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
        }
        item {
            Text(
                "Start a capture, record a run through the line, stop the capture, then type " +
                    "the video-timed crossing instants. The CSV holds figures only.",
                style = MaterialTheme.typography.caption3,
                color = DuskPalette.mistMuted,
                textAlign = TextAlign.Center,
            )
        }
        item {
            val held = if (tick >= 0) capture.fixCount else 0
            Text(
                if (capture.active) "Capturing: $held fixes" else "Idle: $held fixes held",
                style = MaterialTheme.typography.caption1,
            )
        }
        item {
            Chip(
                onClick = {
                    if (capture.active) capture.stop() else capture.start()
                    tick++
                },
                label = { Text(if (capture.active) "Stop capture" else "Start capture") },
                colors = ChipDefaults.primaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            Chip(
                onClick = { tick++ },
                label = { Text("Refresh") },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            InlineTextField(lat, { lat = it }, "Line centre latitude", KeyboardType.Decimal, ImeAction.Done)
        }
        item {
            InlineTextField(lng, { lng = it }, "Line centre longitude", KeyboardType.Decimal, ImeAction.Done)
        }
        item {
            Chip(
                onClick = {
                    scope.launch {
                        val p = lastPosition()
                        if (p == null) {
                            problem = "No position fix."
                        } else {
                            lat = "%.7f".format(java.util.Locale.ROOT, p.lat)
                            lng = "%.7f".format(java.util.Locale.ROOT, p.lng)
                        }
                    }
                },
                label = { Text("Centre at my position") },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            InlineTextField(bearing, { bearing = it }, "Bearing of travel, deg", KeyboardType.Decimal, ImeAction.Done)
        }
        item {
            InlineTextField(halfWidth, { halfWidth = it }, "Half-width, m", KeyboardType.Decimal, ImeAction.Done)
        }
        item {
            Chip(
                onClick = {
                    scope.launch {
                        val clock = CalibrationClock()
                        repeat(CLOCK_SAMPLES) {
                            sampleServerClock()?.let { clock.addSample(it.sentAtMs, it.receivedAtMs, it.serverAtMs) }
                        }
                        val o = clock.offsetMs
                        val rtt = clock.rttMs
                        if (o == null || rtt == null) {
                            problem = "Could not reach the server clock; enter the offset by hand."
                        } else {
                            offset = o.toString()
                            measuredText = offset
                            measuredRttMs = rtt
                            problem = null
                        }
                    }
                },
                label = { Text("Measure server clock") },
                secondaryLabel = { Text("$CLOCK_SAMPLES round trips") },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            InlineTextField(offset, { offset = it }, "Clock offset, ms (server minus device)", KeyboardType.Number, ImeAction.Done)
        }
        item {
            Chip(
                onClick = {
                    val all = CalibrationApproach.values()
                    approach = all[(approach.ordinal + 1) % all.size]
                },
                label = { Text("Approach") },
                secondaryLabel = { Text(approach.wire) },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            Chip(
                onClick = {
                    val all = CalibrationPace.values()
                    pace = all[(pace.ordinal + 1) % all.size]
                },
                label = { Text("Pace") },
                secondaryLabel = { Text(pace.wire) },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            InlineTextField(instants, { instants = it }, "True crossing instants", KeyboardType.Text, ImeAction.Done)
        }
        problem?.let { p ->
            item {
                Text(p, style = MaterialTheme.typography.caption2, color = DuskPalette.error, textAlign = TextAlign.Center)
            }
        }
        item {
            Chip(
                onClick = { score() },
                label = { Text("Score this capture") },
                colors = ChipDefaults.primaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        for (r in results) {
            item {
                Text(
                    "${r.cell.approach.wire} / ${r.cell.pace.wire}: ${r.matched} of ${r.trueCount} matched, " +
                        "${r.missed} missed, ${r.falseCrossings} false, ${r.nearMisses} near; " +
                        "median ${r.medianErrorMs ?: "-"} ms, |err| p50 ${r.medianAbsErrorMs ?: "-"} ms, " +
                        "p95 ${r.p95AbsErrorMs ?: "-"} ms; offset ±${r.offsetRttMs?.let { it / 2 } ?: "?"} ms" +
                        if (r.matched == 0 && r.nearestDiffMs != null) {
                            ". Nothing matched, yet detections sit a median ${r.nearestDiffMs} ms " +
                                "from the truths: check the clock, offset and time zone"
                        } else {
                            ""
                        },
                    style = MaterialTheme.typography.caption3,
                )
            }
        }
        if (results.isNotEmpty()) {
            item {
                Chip(
                    onClick = {
                        saved = try {
                            writeCalibrationCsv(context.filesDir, calibrationCsv(results.toList())).name
                        } catch (e: Exception) {
                            android.util.Log.w("LineCalibration", "CSV not written", e)
                            null
                        }
                        if (saved == null) problem = "The CSV could not be written."
                    },
                    label = { Text("Save CSV") },
                    secondaryLabel = if (saved != null) {
                        { Text("files/$saved") }
                    } else {
                        null
                    },
                    colors = ChipDefaults.primaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        item {
            Chip(
                onClick = onClose,
                label = { Text("Close") },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
