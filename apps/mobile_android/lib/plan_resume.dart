/// What resuming a paused plan should offer (issue #1186): push the weeks that
/// had not started when the runner paused back by the whole weeks the plan sat
/// paused, so it picks up again next week instead of coming back as missed.
///
/// The week the runner paused in stays (it may hold work they did), and week 0
/// never moves because it is anchored on the start date. `resume_training_plan`
/// applies the result in one transaction.
///
/// Dart twin of `apps/web/src/lib/training/plan_resume.ts`.
library;

import 'cycle_plan.dart' show daysBetweenIso;

const int kResumeMaxShiftWeeks = 52;

class ResumeShift {
  /// The first week index to move.
  final int fromWeekIndex;

  /// How many whole weeks it and every later week move.
  final int weeks;

  const ResumeShift({required this.fromWeekIndex, required this.weeks});

  @override
  bool operator ==(Object other) =>
      other is ResumeShift &&
      other.fromWeekIndex == fromWeekIndex &&
      other.weeks == weeks;

  @override
  int get hashCode => Object.hash(fromWeekIndex, weeks);

  @override
  String toString() => 'ResumeShift(from: $fromWeekIndex, weeks: $weeks)';
}

/// The shift a resume on [todayIso] should offer for a plan that started on
/// [startIso], has [weekCount] weeks and was paused on [pausedOnIso] (all the
/// runner's local dates), or null when there is nothing to push back: paused
/// and resumed in the same plan week, paused before the plan started, paused
/// in its last week, or a pause date we do not know or cannot read.
ResumeShift? resumeShift({
  required String startIso,
  required String? pausedOnIso,
  required String todayIso,
  required int weekCount,
}) {
  if (pausedOnIso == null || pausedOnIso.isEmpty) return null;
  final toPause = daysBetweenIso(startIso, pausedOnIso);
  final toToday = daysBetweenIso(startIso, todayIso);
  if (toPause == null || toToday == null) return null;
  final pausedWeek = (toPause / 7).floor();
  final todayWeek = (toToday / 7).floor();
  if (pausedWeek < 0) return null;
  final fromWeekIndex = pausedWeek + 1;
  final elapsed = todayWeek - pausedWeek;
  final weeks = elapsed > kResumeMaxShiftWeeks ? kResumeMaxShiftWeeks : elapsed;
  if (weeks < 1 || fromWeekIndex >= weekCount) return null;
  return ResumeShift(fromWeekIndex: fromWeekIndex, weeks: weeks);
}
