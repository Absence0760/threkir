import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/fitness.dart' show qualifyingRuns;
import '../../lib/hr_zones.dart' show bpmStatsOf;
import '../../lib/l10n/gen/app_localizations.dart';
import '../../lib/l10n/locale_support.dart' show activeLocaleTag;
import '../../lib/l10n/number_format.dart' show formatFixed;
import '../../lib/pace_analysis.dart';
import '../../lib/preferences.dart' show UnitFormat, formatDistanceForPref;
import '../../lib/race_predictor.dart';
import '../../lib/run_altitude.dart';
import '../../lib/run_stats.dart';
import '../../lib/training.dart' show PredictionConfidence, fmtHms;
import '../../lib/training_service.dart';
import '../../lib/widgets/race_predictor_card.dart' show raceLadderSlug;
import 'store_capture_kit.dart';
import 'store_selectors.dart';

/// numbers.json (assets/store/README.md): the numbers the panels' captions
/// may quote, as the app formats them on screen.
///
/// Every display string is read off the screen being captured, so a caption
/// can only repeat what its crop shows. Each one is also recomputed through
/// the helpers the screen itself calls (the run detail's split, pacing and
/// grade-adjusted helpers, the Progress predictor's ladder, the plan row),
/// which supplies what the screen does not print (a split's climb, a pacing
/// verdict, a confidence grade) and fails the capture if the two disagree:
/// a mismatch means these numbers are not the screen's.

/// Read while the run-splits capture is on screen: every split row, the
/// pacing card and the grade-adjusted column.
Map<String, Object?> splitNumbers(
    WidgetTester tester, Run run, AppLocalizations l10n) {
  final splits = computeSplitDurations(run.track, 1000, run.startedAt,
      totalDistanceMetres: splitAxisTotalMetres(run.source, run.distanceMetres));
  final altitude = runAltitude(run.track, run.source).track;
  final gap =
      gradeAdjustedSplitPaces(altitude, List.filled(splits.length, 1000.0));
  final rows = <Map<String, Object?>>[];
  for (var i = 0; i < splits.length; i++) {
    final km = i + 1;
    final row = StoreSelectors.splitRow(km);
    if (row.evaluate().isEmpty) {
      fail('split row $km is not on screen; the demo account must show '
          'kilometres, and every row must fit the run-splits capture');
    }
    // tick, bar label (raw pace), duration, grade-adjusted pace.
    final texts = textsUnder(tester, row);
    if (texts.length != 4 || texts[0] != '$km') {
      fail('split row $km reads $texts; expected its km, raw pace, '
          'duration and grade-adjusted pace');
    }
    final raw = UnitFormat.pace(
        splits[i].duration.inSeconds.toDouble(), DistanceUnit.km);
    final g = gap[i];
    final gapText =
        g == null ? null : UnitFormat.pace(g.toDouble(), DistanceUnit.km);
    if (texts[1] != raw || texts[3] != gapText) {
      fail('split row $km shows ${texts[1]} / ${texts[3]}, the run detail '
          'helpers give $raw / $gapText');
    }
    final climb = splits[i].elevationMetres;
    if (climb == null) fail('split $km carries no elevation');
    rows.add({
      'km': km,
      'raw': texts[1],
      'gap': texts[3],
      'elev_delta_m': climb.toDouble(),
    });
  }
  if (StoreSelectors.splitRow(splits.length + 1).evaluate().isNotEmpty) {
    fail('the screen shows more split rows than the helpers compute');
  }
  var slowest = 0;
  for (var i = 1; i < splits.length; i++) {
    if (splits[i].duration > splits[slowest].duration) slowest = i;
  }

  final pacing = analysePacing(altitude);
  if (pacing == null || pacing.gradeAdjusted == null) {
    fail('the hero run has no grade-adjusted pacing analysis');
  }
  final first =
      UnitFormat.pace(pacing.raw.first.paceSecPerKm.toDouble(), DistanceUnit.km);
  final second = UnitFormat.pace(
      pacing.raw.second.paceSecPerKm.toDouble(), DistanceUnit.km);
  final card = textsUnder(tester, StoreSelectors.pacingCard);
  if (!card.contains(first) || !card.contains(second)) {
    fail('the pacing card reads $card; the helpers give halves '
        '$first and $second');
  }
  final ga = pacing.gradeAdjusted!;
  return {
    'splits': rows,
    'slowest_km': slowest + 1,
    'pacing': {
      'raw': {
        'first': first,
        'second': second,
        'delta_s': pacing.raw.deltaSecPerKm,
        'verdict': pacing.raw.verdict.name,
      },
      'grade_adjusted': {
        'delta_s': ga.deltaSecPerKm,
        'verdict': ga.verdict.name,
      },
    },
  };
}

/// Read while the run-zones capture is on screen: the heart-rate row and
/// each zone's legend line.
Map<String, Object?> zoneNumbers(
    WidgetTester tester, Run run, AppLocalizations l10n) {
  final stats = bpmStatsOf(run.track);
  if (stats == null) fail('the hero run carries no heart rate');
  final avg = '${stats.avg} ${l10n.runUnitBpm}';
  if (find.textContaining(avg, findRichText: true).evaluate().isEmpty) {
    fail('the heart-rate row does not read $avg');
  }
  final zones = <Map<String, Object?>>[];
  for (var zone = 1; zone <= 5; zone++) {
    final row = StoreSelectors.hrZoneRow(zone);
    if (row.evaluate().isEmpty) fail('zone $zone has no legend line');
    // label, time in zone, share.
    final texts = textsUnder(tester, row);
    if (texts.length != 3 || !texts[2].endsWith('%')) {
      fail('zone $zone reads $texts; expected label, time and share');
    }
    zones.add({
      'zone': zone,
      'label': texts[0],
      'time': texts[1],
      'pct': int.parse(texts[2].substring(0, texts[2].length - 1)),
    });
  }
  return {
    'hr': {'avg': stats.avg, 'min': stats.min, 'max': stats.max},
    'zones': zones,
  };
}

/// Read while the progress capture is on screen: the predictor's rungs, fed
/// the runs and clock the Progress page feeds its card.
Map<String, Object?> predictorNumbers(WidgetTester tester, List<Run> runs,
    DateTime now, AppLocalizations l10n) {
  final ladder = predictRaceLadder([
    for (final r in qualifyingRuns(runs))
      EffortForPrediction(
        distanceM: r.distanceMetres,
        durationS: r.duration.inSeconds,
        ageDays: (now.difference(r.startedAt).inMilliseconds / 86400000)
            .clamp(0, double.infinity),
      ),
  ]);
  if (ladder == null) fail('the demo runs give the predictor no anchor');
  final labels = {
    PredictionConfidence.high: l10n.racePredictorConfidenceHigh,
    PredictionConfidence.moderate: l10n.racePredictorConfidenceModerate,
    PredictionConfidence.low: l10n.racePredictorConfidenceLow,
  };
  final rungs = <String, Object?>{};
  for (final rung in ladder.rungs) {
    final name = raceLadderSlug(rung.distanceM);
    final row = StoreSelectors.predictorRow(rung.distanceM);
    if (row.evaluate().isEmpty) fail('the predictor has no $name row');
    // distance, time, pace, confidence chip.
    final texts = textsUnder(tester, row);
    final time = clock(rung.predictedSec);
    if (texts.length != 4 ||
        texts[1] != time ||
        texts[3] != labels[rung.quality.confidence]) {
      fail('the $name row reads $texts; the ladder gives $time, '
          '${labels[rung.quality.confidence]}');
    }
    rungs[name] = {
      'distance': texts[0],
      'time': texts[1],
      'pace': texts[2],
      'confidence': rung.quality.confidence.name,
      'confidence_label': texts[3],
    };
  }
  return {
    'anchor': {
      'distance': formatDistanceForPref(ladder.anchor.distanceM),
      'time': clock(ladder.anchor.durationS.toDouble()),
    },
    'rungs': rungs,
  };
}

/// Read while the plan capture is on screen: the plan row behind the header
/// card, checked against the chips the card shows.
Future<Map<String, Object?>> planNumbers(
    WidgetTester tester, TrainingService training, String planId) async {
  final detail = await training.fetchPlan(planId);
  final p = detail.plan;
  if (p == null) fail('the demo plan $planId did not load');
  final goalS = p.goalTimeSeconds;
  final distance = p.goalDistanceM;
  final vdot = p.vdot;
  if (goalS == null || vdot == null) {
    fail('the demo plan has no goal time or VDOT');
  }
  final goal = fmtHms(goalS);
  final vdotText = formatFixed(vdot, 1, activeLocaleTag);
  final header = textsUnder(tester, StoreSelectors.planHeroCard).join(' | ');
  if (!header.contains(goal) || !header.contains(vdotText)) {
    fail('the plan header reads "$header"; the plan row gives $goal and '
        'VDOT $vdotText');
  }
  return {
    'weeks': detail.weeks.length,
    'goal': goal,
    'goal_distance_m': distance,
    'vdot': vdotText,
    'race_name': p.name,
  };
}

/// MM:SS or H:MM:SS, as the predictor card prints a time.
String clock(double seconds) {
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
