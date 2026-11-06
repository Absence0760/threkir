/// Pure unit tests for the in-progress recovery helper.
/// Persona-hunt finding Casual #3 — pre-fix, sub-threshold partials
/// were silently `clearInProgress()`-d with no breadcrumb. The
/// classifier now hands back the partial a banner reports in both
/// cases so the user can tell the difference between "the app dropped
/// a partial" and "the app ate my run". BUG-006 (#1300): a recent
/// partial with any distance or a minute of time is offered back
/// instead of discarded.

import 'package:core_models/core_models.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import '../lib/in_progress_recovery.dart';
import '../lib/l10n/gen/app_localizations.dart';

Run _partial({
  required double distanceMetres,
  required Duration duration,
  int waypoints = 0,
  bool indoor = false,
  DateTime? savedAt,
}) {
  final track = List.generate(
    waypoints,
    (i) => Waypoint(
      lat: -37.81 + i * 0.001,
      lng: 144.96 + i * 0.001,
      timestamp: DateTime.utc(2026, 4, 1).add(Duration(seconds: i * 5)),
    ),
  );
  final metadata = <String, dynamic>{
    if (indoor) 'indoor_estimated': true,
    if (savedAt != null) 'in_progress_saved_at': savedAt.toIso8601String(),
  };
  return Run(
    id: 'partial-1',
    startedAt: DateTime.utc(2026, 4, 1),
    duration: duration,
    distanceMetres: distanceMetres,
    track: track,
    source: RunSource.app,
    metadata: metadata.isEmpty ? null : metadata,
  );
}

final _en = lookupAppLocalizations(const Locale('en'));

String? _bannerKm(InProgressEvaluation r) =>
    inProgressBannerText(_en, r, DistanceUnit.km);

void main() {
  group('evaluateInProgressPartial', () {
    test('null partial → outcome=none, no banner', () {
      final r = evaluateInProgressPartial(null);
      expect(r.outcome, InProgressOutcome.none);
      expect(r.recovered, isNull);
      expect(r.bannerPartial, isNull);
      expect(_bannerKm(r), isNull);
    });

    test('GPS partial above thresholds → recovered, banner', () {
      // 3 waypoints + 100 m distance — both thresholds met.
      final partial = _partial(
        distanceMetres: 100,
        duration: const Duration(seconds: 90),
        waypoints: 3,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
      expect(r.recovered, isNotNull);
      expect(r.recovered!.metadata?['recovered_from_crash'], isTrue);
      expect(_bannerKm(r),
          'Saved an unfinished run from a previous session (0.10 km, 01:30).');
    });

    test('GPS partial with only 2 waypoints → discarded (track too short)',
        () {
      final partial = _partial(
        distanceMetres: 100,
        duration: const Duration(seconds: 60),
        waypoints: 2,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
      expect(r.recovered, isNull);
      expect(_bannerKm(r),
          'Discarded an unfinished recording from a previous session '
          '(0.10 km, 01:00).');
    });

    test('off-track fixes do not count toward the 3-waypoint line', () {
      // Two line fixes plus canopy fixes the estimator took: the stored
      // track is longer, but the line the threshold has always counted is 2.
      final base = _partial(
        distanceMetres: 100,
        duration: const Duration(seconds: 60),
        waypoints: 4,
      );
      final partial = Run(
        id: base.id,
        startedAt: base.startedAt,
        duration: base.duration,
        distanceMetres: base.distanceMetres,
        track: [
          base.track[0],
          base.track[1].withOffTrack(true),
          base.track[2].withOffTrack(true),
          base.track[3],
        ],
        source: base.source,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
    });

    test('a recovered partial keeps its off-track fixes and track_complete',
        () {
      final base = _partial(
        distanceMetres: 100,
        duration: const Duration(seconds: 90),
        waypoints: 4,
      );
      final partial = Run(
        id: base.id,
        startedAt: base.startedAt,
        duration: base.duration,
        distanceMetres: base.distanceMetres,
        track: [...base.track.take(3), base.track[3].withOffTrack(true)],
        source: base.source,
        metadata: const {'track_complete': true},
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
      expect(r.recovered!.track.last.offTrack, isTrue);
      expect(r.recovered!.metadata?['track_complete'], isTrue);
    });

    test('GPS partial under 50 m → discarded with distance summary', () {
      final partial = _partial(
        distanceMetres: 38,
        duration: const Duration(seconds: 30),
        waypoints: 5,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
      expect(r.bannerPartial?.id, partial.id);
    });

    test('Indoor partial ≥ 60 s → recovered with duration summary', () {
      final partial = _partial(
        distanceMetres: 0,
        duration: const Duration(seconds: 90),
        indoor: true,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
      expect(_bannerKm(r), contains('01:30'));
    });

    test('Indoor partial < 60 s → discarded with duration summary', () {
      final partial = _partial(
        distanceMetres: 0,
        duration: const Duration(seconds: 45),
        indoor: true,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
      expect(_bannerKm(r), contains('00:45'));
    });

    test('banner distance follows the unit preference', () {
      final partial = _partial(
        distanceMetres: 2300,
        duration: const Duration(minutes: 15),
        waypoints: 10,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
      expect(_bannerKm(r), contains('(2.30 km, 15:00)'));
      expect(inProgressBannerText(_en, r, DistanceUnit.mi),
          contains('(1.43 mi, 15:00)'));
    });

    test('Edge: exactly 50 m / 3 waypoints → recovered (≥ thresholds)', () {
      final partial = _partial(
        distanceMetres: 50,
        duration: const Duration(seconds: 30),
        waypoints: 3,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
    });

    test('Edge: 49 m → discarded (just below)', () {
      final partial = _partial(
        distanceMetres: 49,
        duration: const Duration(seconds: 30),
        waypoints: 3,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
    });

    group('resumable (process-kill continuation)', () {
      final now = DateTime.utc(2026, 4, 3, 12);

      test('recent GPS partial → resumable, no banner', () {
        // Saved 6 h ago — a canyon dead-zone stretch. The runner reopens the
        // app; the partial should be offered for resume, not finalized.
        final partial = _partial(
          distanceMetres: 187000,
          duration: const Duration(hours: 40),
          waypoints: 5,
          savedAt: now.subtract(const Duration(hours: 6)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
        expect(r.resumablePartial, isNotNull);
        expect(r.resumablePartial!.id, partial.id,
            reason: 'the raw partial is handed back so resume keeps the id');
        expect(r.recovered, isNull);
        // Interactive prompt on the run screen, not a passive banner.
        expect(r.bannerPartial, isNull);
        expect(_bannerKm(r), isNull);
      });

      test('recent qualifying indoor partial → resumable', () {
        final partial = _partial(
          distanceMetres: 0,
          duration: const Duration(minutes: 20),
          indoor: true,
          savedAt: now.subtract(const Duration(minutes: 30)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
      });

      test('stale qualifying partial (> 48 h) → recovered, not resumable', () {
        final partial = _partial(
          distanceMetres: 5000,
          duration: const Duration(minutes: 40),
          waypoints: 10,
          savedAt: now.subtract(const Duration(hours: 72)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.recovered,
            reason: 'a days-old abandoned partial still auto-finalizes');
        expect(r.resumablePartial, isNull);
        expect(_bannerKm(r), contains('Saved an unfinished run'));
      });

      test('boundary: exactly at the window edge → resumable', () {
        final partial = _partial(
          distanceMetres: 5000,
          duration: const Duration(minutes: 40),
          waypoints: 10,
          savedAt: now.subtract(kResumableWindow),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
      });

      test('recent short partial with some distance → resumable', () {
        // Pre-BUG-006 the 50 m floor discarded this. Any distance is now the
        // runner's to keep or drop.
        final partial = _partial(
          distanceMetres: 30,
          duration: const Duration(seconds: 20),
          waypoints: 5,
          savedAt: now.subtract(const Duration(minutes: 1)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
      });

      test('BUG-006: an 11-minute stationary partial with 11 m → resumable',
          () {
        // A force-close after standing still for 11 minutes: 11 m of GPS
        // jitter on two points. It used to be cleared with "Discarded a 11 m
        // partial recording", which read as eleven minutes.
        final partial = _partial(
          distanceMetres: 11,
          duration: const Duration(minutes: 11),
          waypoints: 2,
          savedAt: now.subtract(const Duration(minutes: 2)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
        expect(r.resumablePartial?.id, partial.id);
        expect(r.bannerPartial, isNull);
      });

      test('recent partial with no distance but a minute of time → resumable',
          () {
        final partial = _partial(
          distanceMetres: 0,
          duration: kResumableMinElapsed,
          savedAt: now.subtract(const Duration(minutes: 2)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
      });

      test('recent empty partial (5 s, 0 m) → discarded with a banner', () {
        final partial = _partial(
          distanceMetres: 0,
          duration: const Duration(seconds: 5),
          savedAt: now.subtract(const Duration(minutes: 1)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.discarded);
        expect(r.resumablePartial, isNull);
        expect(_bannerKm(r),
            'Discarded an unfinished recording from a previous session '
            '(0.00 km, 00:05).');
      });

      test('recent 59 s with no distance → discarded (just below)', () {
        final partial = _partial(
          distanceMetres: 0,
          duration: const Duration(seconds: 59),
          savedAt: now.subtract(const Duration(minutes: 1)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.discarded);
      });

      test('the 48 h window still bounds the lower bar', () {
        // The same 11-minute stationary partial, three days old: nobody is
        // asked, and it does not clear the floor a run saved unasked must.
        final partial = _partial(
          distanceMetres: 11,
          duration: const Duration(minutes: 11),
          waypoints: 2,
          savedAt: now.subtract(const Duration(hours: 72)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.discarded);
        expect(r.resumablePartial, isNull);
        expect(r.recovered, isNull);
      });

      test('just past the window edge → not resumable', () {
        final partial = _partial(
          distanceMetres: 5000,
          duration: const Duration(minutes: 40),
          waypoints: 10,
          savedAt: now
              .subtract(kResumableWindow)
              .subtract(const Duration(seconds: 1)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.recovered);
      });

      test('no in_progress_saved_at stamp → finalizes (recovered), never resumable',
          () {
        // Unknown-age partial: preserve the pre-fix behaviour rather than
        // prompt a resume for a run whose age we can't establish.
        final partial = _partial(
          distanceMetres: 5000,
          duration: const Duration(minutes: 40),
          waypoints: 10,
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.recovered);
      });
    });
  });

  group('inProgressStats', () {
    test('formats distance in the unit and elapsed time as a clock', () {
      final partial = _partial(
        distanceMetres: 11,
        duration: const Duration(minutes: 11, seconds: 2),
      );
      final km = inProgressStats(partial, DistanceUnit.km);
      expect(km.distance, '0.01 km');
      expect(km.duration, '11:02');
      expect(inProgressStats(partial, DistanceUnit.mi).distance, '0.01 mi');
    });

    test('hours show as h:mm:ss', () {
      final partial = _partial(
        distanceMetres: 187000,
        duration: const Duration(hours: 40, minutes: 3, seconds: 9),
      );
      expect(inProgressStats(partial, DistanceUnit.km).duration, '40:03:09');
    });

    test('a pedometer-estimated distance carries the ~ prefix', () {
      final partial = _partial(
        distanceMetres: 1200,
        duration: const Duration(minutes: 10),
        indoor: true,
      );
      expect(inProgressStats(partial, DistanceUnit.km).distance, '~1.20 km');
    });
  });
}
