/// Coach-roster injury-risk + load-band classification (coach_roster.md).
///
/// Pure (no Flutter / Supabase) so it stays the single place the
/// acute:chronic-workload-ratio (ACWR) risk policy lives — web, mobile, and
/// the coach_roster_summary RPC's display all classify through this, so the
/// thresholds can't drift. The RPC returns RAW acute (7d) + chronic
/// (28d-avg-per-7d) load sums; this helper turns them into the ratio, the
/// injury-risk band, and the load trend label the roster column shows.
///
/// Dart twin of `apps/web/src/lib/training/coach_load.ts` — keep the
/// algorithm, band edges, and test counts in lockstep.
library;

import 'plan_current.dart';

enum InjuryRiskBand { insufficient, low, optimal, elevated, high }

enum LoadTrend { ramping, steady, tapering }

/// ACWR band edges (the sports-science "sweet spot" model). A ratio in
/// [0.8, 1.3) is the protective optimal zone; below 0.8 is detraining/low;
/// [1.3, 1.5) is elevated; >=1.5 is the high-spike injury-risk zone.
const double acwrLowMax = 0.8;
const double acwrOptimalMax = 1.3;
const double acwrElevatedMax = 1.5;

/// Load-trend edges around 1.0 (acute vs chronic). A ±15% deadband keeps a
/// roughly-steady athlete out of the ramping/tapering labels.
const double trendTaperMax = 0.85;
const double trendRampMin = 1.15;

/// Acute:chronic workload ratio. [chronic28dAvg] is the average weekly load
/// over the trailing 28 days (the RPC's load_chronic). Returns 0 when there is
/// no chronic base to divide by — the band classifier reads that as
/// "insufficient", never a false "low" (ACWR needs ~28 days of history).
double acwr(double acute7d, double chronic28dAvg) {
  if (!acute7d.isFinite || !chronic28dAvg.isFinite) return 0;
  if (chronic28dAvg <= 0) return 0;
  return acute7d / chronic28dAvg;
}

/// Bucket the ratio into an injury-risk band. A zero/negative chronic base (no
/// meaningful history) returns [InjuryRiskBand.insufficient] rather than
/// guessing — the roster shows that honestly instead of a green "low".
InjuryRiskBand injuryRiskBand(double acute7d, double chronic28dAvg) {
  if (!chronic28dAvg.isFinite || chronic28dAvg <= 0) {
    return InjuryRiskBand.insufficient;
  }
  final ratio = acwr(acute7d, chronic28dAvg);
  if (ratio < acwrLowMax) return InjuryRiskBand.low;
  if (ratio < acwrOptimalMax) return InjuryRiskBand.optimal;
  if (ratio < acwrElevatedMax) return InjuryRiskBand.elevated;
  return InjuryRiskBand.high;
}

/// Load-trend label for the roster's load column. ramping when acute load runs
/// >15% above the chronic average, tapering when >15% below, else steady.
/// Falls back to steady when there's no chronic base.
LoadTrend loadTrend(double acute7d, double chronic28dAvg) {
  if (!chronic28dAvg.isFinite || chronic28dAvg <= 0) return LoadTrend.steady;
  final ratio = acwr(acute7d, chronic28dAvg);
  if (ratio <= trendTaperMax) return LoadTrend.tapering;
  if (ratio >= trendRampMin) return LoadTrend.ramping;
  return LoadTrend.steady;
}

/// One of an athlete's recent planned workouts as `coach_roster_summary`
/// returns it in `recent_workouts` — the shape [isWorkoutMissed] takes.
class RosterRecentWorkout {
  const RosterRecentWorkout({
    required this.scheduledDate,
    required this.kind,
    required this.completed,
    required this.skipped,
  });

  final String scheduledDate;
  final String kind;
  final bool completed;
  final bool skipped;

}

/// Read `recent_workouts` off a roster row. An element missing its date or
/// kind drops out instead of failing the whole row; a non-list reads as none.
List<RosterRecentWorkout> parseRosterRecentWorkouts(Object? json) {
  if (json is! List) return const [];
  final out = <RosterRecentWorkout>[];
  for (final e in json) {
    if (e is! Map) continue;
    final date = e['scheduled_date'];
    final kind = e['kind'];
    if (date is! String || kind is! String) continue;
    out.add(RosterRecentWorkout(
      scheduledDate: date,
      kind: kind,
      completed: e['completed'] == true,
      skipped: e['skipped'] == true,
    ));
  }
  return out;
}

/// Consecutive misses at or above which the roster flags the athlete.
const int consecutiveMissFlag = 2;

/// The athlete's current run of missed workouts, counting back from their
/// local yesterday. "Missed" is [isWorkoutMissed] from the plan_current pair,
/// never restated here, so the roster agrees with the athlete's own plan. A
/// done workout ends the run; a skipped one (an intentional change) and a rest
/// day neither count nor end it. Order of [recent] does not matter.
int consecutiveMissedWorkouts(
  List<RosterRecentWorkout> recent,
  String todayIso,
) {
  final past = recent
      .where((w) => w.scheduledDate.compareTo(todayIso) < 0)
      .toList()
    ..sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
  var run = 0;
  for (final w in past) {
    if (isWorkoutMissed(
      scheduledIso: w.scheduledDate,
      kind: w.kind,
      completed: w.completed,
      skipped: w.skipped,
      todayIso: todayIso,
    )) {
      run += 1;
    } else if (w.completed) {
      break;
    }
  }
  return run;
}

/// Easy-run heart-rate drift (per cent) at or above which the roster flags it.
/// The RPC computes it as the change in mean heart rate on the athlete's
/// planned easy runs held within 15 s/km of their median easy pace, recent 14
/// days against the 42 before, only under health-data consent.
const double easyHrDriftFlagPct = 5;

bool isEasyHrDriftFlagged(double? driftPct) =>
    driftPct != null && driftPct.isFinite && driftPct >= easyHrDriftFlagPct;
