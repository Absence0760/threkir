// Mirrors the parse cases of apps/web/src/lib/training/plan_serialize.test.ts.
// The two export-only web cases ("emits a header table", "adds Race, Priority
// and Goal columns only when a race carries one") have no counterpart here:
// mobile ports the parse half only (decisions § 2053). Where a web case
// round-trips through planToMarkdown, the Markdown below is the text that
// function writes for the same plan, so web's export format is pinned too.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_serialize.dart';
import '../lib/training.dart';

final Map<String, dynamic> _sample = {
  'name': 'Spring Marathon',
  'goalEvent': 'distance_full',
  'goalDistanceM': 42195,
  'goalTimeSec': 3 * 3600 + 30 * 60,
  'startDate': '2026-06-07',
  'workouts': [
    {'week_index': 0, 'scheduled_date': '2026-06-07', 'kind': 'long', 'target_distance_m': 24000, 'target_pace_sec_per_km': 330, 'notes': 'Easy long run'},
    {'week_index': 0, 'scheduled_date': '2026-06-08', 'kind': 'rest', 'target_distance_m': null, 'target_pace_sec_per_km': null, 'notes': null},
    {'week_index': 0, 'scheduled_date': '2026-06-09', 'kind': 'tempo', 'target_distance_m': 10000, 'target_pace_sec_per_km': 270, 'notes': null},
    {'week_index': 1, 'scheduled_date': '2026-06-14', 'kind': 'long', 'target_distance_m': 27000, 'target_pace_sec_per_km': 330, 'notes': null},
    {'week_index': 1, 'scheduled_date': '2026-06-16', 'kind': 'interval', 'target_distance_m': 8000, 'target_pace_sec_per_km': 240, 'notes': '6x800'},
  ],
};

/// What web's planToMarkdown writes for [_sample].
const String _sampleMarkdown = '''# Spring Marathon

- Goal event: distance_full
- Goal distance: 42.20 km
- Goal time: 3:30:00
- Start date: 2026-06-07

| Week | Date | Type | Distance | Pace | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | 2026-06-07 | long | 24.00 km | 5:30 | Easy long run |
| 1 | 2026-06-08 | rest |  |  |  |
| 1 | 2026-06-09 | tempo | 10.00 km | 4:30 |  |
| 2 | 2026-06-14 | long | 27.00 km | 5:30 |  |
| 2 | 2026-06-16 | interval | 8.00 km | 4:00 | 6x800 |
''';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> _flatten(ParsedPlan p) => [
      for (final w in p.generated.weeks)
        for (final wo in w.workouts)
          {
            'week_index': w.weekIndex,
            'scheduled_date': _iso(wo.scheduledDate),
            'kind': workoutKindDbValue(wo.kind),
            'target_distance_m': wo.targetDistanceM,
            'target_pace_sec_per_km': wo.targetPaceSecPerKm,
            'notes': wo.notes,
          },
    ];

List<Map<String, dynamic>> _flattenRaces(ParsedPlan p) => [
      for (final w in p.generated.weeks)
        for (final wo in w.workouts)
          {
            'week_index': w.weekIndex,
            'scheduled_date': _iso(wo.scheduledDate),
            'kind': workoutKindDbValue(wo.kind),
            'target_distance_m': wo.targetDistanceM,
            'target_pace_sec_per_km': wo.targetPaceSecPerKm,
            'notes': wo.notes,
            'target_duration_seconds': wo.targetDurationSeconds,
            'race_name': wo.raceName,
            'race_priority': wo.racePriority,
          },
    ];

/// Compares numerically so an int fixture matches a parsed double.
void _expectRows(List<Map<String, dynamic>> actual, List<dynamic> expected) {
  expect(actual.length, expected.length);
  for (var i = 0; i < actual.length; i++) {
    final e = expected[i] as Map<String, dynamic>;
    for (final key in e.keys) {
      final a = actual[i][key];
      final x = e[key];
      if (a is num && x is num) {
        expect(a, closeTo(x, 1e-9), reason: 'row $i $key');
      } else {
        expect(a, x, reason: 'row $i $key');
      }
    }
  }
}

final Map<String, dynamic> _racePlan = {
  'name': 'Comrades block',
  'goalEvent': 'custom',
  'goalDistanceM': 91000,
  'goalTimeSec': 11 * 3600,
  'startDate': '2027-03-28',
  'workouts': [
    {'week_index': 0, 'scheduled_date': '2027-03-28', 'kind': 'long', 'target_distance_m': 30000, 'target_pace_sec_per_km': 360, 'notes': null, 'target_duration_seconds': null, 'race_name': null, 'race_priority': null},
    {'week_index': 1, 'scheduled_date': '2027-04-04', 'kind': 'race', 'target_distance_m': 56000, 'target_pace_sec_per_km': null, 'notes': 'Two Oceans', 'target_duration_seconds': 6 * 3600 + 30 * 60, 'race_name': 'Two Oceans Ultra', 'race_priority': 'B'},
    {'week_index': 2, 'scheduled_date': '2027-04-11', 'kind': 'race', 'target_distance_m': 91000, 'target_pace_sec_per_km': null, 'notes': null, 'target_duration_seconds': null, 'race_name': 'Comrades', 'race_priority': 'A'},
  ],
};

/// What web's planToMarkdown writes for [_racePlan].
const String _racePlanMarkdown = '''# Comrades block

- Goal event: custom
- Goal distance: 91.00 km
- Goal time: 11:00:00
- Start date: 2027-03-28

| Week | Date | Type | Distance | Pace | Notes | Race | Priority | Goal |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2027-03-28 | long | 30.00 km | 6:00 |  |  |  |  |
| 2 | 2027-04-04 | race | 56.00 km |  | Two Oceans | Two Oceans Ultra | B | 6:30:00 |
| 3 | 2027-04-11 | race | 91.00 km |  |  | Comrades | A |  |
''';

String _table(List<String> lines) => lines.join('\n');

void main() {
  // ─────────────────────── Markdown round-trip ───────────────────────

  test('planToMarkdown → parsePlanMarkdown round-trips the workouts', () {
    final parsed = parsePlanMarkdown(_sampleMarkdown);
    expect(parsed.name, _sample['name']);
    expect(parsed.goalEvent, GoalEvent.distanceFull);
    expect(parsed.goalDistanceM, 42195);
    expect(parsed.goalTimeSec, _sample['goalTimeSec']);
    expect(parsed.startDate, _sample['startDate']);
    _expectRows(_flatten(parsed), _sample['workouts'] as List);
  });

  test('parsePlanMarkdown recomputes phase from week position', () {
    final rows = [
      for (var wk = 0; wk < 6; wk++)
        '| ${wk + 1} | ${_iso(DateTime(2026, 6, 7 + wk * 7))} | long | 20.00 km | 5:30 |  |',
    ];
    final parsed = parsePlanMarkdown(_table([
      '| Week | Date | Type | Distance | Pace | Notes |',
      '| --- | --- | --- | --- | --- | --- |',
      ...rows,
    ]));
    // phaseFor(0, 6) → base; the final week is always 'race'.
    expect(parsed.generated.weeks[0].phase, PlanPhase.base);
    expect(parsed.generated.weeks[5].phase, PlanPhase.race);
  });

  test('parsePlanMarkdown gives a pasted ultra plan the generator\'s ultra phases',
      () {
    final rows = [
      for (var wk = 0; wk < 18; wk++)
        '| ${wk + 1} | ${_iso(DateTime(2026, 6, 7 + wk * 7))} | long | 20.00 km |  |  |',
    ];
    final parsed = parsePlanMarkdown(_table([
      '# 70 km ultra',
      '- Goal event: custom',
      '- Goal distance: 70.00 km',
      '| Week | Date | Type | Distance | Pace | Notes |',
      '| --- | --- | --- | --- | --- | --- |',
      ...rows,
    ]));
    final phases = [for (final w in parsed.generated.weeks) w.phase];
    expect(phases, [for (var i = 0; i < 18; i++) planPhaseFor(i, 18, 70000)]);
    // Two taper weeks, as the generator's ultra branch gives 70 km; the road
    // split would have started a third one at week 15.
    expect(phases.sublist(12), [
      PlanPhase.peak,
      PlanPhase.peak,
      PlanPhase.peak,
      PlanPhase.taper,
      PlanPhase.taper,
      PlanPhase.race,
    ]);
    expect(phaseFor(14, 18), PlanPhase.taper);
  });

  test('parsePlanMarkdown sums weekly volume from the workout distances', () {
    final parsed = parsePlanMarkdown(_sampleMarkdown);
    expect(parsed.generated.weeks[0].targetVolumeM, 24000 + 10000);
    expect(parsed.generated.weeks[1].targetVolumeM, 27000 + 8000);
  });

  test('parsePlanMarkdown accepts a hand-written table with mile distances',
      () {
    final parsed = parsePlanMarkdown(_table([
      '# Coach plan',
      '- Goal event: distance_10k',
      '- Start date: 2026-07-05',
      '| Week | Date | Type | Distance | Pace | Notes |',
      '| --- | --- | --- | --- | --- | --- |',
      '| 1 | 2026-07-05 | long | 10 mi | 5:30 | |',
      '| 1 | 2026-07-07 | easy | 5 mi |  | recovery |',
    ]));
    final flat = _flatten(parsed);
    expect(flat.length, 2);
    expect(flat[0]['target_distance_m'] as double, closeTo(10 * 1609.344, 0.01));
    expect(flat[0]['target_pace_sec_per_km'], 330);
    expect(flat[1]['notes'], 'recovery');
  });

  test(
      'parsePlanMarkdown accepts a hand-written row that omits the trailing '
      'Notes column', () {
    final parsed = parsePlanMarkdown(_table([
      '# Coach plan',
      '| Week | Date | Type | Distance | Pace |',
      '| --- | --- | --- | --- | --- |',
      '| 1 | 2026-07-05 | easy | 5 km | 5:00 |',
    ]));
    final flat = _flatten(parsed);
    expect(flat.length, 1,
        reason: 'the notes-less row must not be silently dropped');
    expect(flat[0]['kind'], 'easy');
    expect(flat[0]['notes'], isNull);
  });

  test(
      'fmtPaceCell / fmtHmsCell never emit a :60 seconds field for a '
      'fractional input', () {
    // 359.6 s/km must format as 6:00, not 5:60 (which re-parses a minute off).
    final withFractionalPace = {
      ..._sample,
      'workouts': [
        {...(_sample['workouts'] as List).first as Map<String, dynamic>, 'target_pace_sec_per_km': 359.6},
      ],
    };
    final parsed = parsePlanJson(jsonEncode(withFractionalPace));
    expect(_flatten(parsed)[0]['target_pace_sec_per_km'], 360);
  });

  // ─────────────────────── error handling ───────────────────────

  test('parsePlanMarkdown throws on an unknown workout kind', () {
    final md = _table([
      '| Week | Date | Type | Distance | Pace | Notes |',
      '| --- | --- | --- | --- | --- | --- |',
      '| 1 | 2026-07-05 | sprintz | 5 km | | |',
    ]);
    expect(
        () => parsePlanMarkdown(md),
        throwsA(isA<PlanParseError>().having(
            (e) => e.message, 'message', contains('Unknown workout type'))));
  });

  test('parsePlanMarkdown throws on a malformed date', () {
    final md = _table([
      '| Week | Date | Type | Distance | Pace | Notes |',
      '| --- | --- | --- | --- | --- | --- |',
      '| 1 | 07/05/2026 | easy | 5 km | | |',
    ]);
    expect(
        () => parsePlanMarkdown(md),
        throwsA(isA<PlanParseError>()
            .having((e) => e.message, 'message', contains('Bad date'))));
  });

  test('parsePlanMarkdown throws when there are no rows', () {
    expect(
        () => parsePlanMarkdown('# Just a title\n\nno table here'),
        throwsA(isA<PlanParseError>()
            .having((e) => e.message, 'message', contains('No workout rows'))));
  });

  test(
      'parsePlanMarkdown defaults goalEvent to custom + infers distance from '
      'longest run', () {
    final parsed = parsePlanMarkdown(_table([
      '| Week | Date | Type | Distance | Pace | Notes |',
      '| --- | --- | --- | --- | --- | --- |',
      '| 1 | 2026-07-05 | long | 30 km | | |',
      '| 1 | 2026-07-07 | easy | 8 km | | |',
    ]));
    expect(parsed.goalEvent, GoalEvent.custom);
    expect(parsed.goalDistanceM, 30000);
  });

  // ─────────────────────── JSON round-trip ───────────────────────

  test('planToJson → parsePlanJson round-trips the workouts', () {
    final parsed = parsePlanJson(jsonEncode(_sample));
    expect(parsed.name, _sample['name']);
    expect(parsed.goalDistanceM, 42195);
    _expectRows(_flatten(parsed), _sample['workouts'] as List);
  });

  test('parsePlanJson carries the taper stamp back onto the workout it eased',
      () {
    const stamp = '2027-03-30T07:15:00.000Z';
    final sampleWorkouts = _sample['workouts'] as List;
    final plan = {
      ..._sample,
      'workouts': [
        for (var i = 0; i < sampleWorkouts.length; i++)
          {
            ...sampleWorkouts[i] as Map<String, dynamic>,
            'race_taper_applied_at': i == 1 ? stamp : null,
          },
      ],
    };
    final stamps = [
      for (final w in parsePlanJson(jsonEncode(plan)).generated.weeks)
        for (final wo in w.workouts) wo.raceTaperAppliedAt,
    ];
    expect(stamps, [
      for (var i = 0; i < sampleWorkouts.length; i++) i == 1 ? stamp : null,
    ]);
    // The Markdown table is a hand-edited prescription: no stamp in.
    expect(
        parsePlanMarkdown(_sampleMarkdown).generated.weeks.every(
            (w) => w.workouts.every((wo) => wo.raceTaperAppliedAt == null)),
        isTrue);
  });

  test('parsePlanJson refuses a taper stamp that is not a timestamp', () {
    final sampleWorkouts = _sample['workouts'] as List;
    Map<String, dynamic> withStamps(Object? Function(int i) stampAt) => {
          ..._sample,
          'workouts': [
            for (var i = 0; i < sampleWorkouts.length; i++)
              {
                ...sampleWorkouts[i] as Map<String, dynamic>,
                'race_taper_applied_at': stampAt(i),
              },
          ],
        };
    for (final bad in <Object>['yesterday', '2027-03-30', 42]) {
      expect(
          () => parsePlanJson(jsonEncode(withStamps((i) => i == 0 ? bad : null))),
          throwsA(isA<PlanParseError>().having(
              (e) => e.message, 'message', contains('race_taper_applied_at'))),
          reason: '$bad');
    }
    expect(
        parsePlanJson(jsonEncode(withStamps((_) => '2027-03-30T07:15:00+00:00')))
            .generated
            .weeks[0]
            .workouts[0]
            .raceTaperAppliedAt,
        '2027-03-30T07:15:00+00:00');
  });

  test('parsePlanJson throws on non-JSON + on missing workouts', () {
    expect(
        () => parsePlanJson('not json {'),
        throwsA(isA<PlanParseError>()
            .having((e) => e.message, 'message', contains('valid JSON'))));
    expect(
        () => parsePlanJson('{"name":"x"}'),
        throwsA(isA<PlanParseError>()
            .having((e) => e.message, 'message', contains('workouts array'))));
  });

  test('notes with a pipe survive the round-trip (sanitized to a slash)', () {
    final withPipe = {
      ..._sample,
      'workouts': [
        {'week_index': 0, 'scheduled_date': '2026-06-07', 'kind': 'easy', 'target_distance_m': 5000, 'target_pace_sec_per_km': null, 'notes': 'do 4x | strides'},
      ],
    };
    expect(_flatten(parsePlanJson(jsonEncode(withPipe)))[0]['notes'],
        'do 4x / strides');
  });

  // ─────────────────────── Race columns ───────────────────────

  test('race columns round-trip through Markdown and JSON', () {
    _expectRows(_flattenRaces(parsePlanMarkdown(_racePlanMarkdown)),
        _racePlan['workouts'] as List);
    _expectRows(_flattenRaces(parsePlanJson(jsonEncode(_racePlan))),
        _racePlan['workouts'] as List);
  });

  test('parsePlanMarkdown maps columns by header name, in any order and case',
      () {
    final rows = _flattenRaces(parsePlanMarkdown(_table([
      '# Reordered',
      '| date | WEEK | Type | Race | Priority | Goal | Distance |',
      '| --- | --- | --- | --- | --- | --- | --- |',
      '| 2027-02-06 | 1 | race | parkrun | c | 22:30 | 5 km |',
      '| 2027-02-07 | 1 | easy |  |  |  | 8 km |',
    ])));
    _expectRows([rows[0]], [
      {
        'week_index': 0,
        'scheduled_date': '2027-02-06',
        'kind': 'race',
        'target_distance_m': 5000,
        'target_pace_sec_per_km': null,
        'notes': null,
        'target_duration_seconds': 22 * 60 + 30,
        'race_name': 'parkrun',
        'race_priority': 'C',
      },
    ]);
    expect(rows[1]['kind'], 'easy');
    expect(rows[1]['target_distance_m'], 8000);
    expect(rows[1]['race_name'], isNull);
  });

  test(
      'parsePlanMarkdown reads the legacy six-column table positionally, '
      'extra cells folding into notes', () {
    final row = _flattenRaces(parsePlanMarkdown(_table([
      '| Week | Date | Type | Distance | Pace | Notes |',
      '| --- | --- | --- | --- | --- | --- |',
      '| 1 | 2027-02-06 | race | 5 km | 4:30 | parkrun | PB attempt |',
    ])))
        .single;
    expect(row['notes'], 'parkrun|PB attempt');
    expect(row['target_pace_sec_per_km'], 270);
    expect(row['race_name'], isNull);
    expect(row['race_priority'], isNull);
    expect(row['target_duration_seconds'], isNull);
  });

  test(
      'parsePlanMarkdown rejects race fields on a non-race row and a bad '
      'priority or goal', () {
    String table(String row) => _table([
          '| Week | Date | Type | Distance | Race | Priority | Goal |',
          '| --- | --- | --- | --- | --- | --- | --- |',
          row,
        ]);
    Matcher throwsWith(String s) => throwsA(isA<PlanParseError>()
        .having((e) => e.message, 'message', contains(s)));
    expect(
        () => parsePlanMarkdown(
            table('| 1 | 2027-02-06 | long | 30 km | Big Run |  |  |')),
        throwsWith('only apply to race rows'));
    expect(
        () => parsePlanMarkdown(
            table('| 1 | 2027-02-06 | easy | 8 km |  | B |  |')),
        throwsWith('only apply to race rows'));
    expect(
        () => parsePlanMarkdown(
            table('| 1 | 2027-02-06 | race | 5 km | parkrun | D |  |')),
        throwsWith('priority "D"'));
    expect(
        () => parsePlanMarkdown(
            table('| 1 | 2027-02-06 | race | 5 km | parkrun |  | fast |')),
        throwsWith('goal time "fast"'));
  });

  test(
      'parsePlanMarkdown reads a race goal up to 999 hours and refuses a field '
      'out of range', () {
    String table(String goal) => [
          '| Week | Date | Type | Distance | Race | Priority | Goal |',
          '| --- | --- | --- | --- | --- | --- | --- |',
          '| 1 | 2027-02-06 | race | 386 km | Moab 240 | A | $goal |',
        ].join('\n');
    int? goalOf(String goal) => parsePlanMarkdown(table(goal))
        .generated
        .weeks[0]
        .workouts[0]
        .targetDurationSeconds;
    expect(goalOf('105:00:00'), 105 * 3600);
    expect(goalOf('999:59:59'), 999 * 3600 + 59 * 60 + 59);
    expect(goalOf('25:30'), 25 * 60 + 30);
    for (final bad in ['1000:00:00', '1:75:00', '1:30:60', '25:61']) {
      expect(
          () => parsePlanMarkdown(table(bad)),
          throwsA(isA<PlanParseError>()
              .having((e) => e.message, 'message', contains('goal time'))),
          reason: bad);
    }
  });

  test(
      'a piped race name, a priority-only race, a goal-only race and the plan '
      'goal time survive the round-trip', () {
    final plan = {
      'name': 'Spring double',
      'goalEvent': 'distance_half',
      'goalDistanceM': 21097.5,
      'goalTimeSec': 1 * 3600 + 35 * 60 + 20,
      'startDate': '2027-03-07',
      'workouts': [
        {'week_index': 0, 'scheduled_date': '2027-03-07', 'kind': 'race', 'target_distance_m': 5000, 'target_pace_sec_per_km': null, 'notes': null, 'target_duration_seconds': null, 'race_name': null, 'race_priority': 'C'},
        {'week_index': 1, 'scheduled_date': '2027-03-14', 'kind': 'race', 'target_distance_m': 10000, 'target_pace_sec_per_km': null, 'notes': null, 'target_duration_seconds': 42 * 60 + 5, 'race_name': null, 'race_priority': null},
        {'week_index': 2, 'scheduled_date': '2027-03-21', 'kind': 'race', 'target_distance_m': 21100, 'target_pace_sec_per_km': null, 'notes': null, 'target_duration_seconds': null, 'race_name': 'City | Half', 'race_priority': 'A'},
      ],
    };
    // What web's planToMarkdown writes for [plan].
    const markdown = """# Spring double

- Goal event: distance_half
- Goal distance: 21.10 km
- Goal time: 1:35:20
- Start date: 2027-03-07

| Week | Date | Type | Distance | Pace | Notes | Race | Priority | Goal |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2027-03-07 | race | 5.00 km |  |  |  | C |  |
| 2 | 2027-03-14 | race | 10.00 km |  |  |  |  | 0:42:05 |
| 3 | 2027-03-21 | race | 21.10 km |  |  | City / Half | A |  |
""";
    for (final parsed in [
      parsePlanMarkdown(markdown),
      parsePlanJson(jsonEncode(plan)),
    ]) {
      expect(parsed.goalTimeSec, plan['goalTimeSec']);
      expect(
        _flattenRaces(parsed)
            .map((r) => [
                  r['race_name'],
                  r['race_priority'],
                  r['target_duration_seconds'],
                ])
            .toList(),
        [
          [null, 'C', null],
          [null, null, 42 * 60 + 5],
          ['City / Half', 'A', null],
        ],
      );
    }
  });

  test(
      'parsePlanMarkdown keeps a 120-character race name and rejects a '
      '121-character one', () {
    String table(String race) => _table([
          '| Week | Date | Type | Distance | Race |',
          '| --- | --- | --- | --- | --- |',
          '| 1 | 2027-02-06 | race | 5 km | $race |',
        ]);
    final longest = 'R' * 120;
    expect(_flattenRaces(parsePlanMarkdown(table(longest)))[0]['race_name'],
        longest);
    expect(
        () => parsePlanMarkdown(table('${longest}R')),
        throwsA(isA<PlanParseError>().having(
            (e) => e.message, 'message', contains('longer than 120 characters'))));
  });

  test("parsePlanMarkdown refuses a workout dated before the plan's own start "
      'date', () {
    String md(String start) => _table([
          '# Early row',
          '- Start date: $start',
          '| Week | Date | Type | Distance | Pace | Notes |',
          '| --- | --- | --- | --- | --- | --- |',
          '| 1 | 2027-03-07 | easy | 5 km | | |',
          '| 1 | 2027-03-10 | long | 12 km | | |',
        ]);
    expect(
        () => parsePlanMarkdown(md('2027-03-08')),
        throwsA(isA<PlanParseError>().having((e) => e.message, 'message',
            contains("2027-03-07 is before the plan's start date, 2027-03-08"))));
    expect(parsePlanMarkdown(md('2027-03-07')).startDate, '2027-03-07');
    expect(parsePlanMarkdown(md('2027-03-01')).startDate, '2027-03-01');
  });
}
