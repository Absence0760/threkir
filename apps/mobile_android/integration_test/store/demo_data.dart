import 'dart:math' as math;

import 'package:core_models/core_models.dart';

/// The store-screenshot demo account, as seeded into the local stack by
/// `assets/store/demo/store_demo_seed.sql`. The two files describe one
/// account, so a change to either is a change to both.
const kDemoEmail = 'store-demo@threkir.test';
const kDemoPassword = 'storedemo';
const kDemoPlanId = '5d000000-0000-4000-8000-0000000000a1';
const kDemoPlanName = 'Riverside Half Marathon';

/// A distinctive phrase from the seeded coach thread, used to know the thread
/// has loaded rather than to assert on its wording.
const kDemoCoachPhrase = 'still on track for 1:45';

/// The run the record panel opens: a loop of Central Park's drives, the most
/// recent run that is not a long run.
const kHeroRunId = '5d000000-0000-4000-8000-0000000000b0';

/// The Monday the seeded plan starts on: five weeks before this one, the same
/// `date_trunc('week', current_date) - 35` the SQL uses, so the runs below
/// land on the plan's own training days.
DateTime demoPlanStart(DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday) - 35);
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
/// so the history reads like a person rather than a generator; each plan run
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
    final startedAt = DateTime(day.year, day.month, day.day, 7, 10 + rnd.nextInt(20));
    runs.add(Run(
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
    ));
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
  for (var day = start;
      day.isBefore(today);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final week = (day.difference(start).inHours / 24).round() ~/ 7;
    final slot = demoSlotFor(day, today);
    final (double km, int paceSec, String title, int bpm) = switch (slot) {
      DemoSlot.quality when week >= 4 => (9.0, 300, 'Track intervals', 162),
      DemoSlot.quality => (6.0, 352, 'Easy run', 141),
      DemoSlot.easy => (7.0, 348, 'Easy miles', 143),
      DemoSlot.tempo => (8.0 + math.min(week, 8) * 0.25, 296, 'Tempo', 158),
      DemoSlot.recovery => (5.0, 366, 'Recovery jog', 135),
      DemoSlot.long => (10.0 + math.min(week, 9), 342, 'Sunday long run', 149),
      DemoSlot.rest => (0.0, 0, '', 0),
    };
    if (km == 0) continue;
    if (slot != DemoSlot.long) hero = runs.length;
    add(day, km, paceSec, title, bpm);
  }
  runs[hero] = heroLoop(runs[hero].startedAt);
  return runs;
}

/// One counter-clockwise lap of Central Park's drives (northbound on the
/// East Drive, over Harlem Hill, southbound on the West Drive), sampled every
/// five seconds at about 5:05 per km with a heart rate that drifts up and a
/// climb at the north end. The drives are offset ~150 m inside Fifth Avenue
/// and Central Park West, which bound the park.
Run heroLoop(DateTime startedAt) {
  const sw = (40.7681, -73.9819); // Central Park West at 59th
  const nw = (40.8003, -73.9581); // Central Park West at 110th
  const se = (40.7644, -73.9730); // Fifth Avenue at 59th
  const ne = (40.7967, -73.9493); // Fifth Avenue at 110th
  (double, double) lerp((double, double) a, (double, double) b, double t) =>
      (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
  // Inward offsets perpendicular to the park's axis, ~150 m.
  (double, double) west(double t) {
    final p = lerp(sw, nw, t);
    final wobble = math.sin(t * math.pi * 5) * 0.0004;
    return (p.$1 - 0.00066 - wobble * 0.5, p.$2 + 0.00154 + wobble);
  }

  (double, double) east(double t) {
    final p = lerp(se, ne, t);
    final wobble = math.sin(t * math.pi * 4 + 1) * 0.0003;
    return (p.$1 + 0.00066 + wobble * 0.5, p.$2 - 0.00154 - wobble);
  }

  (double, double) bezier(
      (double, double) a, (double, double) c, (double, double) b, double t) {
    final u = 1 - t;
    return (
      u * u * a.$1 + 2 * u * t * c.$1 + t * t * b.$1,
      u * u * a.$2 + 2 * u * t * c.$2 + t * t * b.$2,
    );
  }

  final anchors = <(double, double)>[
    for (var i = 0; i <= 60; i++) east(0.06 + 0.89 * i / 60),
    for (var i = 1; i < 20; i++)
      bezier(east(0.95), lerp(nw, ne, 0.5),
          west(0.95), i / 20),
    for (var i = 0; i <= 60; i++) west(0.95 - 0.89 * i / 60),
    for (var i = 1; i <= 20; i++)
      bezier(west(0.06), lerp(sw, se, 0.5),
          east(0.06), i / 20),
  ];

  double metresBetween((double, double) a, (double, double) b) {
    const r = 6371000.0;
    final dLat = (b.$1 - a.$1) * math.pi / 180;
    final dLng = (b.$2 - a.$2) * math.pi / 180;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.$1 * math.pi / 180) *
            math.cos(b.$1 * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  final cumulative = <double>[0];
  for (var i = 1; i < anchors.length; i++) {
    cumulative.add(cumulative.last + metresBetween(anchors[i - 1], anchors[i]));
  }
  final total = cumulative.last;
  const step = 5; // seconds between samples
  const basePace = 305.0; // seconds per km
  final track = <Waypoint>[];
  var travelled = 0.0;
  var seconds = 0;
  var seg = 0;
  while (true) {
    final along = travelled / total;
    // The north end climbs Harlem Hill, which costs about 20 s/km.
    final hill = math.exp(-math.pow((along - 0.5) / 0.06, 2));
    final pace = basePace + 20 * hill + 6 * math.sin(seconds / 170);
    while (seg < cumulative.length - 2 && cumulative[seg + 1] < travelled) {
      seg++;
    }
    final span = cumulative[seg + 1] - cumulative[seg];
    final t = span == 0 ? 0.0 : (travelled - cumulative[seg]) / span;
    final p = lerp(anchors[seg], anchors[seg + 1], t.clamp(0.0, 1.0));
    track.add(Waypoint(
      lat: p.$1,
      lng: p.$2,
      elevationMetres: 28 + 24 * hill + 4 * math.sin(along * math.pi * 6),
      timestamp: startedAt.add(Duration(seconds: seconds)),
      bpm: (146 + 10 * along + 8 * hill + 2 * math.sin(seconds / 40)).round(),
    ));
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
      'title': 'Park loop',
      'avg_bpm': (bpms.reduce((a, b) => a + b) / bpms.length).round(),
    },
  );
}
