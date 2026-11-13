/// The inputs Home's Today and the Progress page both read, so the readiness
/// line on Today and the load card on Progress score the same series
/// (decisions § 109). Each takes the stores rather than a screen, so neither
/// page keeps a copy of the other's rules.
library;

import 'package:api_client/api_client.dart' show SettingsKeys;
import 'package:core_models/core_models.dart';

import 'lift_load.dart';
import 'local_gym_store.dart';
import 'settings_sync.dart';
import 'training.dart' show toIsoDate;
import 'training_load.dart';
import 'training_service.dart';
import 'week_lead.dart';

/// The runner's resting and max HR, the one model every load surface scores
/// on.
HrPrefs hrPrefsOf(SettingsSyncService? settingsSync) => HrPrefs(
      restingHrBpm:
          settingsSync?.service?.effective<num>(SettingsKeys.restingHrBpm),
      maxHrBpm: settingsSync?.service?.effective<num>(SettingsKeys.maxHrBpm),
    );

/// The Settings → Preferences opt-out: a runner who wants a pure run-only
/// readiness curve drops gym load from the fitness / fatigue / form math.
bool excludesGymFromReadiness(SettingsSyncService? settingsSync) =>
    settingsSync?.service
        ?.effective<bool>(SettingsKeys.excludeGymFromReadiness) ==
    true;

/// Logged gym sessions reduced to the load-model input. Empty for a pure
/// runner, so the curve is the unchanged run-only series (multi_modal.md
/// Tier-1 lift→load).
List<LiftForLoad> liftsForLoad(LocalGymStore gymStore) {
  final flat = <SetWithWorkoutDate>[];
  for (final w in gymStore.workouts) {
    if (w.isTombstone) continue;
    final at = w.startedAt;
    if (at == null) continue;
    final iso = at.toUtc().toIso8601String();
    for (final s in w.sets) {
      flat.add(SetWithWorkoutDate(
        workoutId: w.id,
        startedAt: iso,
        reps: s['reps'] as num?,
        weightKg: s['weight_kg'] as num?,
        rpe: s['rpe'] as num?,
      ));
    }
  }
  return liftsFromSetHistory(flat);
}

/// The ONE training-load series a page reads, computed once per build with
/// the lift set the opt-out decides, so the readiness score, the fitness
/// snapshot and the plotted curve can't disagree.
List<TrainingLoadPoint> trainingLoadSeriesFor(
  List<Run> runs,
  DateTime now, {
  required LocalGymStore gymStore,
  required SettingsSyncService? settingsSync,
}) =>
    computeTrainingLoadSeries(
      runs,
      prefs: hrPrefsOf(settingsSync),
      endDate: now,
      lifts: excludesGymFromReadiness(settingsSync)
          ? const []
          : liftsForLoad(gymStore),
    );

/// The runner's week start, `monday` unless the bag says otherwise.
String weekStartDayOf(SettingsSyncService? settingsSync) =>
    settingsSync?.service?.effective<String>(SettingsKeys.weekStartDay) ??
    'monday';

/// The active plan's workouts in the shape the week lead and the goals both
/// read, or null without an active plan.
List<LeadPlanWorkout>? leadPlanWorkoutsOf(ActivePlanOverview? plan) =>
    plan == null
        ? null
        : [
            for (final w in plan.workouts)
              LeadPlanWorkout(
                id: w.id,
                scheduledDate: toIsoDate(w.scheduledDate),
                kind: w.kind,
                targetDistanceM: w.targetDistanceM,
                manuallyCompleted: w.manuallyCompleted,
                completedRunId: w.completedRunId,
                skippedAt: w.skippedAt?.toIso8601String(),
                targetDurationSeconds: w.targetDurationSeconds,
                structure: w.structure,
              ),
          ];
