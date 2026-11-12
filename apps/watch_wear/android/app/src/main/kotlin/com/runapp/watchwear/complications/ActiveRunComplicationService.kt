package com.runapp.watchwear.complications

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.util.Log
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountUpTimeReference
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService.ComplicationRequestListener
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.TimeInterval
import androidx.wear.watchface.complications.datasource.TimelineEntry
import com.runapp.watchwear.MainActivity
import com.runapp.watchwear.R
import com.runapp.watchwear.recording.RecordingRepository
import com.runapp.watchwear.tiles.PlanKind
import com.runapp.watchwear.tiles.loadTodayGlance
import com.runapp.watchwear.tiles.planKindLabel
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/// Watch-face complication: the run in progress, or the last run this watch
/// recorded, on any face with a free slot.
///
///   - **Recording**: elapsed time (ticked by the face itself, see
///     [RunComplicationContent.liveSinceEpochMs]) plus distance, and pace on
///     the long form.
///   - **Paused**: the frozen elapsed time and distance, labelled paused.
///   - **Today**: on a day the paired phone pushed a planned workout for and
///     no run is active, its kind (short slot) or kind and shape (long slot),
///     served as a timeline entry that ends at local midnight over the idle
///     content below.
///   - **Idle**: the last run's distance and duration, or a start prompt on a
///     watch that has recorded nothing (or was signed out since).
///
/// Every request is answered from process memory (`RecordingRepository`) or
/// local reads (DataStore, and the Data Layer item the phone pushed) — never
/// the network. Tapping opens the app, which
/// lands on the running screen when a run is live, exactly as the tile does.
///
/// Updates are pushed by [requestUpdate] from the recording service on every
/// stage transition and once a minute while recording
/// ([COMPLICATION_PUSH_TICKS]), by `RunViewModel` when the last-run entry
/// is written or cleared, and by `TodaysWorkoutListenerService` when the
/// phone pushes a new day's workout. The manifest's UPDATE_PERIOD_SECONDS is an hourly
/// safety net for a push that was refused, not the delivery mechanism.
class ActiveRunComplicationService : ComplicationDataSourceService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener,
    ) {
        val metrics = RecordingRepository.metrics.value
        scope.launch {
            val lastRun = if (metrics.isActive) {
                null
            } else {
                try {
                    LastRunStore(this@ActiveRunComplicationService).current()
                } catch (e: Throwable) {
                    Log.w(TAG, "last run unreadable; showing the start prompt", e)
                    null
                }
            }
            val now = System.currentTimeMillis()
            val content = complicationContent(metrics, lastRun, now)
            val data = try {
                buildData(request.complicationType, content)
            } catch (e: Throwable) {
                Log.w(TAG, "complication data not built for ${request.complicationType}", e)
                null
            }
            val timeline = if (metrics.isActive || data == null) null else todayTimeline(request, data, now)
            try {
                if (timeline != null) {
                    listener.onComplicationDataTimeline(timeline)
                } else {
                    listener.onComplicationData(data)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "complication data not delivered", e)
            }
        }
    }

    /// Today's planned workout over [base], valid until the watch's next
    /// local midnight, or null when there is none (or it cannot be read, in
    /// which case the face keeps the last-run content it would show anyway).
    private suspend fun todayTimeline(
        request: ComplicationRequest,
        base: ComplicationData,
        now: Long,
    ): ComplicationDataTimeline? = try {
        loadTodayGlance(this, now)
            ?.takeIf { it.validUntilEpochMs > now }
            ?.let { glance ->
                buildData(request.complicationType, todayComplicationContent(glance))?.let { today ->
                    ComplicationDataTimeline(
                        base,
                        listOf(
                            TimelineEntry(
                                TimeInterval(Instant.ofEpochMilli(now), Instant.ofEpochMilli(glance.validUntilEpochMs)),
                                today,
                            ),
                        ),
                    )
                }
            }
    } catch (e: Throwable) {
        Log.w(TAG, "today's workout not added to the complication", e)
        null
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        buildData(type, previewContent())

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun buildData(type: ComplicationType, content: RunComplicationContent): ComplicationData? {
        val description = plain(contentDescription(content))
        val tap = tapIntent()
        return when (type) {
            ComplicationType.SHORT_TEXT ->
                ShortTextComplicationData.Builder(shortText(content), description)
                    .setTitle(shortTitle(content))
                    .setMonochromaticImage(icon())
                    .setTapAction(tap)
                    .build()
            ComplicationType.LONG_TEXT ->
                LongTextComplicationData.Builder(plain(longText(content)), description)
                    .setTitle(longTitle(content))
                    .setMonochromaticImage(icon())
                    .setTapAction(tap)
                    .build()
            ComplicationType.MONOCHROMATIC_IMAGE ->
                MonochromaticImageComplicationData.Builder(icon(), description)
                    .setTapAction(tap)
                    .build()
            else -> null
        }
    }

    private fun shortText(content: RunComplicationContent): ComplicationText = when (content.state) {
        ComplicationState.RECORDING -> elapsedText(content)
        ComplicationState.PAUSED -> plain(content.elapsed)
        ComplicationState.TODAY -> plain(getString(planKindShortLabel(content.kind)))
        ComplicationState.LAST_RUN -> plain(content.distance)
        ComplicationState.NO_RUN -> plain(getString(R.string.tile_run))
    }

    private fun shortTitle(content: RunComplicationContent): ComplicationText? = when (content.state) {
        ComplicationState.RECORDING -> plain(content.distance)
        ComplicationState.PAUSED -> plain(getString(R.string.tile_paused))
        ComplicationState.TODAY -> plain(getString(R.string.complication_today_short))
        ComplicationState.LAST_RUN -> plain(getString(R.string.complication_last_short))
        ComplicationState.NO_RUN -> null
    }

    private fun longText(content: RunComplicationContent): String = when (content.state) {
        ComplicationState.NO_RUN -> getString(R.string.tile_tap_to_start)
        else -> content.detail
    }

    private fun longTitle(content: RunComplicationContent): ComplicationText = when (content.state) {
        ComplicationState.RECORDING -> elapsedText(content)
        ComplicationState.PAUSED -> plain(getString(R.string.tile_paused))
        ComplicationState.TODAY -> plain(getString(planKindLabel(content.kind ?: PlanKind.OTHER)))
        ComplicationState.LAST_RUN -> plain(getString(R.string.complication_last_run))
        ComplicationState.NO_RUN -> plain(getString(R.string.tile_run))
    }

    private fun contentDescription(content: RunComplicationContent): String = when (content.state) {
        ComplicationState.RECORDING ->
            getString(R.string.complication_desc_recording, content.elapsed, content.distance)
        ComplicationState.PAUSED ->
            getString(R.string.complication_desc_paused, content.elapsed, content.distance)
        ComplicationState.TODAY ->
            getString(
                R.string.complication_desc_today,
                getString(planKindLabel(content.kind ?: PlanKind.OTHER)),
                content.detail,
            )
        ComplicationState.LAST_RUN ->
            getString(R.string.complication_desc_last_run, content.distance, content.elapsed)
        ComplicationState.NO_RUN -> getString(R.string.tile_tap_to_start)
    }

    /// Live count-up while recording, so the face ticks the seconds itself;
    /// fixed text anywhere there is no anchor (the editor preview).
    private fun elapsedText(content: RunComplicationContent): ComplicationText {
        val since = content.liveSinceEpochMs ?: return plain(content.elapsed)
        return TimeDifferenceComplicationText.Builder(
            TimeDifferenceStyle.STOPWATCH,
            CountUpTimeReference(Instant.ofEpochMilli(since)),
        ).build()
    }

    private fun icon(): MonochromaticImage =
        MonochromaticImage.Builder(Icon.createWithResource(this, R.drawable.ic_complication_mark))
            .build()

    private fun tapIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /// The short-slot code for a plan kind; a kind with none falls back to
    /// the word "Today", which is still true and fits.
    private fun planKindShortLabel(kind: PlanKind?): Int = when (kind) {
        PlanKind.EASY -> R.string.workout_kind_short_easy
        PlanKind.LONG -> R.string.workout_kind_short_long
        PlanKind.RECOVERY -> R.string.workout_kind_short_recovery
        PlanKind.TEMPO -> R.string.workout_kind_short_tempo
        PlanKind.INTERVAL -> R.string.workout_kind_short_interval
        PlanKind.MARATHON_PACE -> R.string.workout_kind_short_marathon_pace
        PlanKind.WALK_RUN -> R.string.workout_kind_short_walk_run
        PlanKind.RACE -> R.string.workout_kind_short_race
        PlanKind.OTHER, null -> R.string.complication_today_short
    }

    private fun plain(text: String): ComplicationText = PlainComplicationText.Builder(text).build()

    companion object {
        private const val TAG = "ActiveRunComplication"

        /// Ask every watch face hosting this complication to re-request it.
        ///
        /// Guarded for the same reason the tile's is: the callers sit on the
        /// recording path, three of them inside `onStartCommand`, and the
        /// legacy path is a `sendBroadcast` that can raise. A glanceable
        /// complication is an L4 effect and may not cost L1. Bound through
        /// the application context so nothing outlives a stopped service.
        fun requestUpdate(context: Context) {
            try {
                val app = context.applicationContext
                ComplicationDataSourceUpdateRequester
                    .create(app, ComponentName(app, ActiveRunComplicationService::class.java))
                    .requestUpdateAll()
            } catch (e: Throwable) {
                Log.w(TAG, "complication update refused", e)
            }
        }
    }
}
