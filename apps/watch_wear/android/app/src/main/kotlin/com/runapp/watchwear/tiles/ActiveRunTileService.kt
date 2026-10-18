package com.runapp.watchwear.tiles

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.FontStyle
import androidx.wear.protolayout.LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.Colors
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders.Tile
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import com.runapp.watchwear.MainActivity
import com.runapp.watchwear.R
import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.recording.RecordingRepository
import com.runapp.watchwear.recording.formatDistance
import com.runapp.watchwear.recording.paceSecPerUnit
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/// Glanceable tile that shows the active-run summary on the runner's
/// watch face. Exists in three visual states — chosen at request time
/// from `RecordingRepository.metrics.value` and today's pushed workout:
///
///   - **Idle**: a single "Tap to start" prompt. Tapping the tile
///     opens the app on the pre-run screen so the runner can pick
///     activity / route and tap GO. The tile is intentionally not
///     a one-tap-start affordance; runners often pick a route from
///     the watch list, and a one-tap "this starts a run NOW" tile
///     would be a foot-gun for a casual swipe.
///   - **Today**: the idle state on a day the paired phone has pushed a
///     planned workout for (`/todays_workout`, read by [loadTodayGlance]):
///     its kind, its shape ("6 × 400 m") and step count. Tapping opens the
///     pre-run screen with that workout armed. The entry carries a validity
///     that ends at the watch's next local midnight, with the plain idle
///     layout as the timeline's default, so the renderer drops yesterday's
///     workout at midnight without asking for a new tile; a new push wakes
///     [TodaysWorkoutListenerService], which asks for one.
///   - **Active** (Recording or Paused): elapsed time as the headline
///     plus distance + pace as a stat row. Tapping resumes / opens
///     the running screen.
///
/// Tile updates are pushed externally via [requestUpdate] from the
/// recording service on every state transition (start, pause, stop)
/// and at a coarse cadence during a run — the tile renderer caches
/// the last layout, so we don't need a per-second refresh; the user
/// only sees the tile when they swipe to it. A 30-second freshness
/// window via [TimelineEntry] handles the "swiped while running 5
/// minutes after the last forced refresh" case.
///
/// The tile is registered in `AndroidManifest.xml` with the
/// `androidx.wear.tiles.action.BIND_TILE_PROVIDER` intent filter and
/// the `BIND_TILE_PROVIDER` permission. The XML preview drawable
/// referenced from `<meta-data>` is what watch face customization UI
/// shows when adding the tile.
class ActiveRunTileService : TileService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<Tile> {
        val metrics = RecordingRepository.metrics.value
        if (metrics.isActive) {
            val tile = tileOf(
                listOf(timelineEntry(buildActiveLayout(this, metrics))),
                // Re-request the tile after this many ms so a runner who
                // glances at the tile mid-run sees stats no older than 30
                // seconds without us waking up the recording service to
                // push every tick.
                freshnessMs = 30_000L,
            )
            return Futures.immediateFuture(tile)
        }
        val future = SettableFuture.create<Tile>()
        scope.launch {
            // Whatever goes wrong, the future is completed with a tile: an
            // unset one leaves the host waiting on a tile that never comes.
            val tile = try {
                idleTile(System.currentTimeMillis())
            } catch (e: Throwable) {
                Log.w(TAG, "today's workout not rendered; showing the idle tile", e)
                tileOf(listOf(timelineEntry(buildIdleLayout(this@ActiveRunTileService))), freshnessMs = 0L)
            }
            future.set(tile)
        }
        return future
    }

    /// The idle tile, with today's workout on top of it when there is one.
    /// The plain idle entry has no validity, so it is the default the
    /// renderer falls back to the moment the "today" entry's day ends:
    /// midnight drops yesterday's workout without a new request.
    private suspend fun idleTile(now: Long): Tile {
        val idle = timelineEntry(buildIdleLayout(this))
        val glance = loadTodayGlance(this, now)
        if (glance == null || glance.validUntilEpochMs <= now) return tileOf(listOf(idle), freshnessMs = 0L)
        val today = timelineEntry(
            buildTodayLayout(this, glance),
            TimelineBuilders.TimeInterval.Builder()
                .setStartMillis(now)
                .setEndMillis(glance.validUntilEpochMs)
                .build(),
        )
        return tileOf(listOf(today, idle), freshnessMs = 0L)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val resources = ResourceBuilders.Resources.Builder()
            .setVersion(RESOURCES_VERSION)
            .build()
        return Futures.immediateFuture(resources)
    }

    companion object {
        private const val TAG = "ActiveRunTile"

        /// Tell the platform to re-fetch the tile because the underlying
        /// state changed. Called from `RunRecordingService` whenever
        /// `Stage` transitions or distance ticks past a meaningful
        /// threshold — the platform debounces multiple rapid calls.
        ///
        /// Guarded because all four callers are on the recording path and
        /// three of them run inside `onStartCommand`, where an escaping
        /// throw is process death mid-run. `getUpdater` itself only
        /// allocates and a watch with no Tiles host is the case AndroidX
        /// already handles (`buildUpdateBindIntent` returns null, logged,
        /// no throw) — but the composite it returns then makes two IPC
        /// calls it does not isolate from each other or from us,
        /// `Context.bindService` and `Context.sendBroadcast`, the first
        /// of which is documented to raise `SecurityException`. A
        /// glanceable tile is an L4 effect and may not cost L1.
        ///
        /// The updater is bound through the APPLICATION context, never the
        /// caller's. `SysUiTileUpdateRequester` keeps the context it is given,
        /// binds SysUI through it, and unbinds later on its own executor
        /// thread. `stopRecording` calls this and then `stopSelf()`; the
        /// framework tears down a destroyed Service's bindings, so that
        /// deferred `unbindService` threw "Service not registered" on a
        /// thread no catch here can reach, and killed the app on every Stop.
        fun requestUpdate(context: Context) {
            try {
                getUpdater(context.applicationContext).requestUpdate(ActiveRunTileService::class.java)
            } catch (e: Throwable) {
                android.util.Log.w(TAG, "active-run tile update refused", e)
            }
        }
    }
}

private fun timelineEntry(
    root: LayoutElementBuilders.LayoutElement,
    validity: TimelineBuilders.TimeInterval? = null,
): TimelineBuilders.TimelineEntry {
    val builder = TimelineBuilders.TimelineEntry.Builder()
        .setLayout(LayoutElementBuilders.Layout.Builder().setRoot(root).build())
    if (validity != null) builder.setValidity(validity)
    return builder.build()
}

private fun tileOf(entries: List<TimelineBuilders.TimelineEntry>, freshnessMs: Long): Tile {
    val timeline = TimelineBuilders.Timeline.Builder()
    entries.forEach { timeline.addTimelineEntry(it) }
    return Tile.Builder()
        .setResourcesVersion(RESOURCES_VERSION)
        .setTileTimeline(timeline.build())
        .setFreshnessIntervalMillis(freshnessMs)
        .build()
}

private const val RESOURCES_VERSION = "1"

/// The "today" variant of the idle tile: what the plan has on for today, and
/// a tap that opens the pre-run screen with that workout armed
/// ([MainActivity.EXTRA_TODAY_WORKOUT_ID]). Still not a one-tap start, for
/// the same reason the idle tile is not.
private fun buildTodayLayout(
    context: Context,
    glance: TodayGlance,
): LayoutElementBuilders.LayoutElement {
    val tapModifier = ModifiersBuilders.Modifiers.Builder()
        .setClickable(
            ModifiersBuilders.Clickable.Builder()
                .setId("today_tap")
                .setOnClick(
                    androidx.wear.protolayout.ActionBuilders.LaunchAction.Builder()
                        .setAndroidActivity(
                            androidx.wear.protolayout.ActionBuilders.AndroidActivity.Builder()
                                .setClassName(MainActivity::class.java.name)
                                .setPackageName(context.packageName)
                                .addKeyToExtraMapping(
                                    MainActivity.EXTRA_TODAY_WORKOUT_ID,
                                    androidx.wear.protolayout.ActionBuilders.stringExtra(glance.planWorkoutId),
                                )
                                .build(),
                        )
                        .build(),
                )
                .build(),
        )
        .build()

    val steps = context.resources.getQuantityString(
        R.plurals.workout_step_count,
        glance.stepCount,
        glance.stepCount,
    )

    return LayoutElementBuilders.Box.Builder()
        .setWidth(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHeight(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
        .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        .setModifiers(tapModifier)
        .addContent(
            LayoutElementBuilders.Column.Builder()
                .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
                .addContent(
                    Text.Builder(context, context.getString(R.string.tile_today))
                        .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                        .setColor(argb(Colors.DEFAULT.primary))
                        .build(),
                )
                .addContent(verticalSpacer(4))
                .addContent(
                    Text.Builder(context, context.getString(planKindLabel(glance.kind)))
                        .setTypography(Typography.TYPOGRAPHY_TITLE3)
                        .setColor(argb(Colors.DEFAULT.onSurface))
                        .setMaxLines(1)
                        .build(),
                )
                .addContent(verticalSpacer(4))
                .addContent(
                    Text.Builder(context, "${glance.headline} · $steps")
                        .setTypography(Typography.TYPOGRAPHY_BODY2)
                        .setColor(argb(Colors.DEFAULT.onSurface))
                        .setMaxLines(1)
                        .build(),
                )
                .addContent(verticalSpacer(8))
                .addContent(
                    Text.Builder(context, context.getString(R.string.tile_tap_to_start))
                        .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                        .setColor(argb(Colors.DEFAULT.primary))
                        .build(),
                )
                .build(),
        )
        .build()
}

/// The full label for a plan workout kind. Shared with the complication's
/// long form, so both glances name a session the same way.
internal fun planKindLabel(kind: PlanKind): Int = when (kind) {
    PlanKind.EASY -> R.string.workout_kind_easy
    PlanKind.LONG -> R.string.workout_kind_long
    PlanKind.RECOVERY -> R.string.workout_kind_recovery
    PlanKind.TEMPO -> R.string.workout_kind_tempo
    PlanKind.INTERVAL -> R.string.workout_kind_interval
    PlanKind.MARATHON_PACE -> R.string.workout_kind_marathon_pace
    PlanKind.WALK_RUN -> R.string.workout_kind_walk_run
    PlanKind.RACE -> R.string.workout_kind_race
    PlanKind.OTHER -> R.string.workout
}

private fun buildIdleLayout(context: Context): LayoutElementBuilders.LayoutElement {
    val intent = Intent(context, MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    val tapModifier = ModifiersBuilders.Modifiers.Builder()
        .setClickable(
            ModifiersBuilders.Clickable.Builder()
                .setId("idle_tap")
                .setOnClick(
                    androidx.wear.protolayout.ActionBuilders.LaunchAction.Builder()
                        .setAndroidActivity(
                            androidx.wear.protolayout.ActionBuilders.AndroidActivity.Builder()
                                .setClassName(MainActivity::class.java.name)
                                .setPackageName(context.packageName)
                                .build(),
                        )
                        .build(),
                )
                .build(),
        )
        .build()

    return LayoutElementBuilders.Box.Builder()
        .setWidth(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHeight(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
        .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        .setModifiers(tapModifier)
        .addContent(
            LayoutElementBuilders.Column.Builder()
                .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
                .addContent(
                    Text.Builder(context, context.getString(R.string.tile_run))
                        .setTypography(Typography.TYPOGRAPHY_TITLE3)
                        .setColor(argb(Colors.DEFAULT.primary))
                        .build(),
                )
                .addContent(verticalSpacer(8))
                .addContent(
                    Text.Builder(context, context.getString(R.string.tile_tap_to_start))
                        .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                        .setColor(argb(Colors.DEFAULT.onSurface))
                        .build(),
                )
                .build(),
        )
        .build()
}

private fun buildActiveLayout(
    context: Context,
    metrics: RecordingRepository.Metrics,
): LayoutElementBuilders.LayoutElement {
    val tapModifier = ModifiersBuilders.Modifiers.Builder()
        .setClickable(
            ModifiersBuilders.Clickable.Builder()
                .setId("active_tap")
                .setOnClick(
                    androidx.wear.protolayout.ActionBuilders.LaunchAction.Builder()
                        .setAndroidActivity(
                            androidx.wear.protolayout.ActionBuilders.AndroidActivity.Builder()
                                .setClassName(MainActivity::class.java.name)
                                .setPackageName(context.packageName)
                                .build(),
                        )
                        .build(),
                )
                .build(),
        )
        .build()

    val statusLabel = if (metrics.stage == RecordingRepository.Stage.Paused) {
        context.getString(R.string.tile_paused)
    } else {
        context.getString(R.string.tile_running)
    }

    return LayoutElementBuilders.Box.Builder()
        .setWidth(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHeight(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
        .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        .setModifiers(tapModifier)
        .addContent(
            LayoutElementBuilders.Column.Builder()
                .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
                .addContent(
                    Text.Builder(context, statusLabel)
                        .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                        .setColor(argb(Colors.DEFAULT.primary))
                        .build(),
                )
                .addContent(verticalSpacer(4))
                .addContent(
                    LayoutElementBuilders.Text.Builder()
                        .setText(formatElapsed(metrics.elapsedMs))
                        .setFontStyle(
                            FontStyle.Builder()
                                .setSize(sp(28f))
                                .setColor(argb(Colors.DEFAULT.onSurface))
                                .setWeight(LayoutElementBuilders.FONT_WEIGHT_MEDIUM)
                                .build(),
                        )
                        .build(),
                )
                .addContent(verticalSpacer(6))
                .addContent(
                    Text.Builder(context, formatStatRow(metrics))
                        .setTypography(Typography.TYPOGRAPHY_BODY2)
                        .setColor(argb(Colors.DEFAULT.onSurface))
                        .build(),
                )
                .build(),
        )
        .build()
}

private fun verticalSpacer(heightDp: Int): LayoutElementBuilders.LayoutElement =
    LayoutElementBuilders.Spacer.Builder()
        .setHeight(dp(heightDp.toFloat()))
        .build()

/// Format `elapsedMs` as `H:MM:SS` (or `MM:SS` under an hour). Pure
/// helper so the unit test can pin the tile's surfaces without
/// running ProtoLayout. Time digits are locale-independent (no decimal
/// separator involved), so the format Locale is fixed for stability.
internal fun formatElapsed(elapsedMs: Long): String {
    val totalSeconds = (elapsedMs / 1000L).coerceAtLeast(0L)
    val hours = totalSeconds / 3600L
    val minutes = (totalSeconds % 3600L) / 60L
    val seconds = totalSeconds % 60L
    return if (hours > 0) {
        String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.ROOT, "%02d:%02d", minutes, seconds)
    }
}

/// Render the secondary stat row: distance and pace separated by a
/// middle-dot, both in the run's [DistanceUnit] (stamped on the metrics
/// at run start from the runner's `preferred_unit` pref). Pure helper so
/// the layout file stays readable and the formatting is testable in
/// isolation. The distance decimal separator follows [locale] (device
/// locale at the call site); the unit word ("km" / "mi") is invariant
/// across the six shipped locales, the same way "km" was inlined before.
internal fun formatStatRow(
    metrics: RecordingRepository.Metrics,
    locale: Locale = Locale.getDefault(),
): String {
    val unit = metrics.preferredUnit
    val distLabel = formatDistanceLabel(metrics.distanceM, unit, locale)
    val paceLabel = formatPaceSecPerUnit(metrics.paceSecPerKm, unit)
    return "$distLabel · $paceLabel"
}

/// Distance with its unit word, e.g. "5.21 km" / "12.3 mi": two decimals
/// below the 10-unit mark and one from it, so a long run still fits a
/// glanceable slot. Shared by the tile and the watch-face complication.
internal fun formatDistanceLabel(
    distanceM: Double,
    unit: DistanceUnit,
    locale: Locale = Locale.getDefault(),
): String {
    val displayValue = when (unit) {
        DistanceUnit.KM -> distanceM / 1000.0
        DistanceUnit.MI -> distanceM / com.runapp.watchwear.recording.METRES_PER_MILE
    }
    val decimals = if (displayValue >= 10.0) 1 else 2
    return "${formatDistance(distanceM, unit, decimals, locale)} ${unitWord(unit)}"
}

internal fun formatPaceSecPerUnit(secPerKm: Double?, unit: DistanceUnit): String {
    val unitWord = unitWord(unit)
    if (secPerKm == null || !secPerKm.isFinite() || secPerKm <= 0.0) return "—:—/$unitWord"
    val perUnit = paceSecPerUnit(secPerKm, unit).toLong()
    val mins = perUnit / 60L
    val secs = perUnit % 60L
    return String.format(Locale.ROOT, "%d:%02d/%s", mins, secs, unitWord)
}

private fun unitWord(unit: DistanceUnit): String = when (unit) {
    DistanceUnit.KM -> "km"
    DistanceUnit.MI -> "mi"
}

@Suppress("unused") // Reserved for a future per-tile launch action that
                    // routes directly to the running screen vs the idle
                    // screen — kept in the same file as the layouts so
                    // the targeting stays adjacent to the modifier.
private fun launchComponent(context: Context): ComponentName =
    ComponentName(context, MainActivity::class.java)
