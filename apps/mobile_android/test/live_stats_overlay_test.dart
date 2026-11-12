// Density of the live recording panel (issue #1300 §1): one row of stat
// tiles paged by tap or swipe instead of seven tiles in two rows, a clock that
// stays the largest thing on the panel, and controls that keep their tap size.
// Pinned on a 360 x 640 dp phone at 1.0x and 2.0x text scale.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart';

const _phone = Size(360, 640);

class _Taps {
  int discard = 0;
  int pause = 0;
  int lap = 0;
  int stop = 0;
}

Widget _host({
  required double textScale,
  required _Taps taps,
  int? bpm,
  bool workoutActive = false,
  bool dockedStop = true,
  bool paceCuesActive = false,
  VoidCallback? onTogglePaceMute,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: LiveStatsOverlay(
          time: '1:23:45',
          distanceValue: '12.34',
          distanceUnit: 'mi',
          primaryValue: '10:24',
          primaryUnit: '/mi',
          primaryLabel: 'Pace',
          secondaryValue: '10:58',
          secondaryLabel: 'Avg Pace',
          calories: '1234',
          elevation: '1024',
          elevationUnit: 'ft',
          steps: '18234',
          cadence: '172',
          bpm: bpm,
          lapCount: 3,
          paused: false,
          stopped: true,
          workoutActive: workoutActive,
          onHoldComplete: dockedStop ? null : () => taps.stop++,
          onDiscard: () => taps.discard++,
          onPauseToggle: () => taps.pause++,
          onLap: () => taps.lap++,
          paceCuesActive: paceCuesActive,
          onTogglePaceMute: onTogglePaceMute ?? () {},
        ),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  await tester.pump();
}

Finder _control(Pattern label) => find.bySemanticsLabel(label);

void main() {
  group('liveStatPages', () {
    const all = LiveStatField.values;

    void expectWellFormed(List<List<LiveStatField>> pages, {required bool hr}) {
      expect(pages.first.length, lessThanOrEqualTo(kLiveStatsGlanceMax));
      for (final p in pages.skip(1)) {
        expect(p.length, inInclusiveRange(1, kLiveStatsPerPage));
      }
      final shown = pages.expand((p) => p).toList();
      expect(shown.toSet().length, shown.length, reason: 'no field twice');
      expect(shown.toSet(),
          all.where((f) => hr || f != LiveStatField.heartRate).toSet(),
          reason: 'paging moves fields, it never drops one');
    }

    test('a plain run glances at distance, pace and average pace', () {
      final pages = liveStatPages(workoutActive: false, hasHeartRate: false);
      expect(pages, [
        [LiveStatField.distance, LiveStatField.pace, LiveStatField.avgPace],
        [
          LiveStatField.elevation,
          LiveStatField.cadence,
          LiveStatField.calories,
          LiveStatField.steps,
        ],
      ]);
      expectWellFormed(pages, hr: false);
    });

    test('a workout step moves average pace off the glance row', () {
      final pages = liveStatPages(workoutActive: true, hasHeartRate: false);
      expect(pages.first, [LiveStatField.distance, LiveStatField.pace]);
      expect(pages[1].first, LiveStatField.avgPace);
      expectWellFormed(pages, hr: false);
    });

    test('a reporting strap takes the glance row third slot', () {
      for (final workout in [false, true]) {
        final pages = liveStatPages(workoutActive: workout, hasHeartRate: true);
        expect(pages.first, [
          LiveStatField.distance,
          LiveStatField.pace,
          LiveStatField.heartRate,
        ]);
        expect(pages.skip(1).map((p) => p.length), [3, 2],
            reason: 'five tiles split evenly, not four and an orphan');
        expectWellFormed(pages, hr: true);
      }
    });
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    group('on a 360 x 640 phone at ${scale}x text', () {
      for (final docked in [true, false]) {
        testWidgets(
            'lays out without overflow, stop ${docked ? 'docked' : 'in row'}',
            (tester) async {
          await _pump(
            tester,
            _host(
              textScale: scale,
              taps: _Taps(),
              bpm: 152,
              workoutActive: true,
              dockedStop: docked,
              paceCuesActive: true,
            ),
          );
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('the clock stays the largest figure on the panel',
          (tester) async {
        await _pump(tester, _host(textScale: scale, taps: _Taps(), bpm: 152));
        final clock = tester.getRect(find.byKey(const Key('liveStatsClock')));
        for (final value in ['12.34', '10:24', '152']) {
          final rect = tester.getRect(find.text(value).hitTestable());
          expect(clock.height, greaterThan(rect.height),
              reason: '$value must not outgrow the clock');
        }
      });

      // A phone in the shell docks the Stop in the nav bar, so the panel holds
      // Discard · Pause · Lap. Every optional band is on: a strap, a workout
      // step, the pace-cue mute.
      testWidgets('leaves the phone at least half of its height',
          (tester) async {
        await _pump(
          tester,
          _host(
            textScale: scale,
            taps: _Taps(),
            bpm: 152,
            workoutActive: true,
            paceCuesActive: true,
          ),
        );
        final panel = tester.getSize(find.byType(LiveStatsOverlay));
        expect(panel.height, lessThanOrEqualTo(_phone.height / 2));
      });

      testWidgets('every control keeps a 48 dp target, apart and tappable',
          (tester) async {
        final taps = _Taps();
        var mutes = 0;
        await _pump(
          tester,
          _host(
            textScale: scale,
            taps: taps,
            dockedStop: false,
            paceCuesActive: true,
            onTogglePaceMute: () => mutes++,
          ),
        );
        final controls = <String, Finder>{
          'mute': find.byKey(const Key('liveStatsPaceMute')),
          'discard': _control('Discard run'),
          'pause': _control('Pause run'),
          'stop': find.byType(HoldToStopButton),
          'lap': _control(RegExp(r'^Mark lap, 3 so far')),
        };
        final rects = <String, Rect>{};
        for (final MapEntry(:key, :value) in controls.entries) {
          expect(value, findsOneWidget, reason: key);
          final r = tester.getRect(value);
          expect(r.width, greaterThanOrEqualTo(48), reason: key);
          expect(r.height, greaterThanOrEqualTo(48), reason: key);
          expect(r.left, greaterThanOrEqualTo(0), reason: key);
          expect(r.right, lessThanOrEqualTo(_phone.width), reason: key);
          rects[key] = r;
        }
        final names = rects.keys.toList();
        for (var i = 0; i < names.length; i++) {
          for (var j = i + 1; j < names.length; j++) {
            expect(rects[names[i]]!.overlaps(rects[names[j]]!), isFalse,
                reason: '${names[i]} overlaps ${names[j]}');
          }
        }
        for (final key in ['mute', 'discard', 'pause', 'lap']) {
          await tester.tap(controls[key]!);
        }
        expect([mutes, taps.discard, taps.pause, taps.lap], [1, 1, 1, 1]);
      });
    });
  }

  testWidgets('tapping the stats row pages through and wraps around',
      (tester) async {
    await _pump(tester, _host(textScale: 1.0, taps: _Taps()));
    final pager = find.byKey(const Key('liveStatsPager'));
    expect(find.text('Avg Pace').hitTestable(), findsOneWidget);
    expect(find.text('Calories').hitTestable(), findsNothing);
    expect(find.bySemanticsLabel('Stats page 1 of 2'), findsOneWidget);

    await tester.tap(pager);
    await tester.pump();
    expect(find.text('Calories').hitTestable(), findsOneWidget);
    expect(find.text('Avg Pace').hitTestable(), findsNothing);
    expect(find.bySemanticsLabel('Stats page 2 of 2'), findsOneWidget);

    await tester.tap(pager);
    await tester.pump();
    expect(find.text('Avg Pace').hitTestable(), findsOneWidget);
  });

  testWidgets('paging does not change the panel height', (tester) async {
    await _pump(tester, _host(textScale: 2.0, taps: _Taps(), bpm: 152));
    final before = tester.getSize(find.byType(LiveStatsOverlay)).height;
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('liveStatsPager')));
      await tester.pump();
      expect(tester.getSize(find.byType(LiveStatsOverlay)).height, before);
    }
  });

  testWidgets('a strap dropping out on its last page lands on a real page',
      (tester) async {
    final taps = _Taps();
    await _pump(tester, _host(textScale: 1.0, taps: taps, bpm: 152));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('liveStatsPager')));
      await tester.pump();
    }
    expect(find.bySemanticsLabel('Stats page 3 of 3'), findsOneWidget);
    await tester.pumpWidget(_host(textScale: 1.0, taps: taps));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Stats page 2 of 2'), findsOneWidget);
  });
}
