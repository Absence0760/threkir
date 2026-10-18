package com.runapp.watchwear.complications

import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.recording.RecordingRepository
import com.runapp.watchwear.tiles.PlanKind
import com.runapp.watchwear.tiles.TodayGlance
import com.runapp.watchwear.tiles.formatDistanceLabel
import com.runapp.watchwear.tiles.formatElapsed
import com.runapp.watchwear.tiles.formatPaceSecPerUnit
import java.util.Locale
import kotlinx.serialization.Serializable

/// The five things the watch-face complication can be showing.
internal enum class ComplicationState { RECORDING, PAUSED, TODAY, LAST_RUN, NO_RUN }

/// What the complication shows, decided without any Android type so the
/// choice is pinned on the host JVM. `ActiveRunComplicationService` maps it
/// onto `ComplicationData` per requested type; that mapping is the only part
/// a unit test cannot reach.
///
/// [liveSinceEpochMs] is set only while recording: the elapsed time is then
/// handed to the watch face as a count-up `TimeDifferenceComplicationText`
/// anchored here, so the face ticks it every second on its own and the app
/// never has to push per-second updates. Every other state carries a fixed
/// [elapsed] string.
internal data class RunComplicationContent(
    val state: ComplicationState,
    val distance: String = "",
    val elapsed: String = "",
    val liveSinceEpochMs: Long? = null,
    val detail: String = "",
    /// Set only for [ComplicationState.TODAY]: the planned session's kind.
    val kind: PlanKind? = null,
)

/// The last run this watch recorded, as `LastRunStore` keeps it. The unit is
/// the one the run was recorded in (`Metrics.preferredUnit`), because the
/// watch holds no other copy of the runner's `preferred_unit` between
/// launches — it is fetched from Supabase on each session restore and kept
/// in memory only.
@Serializable
internal data class LastRun(
    val runId: String,
    val distanceM: Double,
    val durationS: Int,
    val unit: String,
    val finishedAtMs: Long,
    /// The plan workout the run followed, when it followed one, so the
    /// "today" glances stop offering a session this watch already ran.
    /// Defaulted: an entry written before the field existed still decodes.
    val planWorkoutId: String? = null,
)

/// Decide the complication's content from what the watch knows locally.
///
/// An active run wins. Otherwise the last run recorded on this watch, and
/// with none, a start prompt. Weekly distance was considered and rejected:
/// the watch keeps no run history — `LocalRunStore` is an upload queue that
/// empties on sync, and runs recorded on the phone never reach the wrist —
/// so any weekly total built here would undercount, silently, by every run
/// not recorded on this watch. There is no weekly goal on the watch either,
/// which is why no RANGED_VALUE type is offered.
internal fun complicationContent(
    metrics: RecordingRepository.Metrics,
    lastRun: LastRun?,
    nowEpochMs: Long,
    locale: Locale = Locale.getDefault(),
): RunComplicationContent {
    when (metrics.stage) {
        RecordingRepository.Stage.Recording -> {
            val unit = metrics.preferredUnit
            val distance = formatDistanceLabel(metrics.distanceM, unit, locale)
            return RunComplicationContent(
                state = ComplicationState.RECORDING,
                distance = distance,
                elapsed = formatElapsed(metrics.elapsedMs),
                liveSinceEpochMs = nowEpochMs - metrics.elapsedMs.coerceAtLeast(0L),
                detail = "$distance · ${formatPaceSecPerUnit(metrics.paceSecPerKm, unit)}",
            )
        }
        RecordingRepository.Stage.Paused -> {
            val distance = formatDistanceLabel(metrics.distanceM, metrics.preferredUnit, locale)
            val elapsed = formatElapsed(metrics.elapsedMs)
            return RunComplicationContent(
                state = ComplicationState.PAUSED,
                distance = distance,
                elapsed = elapsed,
                detail = "$elapsed · $distance",
            )
        }
        else -> Unit
    }
    if (lastRun == null || !lastRun.distanceM.isFinite() || lastRun.distanceM < 0.0) {
        return RunComplicationContent(state = ComplicationState.NO_RUN)
    }
    val distance = formatDistanceLabel(lastRun.distanceM, DistanceUnit.fromPref(lastRun.unit), locale)
    val elapsed = formatElapsed(lastRun.durationS * 1000L)
    return RunComplicationContent(
        state = ComplicationState.LAST_RUN,
        distance = distance,
        elapsed = elapsed,
        detail = "$distance · $elapsed",
    )
}

/// Today's planned workout, for the idle complication. The service serves it
/// as a timeline entry that ends at [TodayGlance.validUntilEpochMs], over the
/// [complicationContent] it would otherwise show, so at midnight the face
/// drops back to the last run on its own and never shows yesterday's session
/// as today's. A live run never gets here: the service asks for this only
/// when no run is active.
internal fun todayComplicationContent(glance: TodayGlance): RunComplicationContent =
    RunComplicationContent(
        state = ComplicationState.TODAY,
        detail = glance.headline,
        kind = glance.kind,
    )

/// The fixed sample the watch-face editor shows before the complication is
/// placed. The platform caches it and expects it constant per locale, so it
/// is a recording state with no live anchor: elapsed renders as plain text.
internal fun previewContent(locale: Locale = Locale.getDefault()): RunComplicationContent {
    val unit = DistanceUnit.KM
    val distance = formatDistanceLabel(5_000.0, unit, locale)
    return RunComplicationContent(
        state = ComplicationState.RECORDING,
        distance = distance,
        elapsed = formatElapsed(PREVIEW_ELAPSED_MS),
        detail = "$distance · ${formatPaceSecPerUnit(PREVIEW_PACE_SEC_PER_KM, unit)}",
    )
}

private const val PREVIEW_ELAPSED_MS = 26L * 60_000L + 15_000L
private const val PREVIEW_PACE_SEC_PER_KM = 315.0

/// How often the recording service pushes a fresh distance to the
/// complication while a run is RECORDING, in ticker ticks (the ticker runs
/// every 500 ms, so 120 ticks is 60 s).
///
/// Elapsed time needs no push at all — it is the face's own count-up text.
/// Distance and pace do, and every push costs a broadcast (or, on Wear SDK
/// 36+, a bind of this service) plus a face redraw. Once a minute keeps the
/// distance within a few hundred metres of truth at any running pace while
/// costing ~60 wakes an hour against the 7,200 a per-tick push would. Start,
/// pause, resume and stop push immediately on top of this.
internal const val COMPLICATION_PUSH_TICKS = 120

internal fun isComplicationPushTick(
    tickIndex: Int,
    stage: RecordingRepository.Stage,
): Boolean =
    stage == RecordingRepository.Stage.Recording &&
        tickIndex > 0 &&
        tickIndex % COMPLICATION_PUSH_TICKS == 0
