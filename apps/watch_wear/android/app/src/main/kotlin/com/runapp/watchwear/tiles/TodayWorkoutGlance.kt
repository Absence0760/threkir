package com.runapp.watchwear.tiles

import com.runapp.watchwear.complications.LastRun
import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.workout.PushedWorkout
import com.runapp.watchwear.workout.StepKind
import com.runapp.watchwear.workout.WorkoutPush
import com.runapp.watchwear.workout.offeredWorkout
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/// `plan_workouts.kind` as the glances label it. [OTHER] is a kind this build
/// has no label for (a value added to the `workout_kind` enum later, or
/// `rest`, which the phone never pushes because it has no steps): the glance
/// still shows the workout, under the generic "Workout" label.
internal enum class PlanKind(val token: String?) {
    EASY("easy"),
    LONG("long"),
    RECOVERY("recovery"),
    TEMPO("tempo"),
    INTERVAL("interval"),
    MARATHON_PACE("marathon_pace"),
    WALK_RUN("walk_run"),
    RACE("race"),
    OTHER(null);

    companion object {
        fun of(token: String): PlanKind = entries.firstOrNull { it.token == token } ?: OTHER
    }
}

/// What the tile and the complication show for today's planned workout.
internal data class TodayGlance(
    val planWorkoutId: String,
    val kind: PlanKind,
    /// The session's shape in one short line: "6 × 400 m" for a repeat
    /// session, otherwise its total distance or, when it is all timed, its
    /// total time.
    val headline: String,
    val stepCount: Int,
    /// The instant the glance stops being "today" on the watch's calendar.
    val validUntilEpochMs: Long,
)

/// Today's workout for the glances, or null when there is none to offer.
///
/// The same rule the pre-run screen applies ([offeredWorkout]): only a push
/// scheduled for the watch's own [today]. On top of it, a workout this watch
/// already recorded a run against is not offered again — [lastRun] carries
/// the plan workout the last run followed, and the phone only learns the
/// session is done when it next reads the plan, so without this the tile
/// would keep inviting the runner to a session they have just finished.
///
/// The unit is the last run's, the only copy of `preferred_unit` the watch
/// keeps outside a live session (see [LastRun]); km before the first run.
internal fun todayGlance(
    push: WorkoutPush?,
    lastRun: LastRun?,
    today: LocalDate,
    zone: ZoneId,
    locale: Locale = Locale.getDefault(),
): TodayGlance? {
    val workout = offeredWorkout(push, today) ?: return null
    if (lastRun?.planWorkoutId == workout.planWorkoutId) return null
    val unit = DistanceUnit.fromPref(lastRun?.unit)
    return TodayGlance(
        planWorkoutId = workout.planWorkoutId,
        kind = PlanKind.of(workout.workoutKind),
        headline = workoutHeadline(workout, unit, locale),
        stepCount = workout.steps.size,
        validUntilEpochMs = startOfNextDayMs(today, zone),
    )
}

/// The session in one line. A repeat session is named by its reps, the way
/// a runner says it ("6 × 400 m", "8 × 1:00"), when every rep shares one
/// target on one axis; rep distances stay in metres whatever the unit,
/// because that is how track reps are written in both systems. Anything else
/// is named by its total distance in [unit], or its total time when no step
/// has a distance.
internal fun workoutHeadline(
    workout: PushedWorkout,
    unit: DistanceUnit,
    locale: Locale = Locale.getDefault(),
): String {
    val reps = workout.steps.filter { it.kind == StepKind.Rep }
    if (reps.size >= 2) {
        val distances = reps.map { it.distanceM }.toSet()
        val durations = reps.map { it.durationS }.toSet()
        val distance = distances.singleOrNull()
        val duration = durations.singleOrNull()
        if (distance != null) return "${reps.size} × $distance m"
        if (duration != null) return "${reps.size} × ${formatClock(duration)}"
    }
    workout.totalDistanceM?.let { return formatDistanceLabel(it.toDouble(), unit, locale) }
    return formatClock(workout.totalDurationS ?: 0)
}

/// `m:ss`, or `h:mm:ss` from an hour. Digits only, so the locale is fixed.
internal fun formatClock(totalS: Int): String {
    val s = totalS.coerceAtLeast(0)
    val h = s / 3600
    val m = (s % 3600) / 60
    val sec = s % 60
    return if (h > 0) {
        String.format(Locale.ROOT, "%d:%02d:%02d", h, m, sec)
    } else {
        String.format(Locale.ROOT, "%d:%02d", m, sec)
    }
}

/// The first instant of the day after [today] in [zone]. `atStartOfDay`
/// rather than "+24 h", so a DST change, or a zone whose midnight does not
/// exist on the change day, still ends the glance at the real day boundary.
internal fun startOfNextDayMs(today: LocalDate, zone: ZoneId): Long =
    today.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()

/// The watch's calendar day at [nowEpochMs] in [zone].
internal fun localDate(nowEpochMs: Long, zone: ZoneId): LocalDate =
    Instant.ofEpochMilli(nowEpochMs).atZone(zone).toLocalDate()
