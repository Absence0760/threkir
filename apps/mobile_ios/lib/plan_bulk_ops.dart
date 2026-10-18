/// Pure helpers behind the plan bulk operations on plan detail: shifting a
/// date by N days, and turning a week into a recovery (step-back) week. Web
/// twin: `apps/web/src/lib/training/plan_bulk_ops.ts`.
library;

/// A recovery week drops volume + intensity to ~60% of the planned load.
const double kRecoveryScale = 0.6;

/// Shift an ISO `YYYY-MM-DD` date by [days] (may be negative). UTC math so
/// it never drifts across a local-midnight / DST boundary.
String shiftIsoDate(String iso, int days) {
  final parts = iso.split('-').map(int.parse).toList();
  final out = DateTime.utc(parts[0], parts[1], parts[2] + days);
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${out.year}-${pad(out.month)}-${pad(out.day)}';
}

/// Kinds that carry quality intensity — converted to `recovery` when a week
/// is marked as a down week. Easy / long / walk-run keep their kind (just
/// scaled); rest + race are left untouched entirely.
const _qualityKinds = {'tempo', 'interval', 'marathon_pace'};

/// The patch to apply to one workout when its week is marked as recovery,
/// as a `plan_workouts` field map. Null for workouts that shouldn't change
/// (`rest`, `race`). Quality kinds become `recovery` with their strict pace
/// target and interval structure cleared — the structure is what the runner
/// executes, so a "Recovery" workout that kept it still ran the full session.
Map<String, Object?>? recoveryWorkoutPatch(String kind, num? targetDistanceM) {
  if (kind == 'rest' || kind == 'race') return null;
  final patch = <String, Object?>{};
  if (_qualityKinds.contains(kind)) {
    patch['kind'] = 'recovery';
    patch['target_pace_sec_per_km'] = null;
    patch['target_pace_tolerance_sec'] = null;
    patch['structure'] = null;
  }
  if (targetDistanceM != null) {
    patch['target_distance_m'] = (targetDistanceM * kRecoveryScale).round();
  }
  return patch.isEmpty ? null : patch;
}

/// New target volume for a week marked as recovery.
int? recoveryWeekVolume(num? targetVolumeM) =>
    targetVolumeM == null ? null : (targetVolumeM * kRecoveryScale).round();
