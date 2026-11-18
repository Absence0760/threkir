import 'dart:math' as math;

import 'package:core_models/core_models.dart';

import '../../lib/grade_adjusted_pace.dart' show gradeFactor;
import '../../lib/run_stats.dart' show haversineMetres;
import 'hero_route.dart';

/// The store-screenshot demo account, as seeded into the local stack by
/// `assets/store/demo/store_demo_seed.sql`. The two files describe one
/// account, so a change to either is a change to both.
const kDemoEmail = 'store-demo@threkir.test';
const kDemoPassword = 'storedemo';
const kDemoPlanId = '5d000000-0000-4000-8000-0000000000a1';
const kDemoPlanName = 'Wrenfield Half Marathon';

/// A distinctive phrase from the seeded coach thread, used to know the thread
/// has loaded rather than to assert on its wording.
const kDemoCoachPhrase = 'still on track for 1:45';

/// The run the record panel opens: a lap of Central Park's full loop of
/// drives (6.1 miles), the most recent run that is not a long run.
const kHeroRunId = '5d000000-0000-4000-8000-0000000000b0';
const kHeroRunTitle = 'Central Park full loop';

/// The raced 10K tune-up the Race-time predictor anchors on ([tuneUp10k]).
const kTuneUpMetres = 10020.0;
const kTuneUpSeconds = 2870;

/// The Monday the seeded plan starts on: five weeks before this one, the same
/// `date_trunc('week', current_date) - 35` the SQL uses, so the runs below
/// land on the plan's own training days.
DateTime demoPlanStart(DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  return DateTime(
    day.year,
    day.month,
    day.day - (day.weekday - DateTime.monday) - 35,
  );
}

/// A session slot in the plan's training week.
enum DemoSlot { rest, quality, easy, tempo, recovery, long }

/// The slot [day] holds in a plan captured on [today]. Sunday is always the
/// long run. Monday to Saturday hold rest, quality, easy, tempo, rest and
/// recovery, rotated so that today is the tempo, so the Today panel shows a
/// session to start whichever day the capture runs, as its caption promises.
/// The seed's `v_shift` is the same rotation; change the two together.
DemoSlot demoSlotFor(DateTime day, DateTime today) {
  const week = [
    DemoSlot.rest,
    DemoSlot.quality,
    DemoSlot.easy,
    DemoSlot.tempo,
    DemoSlot.rest,
    DemoSlot.recovery,
  ];
  if (day.weekday == DateTime.sunday) return DemoSlot.long;
  final t = today.weekday - DateTime.monday;
  final shift = today.weekday == DateTime.sunday ? 0 : 3 - t;
  return week[(day.weekday - DateTime.monday + shift) % 6];
}

/// Every run on the device, oldest first: six weeks of easy base before the
/// plan, then one run for each session the plan has had, with a run that
/// isn't the long run carrying [heroLoop]'s track. The base matters to the
/// readiness line on Today: five weeks of history from nothing reads as heavy
/// fatigue (form below -20), which no runner six weeks into a plan has.
/// Distances and paces follow the seeded sessions with a deterministic wobble
/// so the history reads like a person rather than a generator, and a quality
/// session's pace is the whole run's, warm-up and cool-down included. The
/// latest quality session is a raced 10K ([tuneUp10k]). Each plan run
/// is within a few percent of its session's target, so the server's
/// run-to-workout matcher (decisions § 2079) ticks every past session off.
List<Run> demoRuns(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final start = demoPlanStart(today);
  final rnd = math.Random(1375);
  final runs = <Run>[];
  void add(DateTime day, double km, int paceSec, String title, int bpm) {
    final metres = km * 1000 * (0.98 + rnd.nextDouble() * 0.05);
    final secs = (metres / 1000 * (paceSec + rnd.nextInt(9) - 4)).round();
    final startedAt = DateTime(
      day.year,
      day.month,
      day.day,
      7,
      10 + rnd.nextInt(20),
    );
    runs.add(
      Run(
        id: '5d000000-0000-4000-8000-${(0xc000 + runs.length).toRadixString(16).padLeft(12, '0')}',
        startedAt: startedAt,
        duration: Duration(seconds: secs),
        distanceMetres: metres,
        source: RunSource.app,
        metadata: {
          'activity_type': 'run',
          'title': title,
          'avg_bpm': bpm + rnd.nextInt(5) - 2,
        },
      ),
    );
  }

  // Calendar days, never `add(Duration(days: 1))`: across a DST change that
  // lands on 23:00 of the same date and repeats a day.
  for (var i = 42; i > 0; i--) {
    final day = DateTime(start.year, start.month, start.day - i);
    final weekBack = (i - 1) ~/ 7;
    switch (day.weekday) {
      case DateTime.tuesday:
        add(day, 6.0, 355, 'Easy run', 140);
      case DateTime.thursday:
        add(day, 7.0, 340, 'Steady run', 146);
      case DateTime.saturday:
        add(day, 5.0, 365, 'Recovery jog', 134);
      case DateTime.sunday:
        add(day, 12.0 - weekBack * 0.5, 350, 'Long run', 147);
    }
  }
  var hero = -1;
  var tuneUp = -1;
  for (
    var day = start;
    day.isBefore(today);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final week = (day.difference(start).inHours / 24).round() ~/ 7;
    final slot = demoSlotFor(day, today);
    final (double km, int paceSec, String title, int bpm) = switch (slot) {
      DemoSlot.quality when week >= 4 => (9.0, 325, 'Track intervals', 156),
      DemoSlot.quality => (6.0, 362, 'Easy run', 141),
      DemoSlot.easy => (7.0, 358, 'Easy miles', 143),
      DemoSlot.tempo => (8.0 + math.min(week, 8) * 0.25, 322, 'Tempo', 154),
      DemoSlot.recovery => (5.0, 366, 'Recovery jog', 135),
      DemoSlot.long => (10.0 + math.min(week, 9), 360, 'Sunday long run', 149),
      DemoSlot.rest => (0.0, 0, '', 0),
    };
    if (km == 0) continue;
    if (slot != DemoSlot.long) hero = runs.length;
    if (slot == DemoSlot.quality && week >= 4) tuneUp = runs.length;
    add(day, km, paceSec, title, bpm);
  }
  runs[hero] = heroLoop(runs[hero].startedAt);
  runs[tuneUp] = tuneUp10k(runs[tuneUp]);
  return runs;
}

/// The plan's latest quality session is a 10K tune-up (the seed's
/// `10K tune-up` workout), raced: 10.02 km on the watch in [kTuneUpSeconds].
/// It is the freshest hard effort on the device, so the Race-time predictor
/// anchors on it, and Riegel from it gives the 1:45 half the plan aims at and
/// the coach quotes. A whole training run under-reads race fitness, which is
/// why the predictor needs a raced effort here at all.
Run tuneUp10k(Run slot) => Run(
  id: slot.id,
  startedAt: slot.startedAt,
  duration: const Duration(seconds: kTuneUpSeconds),
  distanceMetres: kTuneUpMetres,
  source: RunSource.app,
  metadata: {'activity_type': 'run', 'title': '10K tune-up', 'avg_bpm': 171},
);

/// The hero run: one counter-clockwise lap of Central Park's full loop of
/// drives from Columbus Circle ([kHeroRoute], a real line with real USGS
/// elevations), run at an even effort that tires a little: 5:34/km on the flat
/// at the start, 14 s/km slower by the end, then a hard last 500 m. Each 5 s
/// sample's pace is that flat pace scaled by the app's own Minetti cost of the
/// grade underfoot ([gradeFactor]) to the 0.95 power, because runners slow on
/// a climb by a little less than its full cost. Raw pace therefore fades over
/// Harlem Hill (the sixth km) while the grade-adjusted pace holds. The phone's
/// barometer recorded the altitude, so the app reads the climb off it at the
/// 3 m band.
///
/// Heart rate follows the effort with a 50 s lag from an 88 bpm start, for a
/// runner whose max is 188 and resting 52 (the seed's `user_settings`):
/// warm-up through Recovery and Easy, mostly Aerobic, Threshold up the hills
/// and Max in the finish. store_demo_hero_run_test.dart pins what the run
/// detail and the Progress predictor make of it.
const _flatPace = 334.0; // s/km on level ground, fresh
const _drift = 14.0; // s/km slower on the flat by the end
const _climbEase = 0.95; // share of a grade's cost the runner slows for
const _kickM = 500.0; // the hard finish, metres
const _kickPace = 0.85;
const _kickEffort = 0.22;
const _hrStart = 88.0;
const _hrLagS = 50.0;
const _restBpm = 52.0;
const _maxBpm = 188.0;

Run heroLoop(DateTime startedAt) {
  // The bare-earth model drops the drive where it crosses an arch, so the
  // altitude is a 100 m running median of the samples, then a 60 m mean.
  final raw = [for (final p in kHeroRoute) p.$3];
  final median = [
    for (var i = 0; i < raw.length; i++)
      (raw.sublist(math.max(0, i - 2), math.min(raw.length, i + 3))
        ..sort())[(math.min(raw.length, i + 3) - math.max(0, i - 2)) ~/ 2],
  ];
  final ele = [
    for (var i = 0; i < median.length; i++)
      [
            for (
              var j = math.max(0, i - 1);
              j <= math.min(median.length - 1, i + 1);
              j++
            )
              median[j],
          ].reduce((a, b) => a + b) /
          (math.min(median.length - 1, i + 1) - math.max(0, i - 1) + 1),
  ];

  final cumulative = <double>[0];
  for (var i = 1; i < kHeroRoute.length; i++) {
    final a = kHeroRoute[i - 1];
    final b = kHeroRoute[i];
    cumulative.add(cumulative.last + haversineMetres(a.$1, a.$2, b.$1, b.$2));
  }
  final total = cumulative.last;

  var seg = 0;
  ({double lat, double lng, double ele, double grade}) at(double metres) {
    while (seg < cumulative.length - 2 && cumulative[seg + 1] < metres) {
      seg++;
    }
    final span = cumulative[seg + 1] - cumulative[seg];
    final t = span == 0
        ? 0.0
        : ((metres - cumulative[seg]) / span).clamp(0.0, 1.0);
    final a = kHeroRoute[seg];
    final b = kHeroRoute[seg + 1];
    // The grade the runner feels: the rise over the 40 m either side.
    final lo = math.max(0, seg - 2);
    final hi = math.min(ele.length - 1, seg + 3);
    return (
      lat: a.$1 + (b.$1 - a.$1) * t,
      lng: a.$2 + (b.$2 - a.$2) * t,
      ele: ele[seg] + (ele[seg + 1] - ele[seg]) * t,
      grade: (ele[hi] - ele[lo]) / (cumulative[hi] - cumulative[lo]),
    );
  }

  const step = 5; // seconds between samples
  final track = <Waypoint>[];
  var travelled = 0.0;
  var seconds = 0;
  var bpm = _hrStart;
  while (true) {
    final here = at(travelled);
    final cost = gradeFactor(here.grade);
    final kick = travelled > total - _kickM;
    final flat =
        (_flatPace + _drift * travelled / total) * (kick ? _kickPace : 1);
    final pace =
        flat * math.pow(cost, _climbEase) + 3 * math.sin(seconds / 150);
    final effort =
        0.66 +
        1.6 * (math.pow(cost, 0.15) - 1) +
        (kick ? _kickEffort : 0) +
        0.05 * travelled / total;
    final target = _restBpm + (_maxBpm - _restBpm) * effort;
    bpm += (target - bpm) * (1 - math.exp(-step / _hrLagS));
    track.add(
      Waypoint(
        lat: here.lat,
        lng: here.lng,
        elevationMetres: here.ele,
        baroElevationMetres: here.ele,
        timestamp: startedAt.add(Duration(seconds: seconds)),
        bpm: (bpm + 1.5 * math.sin(seconds / 37)).round(),
      ),
    );
    if (travelled >= total) break;
    travelled = math.min(total, travelled + 1000 / pace * step);
    seconds += step;
  }
  final bpms = [for (final w in track) w.bpm!];
  return Run(
    id: kHeroRunId,
    startedAt: startedAt,
    duration: Duration(seconds: seconds),
    distanceMetres: total,
    track: track,
    source: RunSource.app,
    metadata: {
      'activity_type': 'run',
      'title': kHeroRunTitle,
      'avg_bpm': (bpms.reduce((a, b) => a + b) / bpms.length).round(),
    },
  );
}
