/// Anchor the weeks ahead to what the runner actually ran (issue #1186,
/// "a niggle week gets no real response").
///
/// [replanRemaining] reacts to a missed long run and to over-running, but a
/// week that came in well short changes nothing ahead of it: the plan carries
/// on up its nominal ramp, so the week after a niggle asks for more than the
/// week the runner could not finish. A coach answers that week by building
/// back from what was run, at about 10% a week, until the plan's own weeks
/// fit again. That is this module.
///
/// Distance only: it reads planned and actual weekly volume and nothing
/// derived from heart rate or training load. It still ships behind
/// `ADAPTIVE_FITNESS_GATE` (decisions § 2090, § 144 / § 150), because it
/// rewrites the weeks ahead from what was run, which is the second-wave
/// prescription work that sign-off covers. The gate is the caller's: Home and
/// the plan screen call this only while it is on.
///
/// The rules:
///  - It speaks when the last completed week ran under plan ([weeklyDrift]'s
///    20% band, against the smaller of the week's target and what its
///    sessions prescribe, so a week already anchored and run as prescribed is
///    not short), or when the runner has been away from the plan for
///    [kLayoffMinDays] or more: a resumed or rescheduled plan whose skipped
///    weeks are a layoff, whether or not the week before it was on target.
///  - The anchor is the most recent completed week with any running in it. A
///    week with none is a break, not a level, and a plan with no such week has
///    no evidence of the runner's level, so it proposes nothing.
///  - The first week ahead may ask for at most 10% over the anchor; after a
///    layoff, at most [kReturnWeekShare] of it, the wizard's returning-runner
///    opening (decisions § 2090). Each later week may ask for at most 10% over
///    the most any week since prescribes, so a step-back week holds the climb.
///  - Only future, undone, unskipped, distance-targeted sessions shrink, all by
///    one factor so the week keeps its shape, down to the 100 m. None goes
///    below the generator's 3 km easy floor, and one already at or under it is
///    left alone. Done sessions count toward their week as prescribed; missed
///    ones count nothing. Rest and race sessions are never counted or touched.
///  - The climb stops at the first taper or race week. The taper is sacred,
///    exactly as in [replanRemaining].
///
/// It returns proposals in the re-plan engine's own [ReplanChange] shape, so
/// they go through the same preview and the same `apply_workout_adjustments`
/// write as every other re-plan.
///
/// Dart twin of `apps/web/src/lib/training/plan_volume_anchor.ts` — keep in
/// lockstep (TS↔Dart parity pair, equal test counts).
library;

import 'dart:math' as math;

import 'comeback.dart' show kLayoffMinDays, kReturnWeekShare, kReturnWeeklyGrowth;
import 'plan_adherence.dart' show DriftDirection, weeklyDrift;
import 'plan_replan.dart';
import 'training.dart' show kEasyRunFloorKm;

const _taperPhases = {'taper', 'race'};
const double _floorM = kEasyRunFloorKm * 1000.0;

class VolumeAnchor {
  final List<ReplanChange> changes;

  /// The completed week whose running the climb starts from.
  final int anchorWeekIndex;

  /// What the runner ran in that week, metres.
  final double anchorMetres;

  /// Plan weeks between the anchor week and the weeks ahead: completed weeks
  /// with no running, plus weeks a resume skipped over.
  final int idleWeeks;

  /// The idle stretch is a layoff, so the climb restarts from
  /// [kReturnWeekShare] of the anchor rather than from the anchor itself.
  final bool returning;

  const VolumeAnchor({
    required this.changes,
    required this.anchorWeekIndex,
    required this.anchorMetres,
    required this.idleWeeks,
    required this.returning,
  });
}

bool _isFixed(String kind) => kind == 'rest' || kind == 'race';

/// What a completed week asked for: its target, or less when its sessions
/// add up to less (the anchor lowers sessions, never the week's target).
double _prescribedMetres(ReplanWeek week) {
  var sessions = 0.0;
  for (final wo in week.workouts) {
    if (wo.kind != 'rest') sessions += wo.targetDistanceM ?? 0;
  }
  return sessions > 0 ? math.min(week.plannedMetres, sessions) : week.plannedMetres;
}

/// The proposal, or null when nothing ahead needs to change.
VolumeAnchor? anchorToActualVolume({required List<ReplanWeek> weeks}) {
  final sorted = [...weeks]..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  final completed = sorted.where((w) => w.isComplete).toList();
  if (completed.isEmpty) return null;
  final lastComplete = completed.last;
  final ahead =
      sorted.where((w) => w.weekIndex > lastComplete.weekIndex).toList();
  if (ahead.isEmpty) return null;
  ReplanWeek? anchor;
  for (final w in completed.reversed) {
    if (w.actualMetres > 0) {
      anchor = w;
      break;
    }
  }
  if (anchor == null) return null;

  final idleWeeks = ahead.first.weekIndex - anchor.weekIndex - 1;
  final returning = idleWeeks * 7 >= kLayoffMinDays;
  final under = weeklyDrift(
              _prescribedMetres(lastComplete), lastComplete.actualMetres)
          .direction ==
      DriftDirection.under;
  if (!under && !returning) return null;

  final changes = <ReplanChange>[];
  // The level the climb resumes from: what was run, or the return share of
  // it after a layoff, which is itself the first week's cap. Every cap after
  // grows from the most any week since prescribes, so an empty or step-back
  // week ahead holds the climb rather than lowering it.
  var highest =
      returning ? anchor.actualMetres * kReturnWeekShare : anchor.actualMetres;
  var cap = returning ? highest : highest * kReturnWeeklyGrowth;
  for (final week in ahead) {
    if (_taperPhases.contains(week.phase)) break;

    var fixed = 0.0;
    var adjustableM = 0.0;
    final adjustable = <ReplanWorkout>[];
    for (final wo in week.workouts) {
      if (_isFixed(wo.kind) || wo.skipped) continue;
      final target = wo.targetDistanceM ?? 0;
      if (!(target > 0)) continue;
      if (wo.completed) {
        fixed += target;
      } else if (wo.isPast) {
        continue;
      } else {
        adjustable.add(wo);
        adjustableM += target;
      }
    }

    var prescribed = fixed + adjustableM;
    if (prescribed > cap && adjustableM > 0) {
      final factor = math.max(0.0, cap - fixed) / adjustableM;
      prescribed = fixed;
      for (final wo in adjustable) {
        final target = wo.targetDistanceM!;
        final next = target <= _floorM
            ? target
            : math.max(_floorM, ((target * factor) / 100).floorToDouble() * 100);
        prescribed += next;
        if (next < target) {
          changes.add(ReplanChange(
            workoutId: wo.id,
            scheduledDate: wo.scheduledDate,
            reason: ReplanReason.anchorActualVolume,
            fromMetres: target,
            toMetres: next,
          ));
        }
      }
    }
    highest = math.max(highest, prescribed);
    cap = highest * kReturnWeeklyGrowth;
  }

  if (changes.isEmpty) return null;
  return VolumeAnchor(
    changes: changes,
    anchorWeekIndex: anchor.weekIndex,
    anchorMetres: anchor.actualMetres,
    idleWeeks: idleWeeks,
    returning: returning,
  );
}

/// An under-run week is answered by the anchor alone. A make-up stretch or
/// any other proposal beside it would push the capped weeks back up, so when
/// the anchor has something to say, nothing else is proposed with it.
List<ReplanChange> preferVolumeAnchor(
  VolumeAnchor? anchor,
  List<ReplanChange> otherwise,
) =>
    anchor != null ? anchor.changes : otherwise;
