/// What a race on the calendar hands the plan builder: the chained start floor
/// when the runner already has a plan ending before this race, the goal time
/// they set for it, and the description the AI plan box is prefilled with.
///
/// Pure logic, no Supabase / auth.
///
/// TS twin: apps/web/src/lib/training/race_plan_prefill.ts (parity pair — keep
/// the selection rules, text, cap and test counts in lockstep). Web's
/// `racePlanHref` has no twin: the phone opens `PlanNewScreen` with the same
/// fields as constructor arguments.
///
/// The description is English and metric on purpose: it is a machine-read
/// request to the plan extractor, like the Coach's own handoff, not UI copy.
/// It carries only what the AI plan consent bullet names — the goal race, a
/// target time and a recent time. Weekly volume and the longest recent run are
/// deliberately left out: the bullet does not cover them (decisions § 2154).
library;

import 'race_plan_preset.dart';
import 'season_plan.dart' show seasonRecoveryDays;

/// The AI plan box's own maxlength.
const int kRacePlanDescribeMax = 600;

/// A listing name longer than this is cut, so the race always fits the cap.
const int kRacePlanDescribeNameMax = 120;
const int kRacePlanSurfaceMax = 40;

const int _dayMs = 86400000;

class RacePlanRace {
  final String name;
  final String raceDateIso;
  final num? distanceM;

  const RacePlanRace({
    required this.name,
    required this.raceDateIso,
    this.distanceM,
  });
}

class RacePlanCourse {
  final num? ascentM;
  final num? descentM;
  final String? surface;

  const RacePlanCourse({this.ascentM, this.descentM, this.surface});
}

class RacePlanEffort {
  final num distanceM;
  final num durationS;
  final num ageDays;

  const RacePlanEffort({
    required this.distanceM,
    required this.durationS,
    required this.ageDays,
  });
}

class RacePlanOwnPlan {
  final String id;
  final String name;
  final String status;
  final String endDateIso;
  final num? goalDistanceM;
  final num? goalTimeSeconds;

  const RacePlanOwnPlan({
    required this.id,
    required this.name,
    required this.status,
    required this.endDateIso,
    this.goalDistanceM,
    this.goalTimeSeconds,
  });
}

class RacePlanChain {
  final String planId;
  final String planName;
  final String planEndIso;
  final int recoveryDays;

  /// The first day the new plan may start: the day after the earlier plan
  /// ends plus its race's recovery days.
  final String notBeforeIso;

  const RacePlanChain({
    required this.planId,
    required this.planName,
    required this.planEndIso,
    required this.recoveryDays,
    required this.notBeforeIso,
  });
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

int? _epochDay(String iso) {
  if (!_isoDate.hasMatch(iso)) return null;
  final y = int.parse(iso.substring(0, 4));
  final m = int.parse(iso.substring(5, 7));
  final d = int.parse(iso.substring(8, 10));
  final dt = DateTime.utc(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) return null;
  return dt.millisecondsSinceEpoch ~/ _dayMs;
}

String _isoFromEpochDay(int day) {
  final d = DateTime.fromMillisecondsSinceEpoch(day * _dayMs, isUtc: true);
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${pad(d.month)}-${pad(d.day)}';
}

/// The plan this race should be chained after, or null when none applies.
///
/// Candidates are the runner's active plans ending before race day; the
/// latest ending one is the block this race follows. Null when the recovery
/// floor is already behind today (nothing to avoid) or when a plan cannot be
/// built for the race from that floor, so "Add to my season" is only ever
/// offered when it can succeed.
RacePlanChain? racePlanChain(
  List<RacePlanOwnPlan> plans,
  RacePlanRace race,
  String todayIso,
) {
  final raceDay = _epochDay(race.raceDateIso);
  final today = _epochDay(todayIso);
  if (raceDay == null || today == null) return null;
  RacePlanOwnPlan? bestPlan;
  var bestEnd = 0;
  for (final p in plans) {
    if (p.status != 'active') continue;
    final end = _epochDay(p.endDateIso);
    if (end == null || end >= raceDay) continue;
    if (bestPlan == null || end > bestEnd) {
      bestPlan = p;
      bestEnd = end;
    }
  }
  if (bestPlan == null) return null;
  final recoveryDays =
      seasonRecoveryDays((bestPlan.goalDistanceM ?? 0).toDouble());
  final floor = bestEnd + 1 + recoveryDays;
  if (floor <= today) return null;
  final notBeforeIso = _isoFromEpochDay(floor);
  final preset = racePlanPreset(
    raceDateIso: race.raceDateIso,
    distanceM: race.distanceM,
    todayIso: todayIso,
    notBeforeIso: notBeforeIso,
  );
  if (!preset.ok) return null;
  return RacePlanChain(
    planId: bestPlan.id,
    planName: bestPlan.name,
    planEndIso: bestPlan.endDateIso,
    recoveryDays: recoveryDays,
    notBeforeIso: notBeforeIso,
  );
}

/// The goal time the runner set for this race: an active plan of theirs that
/// ends on race day and carries one. The first such plan wins.
int? racePlanGoalTimeS(List<RacePlanOwnPlan> plans, String raceDateIso) {
  for (final p in plans) {
    if (p.status != 'active' || p.endDateIso != raceDateIso) continue;
    final t = p.goalTimeSeconds;
    if (_positive(t)) return t!.round();
  }
  return null;
}

String _kmText(num metres) {
  final tenths = (metres / 100).round();
  final whole = tenths ~/ 10;
  final frac = tenths % 10;
  return frac == 0 ? '$whole' : '$whole.$frac';
}

String _clockText(num totalS) {
  final s = totalS.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String pad(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${pad(m)}:${pad(sec)}' : '$m:${pad(sec)}';
}

bool _positive(num? n) => n != null && n.isFinite && n > 0;

String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _cut(String text, int max) =>
    text.length > max ? text.substring(0, max) : text;

/// The AI plan box's description for a race, at most `maxChars` long.
///
/// Built from sentences in priority order — race and date, distance, goal,
/// recent fitness, course — and a sentence that would overflow the cap is
/// dropped whole, along with everything after it, so the text is
/// deterministic and never ends mid-word. The race sentence always fits
/// because the name is cut to [kRacePlanDescribeNameMax] first.
String racePlanDescribe({
  required RacePlanRace race,
  num? goalTimeS,
  RacePlanEffort? recentEffort,
  RacePlanCourse? course,
  int maxChars = kRacePlanDescribeMax,
}) {
  final name = _cut(_collapse(race.name), kRacePlanDescribeNameMax).trim();
  final sentences = <String>['Race: $name on ${race.raceDateIso}.'];
  if (_positive(race.distanceM)) {
    sentences.add('Distance: ${_kmText(race.distanceM!)} km.');
  }
  if (_positive(goalTimeS)) {
    sentences.add('Goal time: ${_clockText(goalTimeS!)}.');
  }
  final e = recentEffort;
  if (e != null &&
      _positive(e.distanceM) &&
      _positive(e.durationS) &&
      e.ageDays.isFinite) {
    final days = e.ageDays.round() < 0 ? 0 : e.ageDays.round();
    final when = days == 0
        ? 'today'
        : days == 1
            ? '1 day ago'
            : '$days days ago';
    sentences.add(
        'Recent effort: ${_kmText(e.distanceM)} km in ${_clockText(e.durationS)}, $when.');
  }
  final c = course;
  if (c != null) {
    final parts = <String>[];
    if (_positive(c.ascentM)) parts.add('${c.ascentM!.round()} m ascent');
    if (_positive(c.descentM)) parts.add('${c.descentM!.round()} m descent');
    final surface = c.surface == null
        ? ''
        : _cut(_collapse(c.surface!), kRacePlanSurfaceMax).trim();
    if (surface.isNotEmpty) parts.add('$surface surface');
    if (parts.isNotEmpty) sentences.add('Course: ${parts.join(', ')}.');
  }
  var out = _cut(sentences.first, maxChars);
  for (final s in sentences.skip(1)) {
    if (out.length + 1 + s.length > maxChars) break;
    out = '$out $s';
  }
  return out;
}
