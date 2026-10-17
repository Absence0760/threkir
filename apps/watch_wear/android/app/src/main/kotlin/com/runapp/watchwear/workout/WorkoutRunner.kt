package com.runapp.watchwear.workout

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToLong
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/// What one feed of totals produced, in order.
sealed interface WorkoutEvent {
    /// A step began. [previousIndex] is -1 for the first one.
    data class Transition(val previousIndex: Int, val currentIndex: Int) : WorkoutEvent

    /// The end of the current step is close: the last 50 m of a distance
    /// step over 100 m, or the last 10 s of a timed step over 20 s.
    data class Warning(val index: Int) : WorkoutEvent

    /// The runner is well off the step's target pace, rate-limited to one
    /// per [WorkoutRunner.DRIFT_CUE_INTERVAL_MS].
    data class PaceDrift(val index: Int, val ahead: Boolean, val deltaSPerKm: Int) : WorkoutEvent

    data object Complete : WorkoutEvent
}

/// One step's planned-vs-actual row, `runs.metadata.workout_step_results[]`.
@Serializable
data class WorkoutStepResultRecord(
    val stepIndex: Int,
    val kind: String,
    val repIndex: Int? = null,
    val repTotal: Int? = null,
    val targetDistanceM: Double,
    val targetDurationS: Int? = null,
    val actualDistanceM: Double,
    val targetPaceSPerKm: Int,
    val actualPaceSPerKm: Int? = null,
    val toleranceSPerKm: Int,
    val durationS: Int,
    val status: String,
)

/// The review a run started from a pushed workout carries: the three
/// `runs.metadata` keys `WorkoutRunner.reviewMetadata` writes on the phone.
/// Serializable so the upload queue and the crash checkpoint keep it.
@Serializable
data class WorkoutReview(
    val planWorkoutId: String,
    val adherence: String,
    val steps: List<WorkoutStepResultRecord>,
) {
    /// Exactly the shape `WorkoutStepResult.toJson` writes on the phone, which
    /// both run detail screens render (docs/backend/metadata.md).
    fun stepResultsJson() = buildJsonArray {
        for (r in steps) addJsonObject {
            put("step_index", r.stepIndex)
            put("kind", r.kind)
            r.repIndex?.let { put("rep_index", it) }
            r.repTotal?.let { put("rep_total", it) }
            put("target_distance_m", r.targetDistanceM)
            r.targetDurationS?.let { put("target_duration_s", it) }
            put("actual_distance_m", r.actualDistanceM)
            put("target_pace_sec_per_km", r.targetPaceSPerKm)
            if (r.actualPaceSPerKm != null) {
                put("actual_pace_sec_per_km", r.actualPaceSPerKm)
            } else {
                put("actual_pace_sec_per_km", JsonNull)
            }
            put("tolerance_sec_per_km", r.toleranceSPerKm)
            put("duration_s", r.durationS)
            put("status", r.status)
        }
    }
}

/// What the running screen shows about the workout.
data class WorkoutView(
    /// Null once the workout is complete.
    val step: PushedStep?,
    val index: Int,
    val stepCount: Int,
    /// Metres left on a distance step, null on a timed one.
    val remainingM: Double?,
    /// Seconds left on a timed step, null on a distance one.
    val remainingS: Int?,
    /// Whether the session grades pace at all (false on walk-run).
    val paced: Boolean,
)

/// The structured-workout step runner, a port of the phone's
/// `packages/run_recorder/lib/src/workout_runner.dart` (the reference) and a
/// sibling of the custom watch's `watch_core::workout` (§354). Pure: fed the
/// run's totals, it returns what happened, and owns no clock, sensor or
/// vibrator.
///
/// [onTotals] takes ACTIVE elapsed time, the same clock the phone's runner
/// reads: a manual pause stops it, so a timed recovery does not run out while
/// the runner has paused the recording.
///
/// Ported: auto-advance on either axis with the overshoot carried into the
/// next step (one feed can cross several short steps after a GPS gap), the
/// end-of-step warning, the 45 s pace-drift cue on paced steps, manual skip,
/// per-step results and the adherence roll-up. Not ported, for §354's
/// reasons: rewind and abandon (no control budget on a wrist; stopping the
/// run or ignoring the step line covers abandon) and the halfway cue (the
/// step line shows what is left). `fixtures/watch_workout_payload.json`
/// § runner_vectors holds this port to the reference.
class WorkoutRunner(val workout: PushedWorkout) {

    val steps: List<PushedStep> get() = workout.steps

    private var idx = 0
    private var stepStartDistanceM = 0.0
    private var stepStartElapsedS = 0.0
    private var lastDistanceM = 0.0
    private var lastElapsedS = 0.0
    private var hasTotals = false
    private var emittedFirst = false
    private var firedWarning = false
    private var lastDriftAtMs: Long? = null
    private val results = mutableListOf<WorkoutStepResultRecord>()

    val currentIndex: Int get() = idx
    val isComplete: Boolean get() = idx >= steps.size

    /// While true the step owns the run's pace cues, and the run's general
    /// target-pace alert stands down (decisions § 2076).
    val ownsPaceCues: Boolean get() = !isComplete

    private val stepDistanceM: Double
        get() = if (!hasTotals) 0.0 else (lastDistanceM - stepStartDistanceM).coerceAtLeast(0.0)

    private val stepElapsedS: Double
        get() = if (!hasTotals) 0.0 else (lastElapsedS - stepStartElapsedS).coerceAtLeast(0.0)

    /// Whole seconds, as the phone's `Duration.inSeconds` reads them.
    private val stepSecs: Int get() = floor(stepElapsedS).toInt()

    fun view(): WorkoutView {
        val step = steps.getOrNull(idx)
        return WorkoutView(
            step = step,
            index = idx,
            stepCount = steps.size,
            remainingM = step?.distanceM?.let { (it - stepDistanceM).coerceAtLeast(0.0) },
            remainingS = step?.durationS?.let { (it - stepSecs).coerceAtLeast(0) },
            paced = !workout.unpaced,
        )
    }

    fun onTotals(distanceM: Double, elapsedS: Double, nowMs: Long): List<WorkoutEvent> {
        if (steps.isEmpty() || isComplete) return emptyList()
        val out = mutableListOf<WorkoutEvent>()
        lastDistanceM = distanceM
        lastElapsedS = elapsedS
        hasTotals = true

        if (!emittedFirst) {
            emittedFirst = true
            stepStartDistanceM = distanceM
            stepStartElapsedS = elapsedS
            out += WorkoutEvent.Transition(previousIndex = -1, currentIndex = 0)
        }

        val step = steps[idx]
        val dist = stepDistanceM
        val secs = stepSecs

        val warningHit = when {
            step.durationS != null -> step.durationS - secs <= 10 && step.durationS > 20
            else -> step.distanceM!! - dist <= 50 && step.distanceM > 100
        }
        if (!firedWarning && warningHit) {
            firedWarning = true
            out += WorkoutEvent.Warning(idx)
        }

        val drift = paceDrift(step)
        if (drift != null) {
            val last = lastDriftAtMs
            if (last == null || nowMs - last >= DRIFT_CUE_INTERVAL_MS) {
                lastDriftAtMs = nowMs
                out += WorkoutEvent.PaceDrift(idx, ahead = drift < 0, deltaSPerKm = abs(drift))
            }
        }

        while (!isComplete) {
            val cur = steps[idx]
            val hit = if (cur.durationS != null) stepSecs >= cur.durationS else stepDistanceM >= cur.distanceM!!
            if (!hit) break
            out += advance(status = STATUS_COMPLETED, carryOvershoot = true)
        }
        return out
    }

    /// Skip the current step: what it covered is its actual, status skipped,
    /// and the next step starts from the latest totals.
    fun skipStep(): List<WorkoutEvent> {
        if (isComplete || !hasTotals) return emptyList()
        return listOf(advance(status = STATUS_SKIPPED, carryOvershoot = false))
    }

    /// Results so far, the step in progress included as `skipped` — the
    /// crash-recovery shape the phone writes on every in-progress save.
    fun snapshotResults(): List<WorkoutStepResultRecord> {
        val out = results.toMutableList()
        if (!isComplete && hasTotals) {
            out += resultFor(idx, steps[idx], stepDistanceM, stepElapsedS, STATUS_SKIPPED)
        }
        return out
    }

    /// `completed` when every step ran to at least 80 % of its target on its
    /// own axis, `partial` otherwise. The phone's third value, `abandoned`,
    /// is only reachable here as a workout that never started.
    fun adherence(): String {
        val rs = snapshotResults()
        if (rs.isEmpty()) return "abandoned"
        var short = rs.size < steps.size
        for (r in rs) {
            if (r.status == STATUS_SKIPPED) {
                short = true
                continue
            }
            val target = r.targetDurationS
            if (target != null) {
                if (r.durationS < target * 0.8) short = true
            } else if (r.actualDistanceM < r.targetDistanceM * 0.8) {
                short = true
            }
        }
        return if (short) "partial" else "completed"
    }

    fun review(): WorkoutReview = WorkoutReview(
        planWorkoutId = workout.planWorkoutId,
        adherence = adherence(),
        steps = snapshotResults(),
    )

    /// Signed drift in s/km (positive = slower) when the step is paced and
    /// the runner is past twice its tolerance, else null.
    private fun paceDrift(step: PushedStep): Int? {
        if (workout.unpaced) return null
        val d = stepDistanceM
        val secs = stepSecs
        if (d < 5 || secs < 1) return null
        val actual = (secs / (d / 1000.0)).roundToLong().toInt()
        val diff = actual - step.paceSPerKm
        return if (abs(diff) > step.toleranceSPerKm * 2) diff else null
    }

    private fun advance(status: String, carryOvershoot: Boolean): WorkoutEvent {
        val step = steps[idx]
        val coveredDist = stepDistanceM
        val coveredElapsed = stepElapsedS
        val consumedDist: Double
        val consumedElapsed: Double
        if (carryOvershoot) {
            if (step.durationS != null) {
                consumedElapsed = step.durationS.toDouble()
                val ratio = if (coveredElapsed > 0) (consumedElapsed / coveredElapsed).coerceIn(0.0, 1.0) else 1.0
                consumedDist = coveredDist * ratio
            } else {
                consumedDist = step.distanceM!!.toDouble()
                val ratio = if (coveredDist > 0) (consumedDist / coveredDist).coerceIn(0.0, 1.0) else 1.0
                consumedElapsed = coveredElapsed * ratio
            }
        } else {
            consumedDist = coveredDist
            consumedElapsed = coveredElapsed
        }
        results += resultFor(idx, step, consumedDist, consumedElapsed, status)

        val prev = idx
        idx += 1
        if (carryOvershoot) {
            stepStartDistanceM += consumedDist
            stepStartElapsedS += consumedElapsed
        } else {
            stepStartDistanceM = lastDistanceM
            stepStartElapsedS = lastElapsedS
        }
        firedWarning = false
        lastDriftAtMs = null
        return if (isComplete) WorkoutEvent.Complete else WorkoutEvent.Transition(prev, idx)
    }

    private fun resultFor(
        index: Int,
        step: PushedStep,
        distanceM: Double,
        elapsedS: Double,
        status: String,
    ): WorkoutStepResultRecord {
        val secs = floor(elapsedS).toInt()
        val pace = if (distanceM >= 5 && secs >= 1) {
            (secs / (distanceM / 1000.0)).roundToLong().toInt()
        } else {
            null
        }
        return WorkoutStepResultRecord(
            stepIndex = index,
            kind = step.kind.token,
            repIndex = step.repIndex,
            repTotal = step.repTotal,
            targetDistanceM = (step.distanceM ?: 0).toDouble(),
            targetDurationS = step.durationS,
            actualDistanceM = distanceM,
            targetPaceSPerKm = step.paceSPerKm,
            actualPaceSPerKm = pace,
            toleranceSPerKm = step.toleranceSPerKm,
            durationS = secs,
            status = status,
        )
    }

    companion object {
        const val STATUS_COMPLETED = "completed"
        const val STATUS_SKIPPED = "skipped"

        /// The phone runner's drift-cue spacing.
        const val DRIFT_CUE_INTERVAL_MS = 45_000L
    }
}

/// The three `runs.metadata` keys a run started from a pushed workout carries,
/// for `buildRunMetadata`.
fun WorkoutReview.metadataEntries(): JsonObject = buildJsonObject {
    put("plan_workout_id", planWorkoutId)
    put("workout_step_results", stepResultsJson())
    put("workout_adherence", adherence)
}
