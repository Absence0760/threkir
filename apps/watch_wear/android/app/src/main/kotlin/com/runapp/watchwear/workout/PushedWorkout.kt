package com.runapp.watchwear.workout

import java.time.LocalDate
import java.time.format.DateTimeParseException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/// The kinds of step `expandWorkoutSteps` emits, by their wire token.
enum class StepKind(val token: String) {
    Warmup("warmup"),
    Rep("rep"),
    Recovery("recovery"),
    Walk("walk"),
    Steady("steady"),
    Cooldown("cooldown");

    companion object {
        fun fromToken(token: String?): StepKind? = entries.firstOrNull { it.token == token }
    }
}

/// One step of today's workout as the phone expanded it. Exactly one of
/// [distanceM] and [durationS] is set: the step ends when that axis is
/// covered.
data class PushedStep(
    val kind: StepKind,
    val repIndex: Int?,
    val repTotal: Int?,
    val distanceM: Int?,
    val durationS: Int?,
    val paceSPerKm: Int,
    val toleranceSPerKm: Int,
) {
    val isDurationBased: Boolean get() = durationS != null
}

/// Today's planned workout, pushed by the phone (`watch_workout_push.dart`)
/// already expanded into steps. The watch runs it as given and never
/// re-derives a pace.
data class PushedWorkout(
    val planWorkoutId: String,
    /// The plan day, `yyyy-MM-dd`, in the runner's own calendar.
    val scheduledDate: LocalDate,
    /// `plan_workouts.kind` (easy, interval, walk_run, …). Not rendered by
    /// this build; carried for the "today" tile and complication.
    val workoutKind: String,
    /// A walk-run session: no step is a pace test, so no step grades pace.
    val unpaced: Boolean,
    val steps: List<PushedStep>,
) {
    /// Whether this is today's workout on the watch's own calendar. A push
    /// from yesterday is never offered, so a phone left unopened past
    /// midnight cannot arm a stale session. The watch's calendar is the right
    /// one to read: the phone picks the workout on its own local date, which
    /// is the plan's, and a paired watch takes its zone from that phone. A
    /// "today" sent in the push would be exactly as stale as the push
    /// (decisions § 2102).
    fun isFor(today: LocalDate): Boolean = scheduledDate == today

    /// Sum of the distance-based steps, for the pre-run chip. Null when the
    /// session is all timed.
    val totalDistanceM: Int?
        get() = steps.mapNotNull { it.distanceM }.takeIf { it.isNotEmpty() }?.sum()

    /// Sum of the timed steps, for the pre-run chip. Null when none is timed.
    val totalDurationS: Int?
        get() = steps.mapNotNull { it.durationS }.takeIf { it.isNotEmpty() }?.sum()
}

/// What one push says.
sealed interface WorkoutPush {
    /// A workout to offer.
    data class Workout(val workout: PushedWorkout) : WorkoutPush

    /// The phone's explicit "nothing today": drop whatever the watch holds.
    data object None : WorkoutPush

    /// Not a payload this build can trust. Also drops what the watch holds:
    /// keeping a workout the phone has since replaced with something this
    /// build cannot read would offer a session the plan no longer has.
    data object Rejected : WorkoutPush
}

/// The payload version this build decodes; must equal
/// `kWatchWorkoutPayloadVersion` in `watch_workout_push.dart`.
const val WORKOUT_PAYLOAD_VERSION = 1

/// The custom watch's `WKT1` caps, which the phone already applies before it
/// pushes. Restated here so a payload that bypassed the phone gate still
/// cannot reach the runner: `kMaxWorkoutSteps`, the pace band and
/// `kWorkoutDistanceMaxM` in `watch_workout.dart`, and the wire's u8 / u16.
const val MAX_WORKOUT_STEPS = 64
const val WORKOUT_PACE_MIN_S_PER_KM = 120
const val WORKOUT_PACE_MAX_S_PER_KM = 5940
const val WORKOUT_DISTANCE_MAX_M = 1_000_000
private const val TOLERANCE_MAX = 0xFF
private const val DURATION_MAX_S = 0xFFFF

private val payloadJson = Json { ignoreUnknownKeys = true }

/// Decode one push, fail-closed. Matches the encoder in
/// `apps/mobile_android/lib/watch_workout_push.dart`; the shared fixture is
/// `fixtures/watch_workout_payload.json` (`WorkoutPushFixtureTest`).
///
/// A payload with no (or an empty) `plan_workout_id` is [WorkoutPush.None].
/// Anything else that is not exactly the shape the phone writes — another
/// version, a malformed date, a step with both or neither end axis, a target
/// outside the plausibility caps, a number where an integer belongs — is
/// [WorkoutPush.Rejected], whole: a half-decoded session is a different
/// session.
fun parseWorkoutPush(raw: String?): WorkoutPush {
    val obj = try {
        payloadJson.parseToJsonElement(raw ?: return WorkoutPush.Rejected) as? JsonObject
    } catch (_: Exception) {
        null
    } ?: return WorkoutPush.Rejected
    if (obj.int("v") != WORKOUT_PAYLOAD_VERSION) return WorkoutPush.Rejected
    val id = obj.string("plan_workout_id")
    if (id.isNullOrEmpty()) return WorkoutPush.None

    val date = try {
        LocalDate.parse(obj.string("scheduled_date") ?: return WorkoutPush.Rejected)
    } catch (_: DateTimeParseException) {
        return WorkoutPush.Rejected
    }
    val kind = obj.string("workout_kind") ?: return WorkoutPush.Rejected
    val unpaced = (obj["unpaced"] as? JsonPrimitive)
        ?.takeUnless { it.isString }?.booleanOrNull ?: return WorkoutPush.Rejected
    val rawSteps = obj["steps"] as? JsonArray ?: return WorkoutPush.Rejected
    if (rawSteps.isEmpty() || rawSteps.size > MAX_WORKOUT_STEPS) return WorkoutPush.Rejected
    val steps = rawSteps.map { parseStep(it) ?: return WorkoutPush.Rejected }
    return WorkoutPush.Workout(
        PushedWorkout(
            planWorkoutId = id,
            scheduledDate = date,
            workoutKind = kind,
            unpaced = unpaced,
            steps = steps,
        ),
    )
}

private fun parseStep(el: JsonElement): PushedStep? {
    val s = el as? JsonObject ?: return null
    val kind = StepKind.fromToken(s.string("kind")) ?: return null
    val hasDistance = "distance_m" in s
    val hasDuration = "duration_s" in s
    if (hasDistance == hasDuration) return null
    val distance = if (hasDistance) s.int("distance_m") ?: return null else null
    val duration = if (hasDuration) s.int("duration_s") ?: return null else null
    if (distance != null && distance !in 1..WORKOUT_DISTANCE_MAX_M) return null
    if (duration != null && duration !in 1..DURATION_MAX_S) return null
    val pace = s.int("pace_s_per_km") ?: return null
    if (pace !in WORKOUT_PACE_MIN_S_PER_KM..WORKOUT_PACE_MAX_S_PER_KM) return null
    val tolerance = s.int("tolerance_s_per_km") ?: return null
    if (tolerance !in 0..TOLERANCE_MAX) return null
    val repIndex = if ("rep_index" in s) s.int("rep_index") ?: return null else null
    val repTotal = if ("rep_total" in s) s.int("rep_total") ?: return null else null
    return PushedStep(
        kind = kind,
        repIndex = repIndex,
        repTotal = repTotal,
        distanceM = distance,
        durationS = duration,
        paceSPerKm = pace,
        toleranceSPerKm = tolerance,
    )
}

private fun JsonObject.string(key: String): String? =
    (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

/// An integer, and only an integer: `300.5` is refused rather than truncated,
/// because the phone writes whole seconds and metres and a fraction means the
/// writer is not the phone.
private fun JsonObject.int(key: String): Int? {
    val p = this[key] as? JsonPrimitive ?: return null
    if (p.isString) return null
    val l = p.longOrNull ?: return null
    if (p.doubleOrNull != l.toDouble()) return null
    return l.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()
}

/// The workout the pre-run screen offers from [push], or null: only a
/// workout scheduled for [today] on the watch's own calendar.
fun offeredWorkout(push: WorkoutPush?, today: LocalDate): PushedWorkout? =
    (push as? WorkoutPush.Workout)?.workout?.takeIf { it.isFor(today) }
