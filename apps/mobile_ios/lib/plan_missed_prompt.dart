/// The Today card's "ask once" about a missed workout (decisions § 2122).
/// Pure: which miss to ask about, what the engine advises for it, and the
/// make-up the runner previews when the advice is to make it up. It adds no
/// rule of its own: "missed" is plan_current's [isWorkoutMissed], the advice is
/// plan_adherence's [missedWorkoutAdvice], and the make-up is plan_replan's
/// stretched next long run. Web twin
/// `apps/web/src/lib/training/plan_missed_prompt.ts`.
library;

import 'plan_adherence.dart';
import 'plan_current.dart';
import 'plan_replan.dart';

/// Only a miss from the last week is asked about. An older one has already
/// slipped past the week it belonged to, and asking about it would read as a
/// reproach rather than a decision still worth making.
const int missedPromptWindowDays = 7;

const Set<String> _taperPhases = {'taper', 'race'};

class MissedPromptWorkout {
  final String id;

  /// ISO scheduled date (YYYY-MM-DD).
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;
  final bool completed;
  final bool skipped;

  /// The runner already answered the prompt for this workout
  /// (`plan_workouts.missed_ack_at`).
  final bool answered;

  const MissedPromptWorkout({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    this.completed = false,
    this.skipped = false,
    this.answered = false,
  });
}

class MissedPromptWeek {
  final int weekIndex;
  final String phase;
  final double plannedMetres;
  final List<MissedPromptWorkout> workouts;

  const MissedPromptWeek({
    required this.weekIndex,
    required this.phase,
    required this.plannedMetres,
    required this.workouts,
  });
}

class MissedPrompt {
  final String workoutId;
  final String scheduledDate;
  final String kind;
  final MissedWorkoutAdvice advice;

  /// The stretched next long run the runner previews. Null when the advice is
  /// to let it go, or when no later long run is short of the miss.
  final ReplanChange? makeUp;

  /// Every unanswered missed long run the make-up honours. They are answered
  /// together with it, so none of them is asked about, or made up, again.
  final List<String> makeUpAnswers;

  const MissedPrompt({
    required this.workoutId,
    required this.scheduledDate,
    required this.kind,
    required this.advice,
    this.makeUp,
    this.makeUpAnswers = const [],
  });
}

String _isoMinusDays(String iso, int days) {
  final d = DateTime.parse('${iso}T00:00:00Z');
  return DateTime.utc(d.year, d.month, d.day - days)
      .toIso8601String()
      .substring(0, 10);
}

bool _missed(MissedPromptWorkout wo, String today) => isWorkoutMissed(
      scheduledIso: wo.scheduledDate,
      kind: wo.kind,
      completed: wo.completed,
      skipped: wo.skipped,
      todayIso: today,
    );

/// The most recent unanswered miss from the last [windowDays] days, or null.
/// Two misses on one day keep the earlier in plan order.
MissedPrompt? missedWorkoutPrompt({
  required List<MissedPromptWeek> weeks,

  /// The runner's local today (YYYY-MM-DD).
  required String today,
  int windowDays = missedPromptWindowDays,
}) {
  final windowStart = _isoMinusDays(today, windowDays);
  final sorted = [...weeks]..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  final replanWeeks = [
    for (final w in sorted)
      ReplanWeek(
        weekIndex: w.weekIndex,
        phase: w.phase,
        plannedMetres: w.plannedMetres,
        actualMetres: 0,
        isComplete: false,
        workouts: const [],
      ),
  ];

  MissedPromptWorkout? pick;
  var pickIdx = -1;
  for (var i = 0; i < sorted.length; i++) {
    for (final wo in sorted[i].workouts) {
      if (wo.answered ||
          wo.scheduledDate.compareTo(windowStart) < 0 ||
          !_missed(wo, today)) {
        continue;
      }
      if (pick == null || wo.scheduledDate.compareTo(pick.scheduledDate) > 0) {
        pick = wo;
        pickIdx = i;
      }
    }
  }
  if (pick == null) return null;

  MissedWorkoutAdvice adviceFor(String kind, int idx) =>
      missedWorkoutAdvice(MissedWorkoutInput(
        kind: kind,
        isTaper: _taperPhases.contains(sorted[idx].phase),
        recoveryWeekImminent: recoveryWeekImminent(replanWeeks, idx),
      ));
  final advice = adviceFor(pick.kind, pickIdx);
  final result = MissedPrompt(
    workoutId: pick.id,
    scheduledDate: pick.scheduledDate,
    kind: pick.kind,
    advice: advice,
  );
  if (advice.recommendation != MakeUpRecommendation.makeUp) return result;

  // An answered miss is off the books for the make-up, as a skipped one is:
  // the runner already let it go, or already made it up.
  final res = replanRemaining(
    weeks: [
      for (var i = 0; i < sorted.length; i++)
        ReplanWeek(
          weekIndex: replanWeeks[i].weekIndex,
          phase: replanWeeks[i].phase,
          plannedMetres: replanWeeks[i].plannedMetres,
          actualMetres: 0,
          isComplete: false,
          workouts: [
            for (final wo in sorted[i].workouts)
              ReplanWorkout(
                id: wo.id,
                scheduledDate: wo.scheduledDate,
                kind: wo.kind,
                targetDistanceM: wo.targetDistanceM,
                completed: wo.completed,
                skipped: wo.skipped || wo.answered,
                isPast: wo.scheduledDate.compareTo(today) < 0,
              ),
          ],
        ),
    ],
    today: today,
  );
  ReplanChange? makeUp;
  for (final c in res.changes) {
    if (c.reason == ReplanReason.makeUpLong) {
      makeUp = c;
      break;
    }
  }
  if (makeUp == null) return result;

  final answers = <String>[];
  for (var i = 0; i < sorted.length; i++) {
    for (final wo in sorted[i].workouts) {
      if (wo.kind != 'long' || wo.answered || !_missed(wo, today)) continue;
      if (adviceFor('long', i).recommendation == MakeUpRecommendation.makeUp) {
        answers.add(wo.id);
      }
    }
  }
  return MissedPrompt(
    workoutId: result.workoutId,
    scheduledDate: result.scheduledDate,
    kind: result.kind,
    advice: advice,
    makeUp: makeUp,
    makeUpAnswers: answers,
  );
}
