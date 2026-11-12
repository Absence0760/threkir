import 'package:core_models/core_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/run_share_stats.dart';

Run _run({
  List<Waypoint> track = const [],
  Map<String, dynamic> metadata = const {'activity_type': 'run'},
  double distanceMetres = 10000,
  Duration duration = const Duration(minutes: 50),
}) =>
    Run(
      id: 'r1',
      startedAt: DateTime.utc(2026, 4, 15, 8),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      track: track,
      metadata: metadata,
    );

final _hill = [
  for (var i = 0; i < 6; i++)
    Waypoint(
      lat: 51.44 + i * 0.002,
      lng: -0.27,
      elevationMetres: 20.0 + i * 30,
      timestamp: DateTime.utc(2026, 4, 15, 8, i),
    ),
];

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('availableShareStats', () {
    test('distance, pace and time always; nothing unmeasured', () {
      expect(availableShareStats(_run()), [
        RunShareStatKind.distance,
        RunShareStatKind.pace,
        RunShareStatKind.time,
      ]);
    });

    test('climb when the track climbed, heart rate when it was measured', () {
      final run = _run(
        track: _hill,
        metadata: const {'activity_type': 'run', 'avg_bpm': 155},
      );
      expect(availableShareStats(run), RunShareStatKind.values);
    });

    test('a zero or absent average heart rate is not offered', () {
      for (final meta in [
        const {'activity_type': 'run', 'avg_bpm': 0},
        const {'activity_type': 'run'},
      ]) {
        expect(availableShareStats(_run(metadata: meta)),
            isNot(contains(RunShareStatKind.heartRate)));
      }
    });

    test('a flat track offers no climb', () {
      final flat = [
        for (var i = 0; i < 4; i++)
          Waypoint(lat: 51.44 + i * 0.002, lng: -0.27, elevationMetres: 20),
      ];
      expect(runShareClimbMetres(_run(track: flat)), isNull);
    });
  });

  group('runShareStats', () {
    test('prints the picked kinds in display order', () {
      final stats = runShareStats(
        l10n,
        _run(),
        DistanceUnit.km,
        kinds: const [RunShareStatKind.time, RunShareStatKind.distance],
      );
      expect([for (final s in stats) s.kind],
          [RunShareStatKind.distance, RunShareStatKind.time]);
      expect(stats.first.value, '10.00');
      expect(stats.last.value, '50:00');
    });

    test('a pick the run cannot print is dropped, never shown empty', () {
      final stats = runShareStats(
        l10n,
        _run(),
        DistanceUnit.km,
        kinds: const [RunShareStatKind.heartRate, RunShareStatKind.climb],
      );
      expect([for (final s in stats) s.kind], [RunShareStatKind.distance]);
    });

    test('heart rate prints the measured average in bpm', () {
      final stats = runShareStats(
        l10n,
        _run(metadata: const {'activity_type': 'run', 'avg_bpm': 151.6}),
        DistanceUnit.km,
        kinds: const [RunShareStatKind.heartRate],
      );
      expect(stats.single.value, '152');
      expect(stats.single.unit, l10n.runUnitBpm);
    });

    test('climb prints in the runner unit, without its label in the value',
        () {
      final km = runShareStats(l10n, _run(track: _hill), DistanceUnit.km,
          kinds: const [RunShareStatKind.climb]).single;
      final mi = runShareStats(l10n, _run(track: _hill), DistanceUnit.mi,
          kinds: const [RunShareStatKind.climb]).single;
      expect(km.unit, 'm');
      expect(mi.unit, 'ft');
      expect(km.value, isNot(contains('m')));
      expect(double.parse(mi.value.replaceAll(',', '')),
          greaterThan(double.parse(km.value.replaceAll(',', ''))));
    });

    test('moving time rounds a millisecond-stamped track to the second', () {
      final track = [
        Waypoint(
            lat: 51.44, lng: -0.27, timestamp: DateTime.utc(2026, 4, 15, 8)),
        Waypoint(
            lat: 51.442,
            lng: -0.27,
            timestamp: DateTime.utc(2026, 4, 15, 8, 0, 1, 600)),
      ];
      final stats = runShareStats(l10n, _run(track: track), DistanceUnit.km,
          kinds: const [RunShareStatKind.time]);
      expect(stats.single.value, '00:02');
    });

    test('a ride prints speed in the pace slot', () {
      final stats = runShareStats(
        l10n,
        _run(metadata: const {'activity_type': 'cycle'}),
        DistanceUnit.km,
        kinds: const [RunShareStatKind.pace],
      );
      expect(stats.single.label, l10n.shareCardStatSpeed);
    });
  });

  test('formatShareDuration drops the hour under an hour', () {
    expect(formatShareDuration(const Duration(minutes: 4, seconds: 5)),
        '04:05');
    expect(formatShareDuration(const Duration(hours: 2, minutes: 3, seconds: 4)),
        '2:03:04');
  });
}
