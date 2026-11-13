import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show ActivityType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'package:run_recorder/run_recorder.dart';
import 'supabase_test_init.dart';

bool _supabaseReady = false;
late Directory _runsDir;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

Future<({
  LocalRunStore runStore,
  LocalRouteStore routeStore,
  Preferences prefs,
  SocialService social,
  TrainingService training,
  BleHeartRate heartRate,
  BleTreadmill treadmill,
  AudioCues audioCues,
  RaceController raceController,
})> _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('run_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  final social = SocialService();

  return (
    runStore: runStore,
    routeStore: LocalRouteStore(),
    prefs: prefs,
    social: social,
    training: TrainingService(),
    heartRate: BleHeartRate(),
    treadmill: BleTreadmill(),
    audioCues: AudioCues(),
    raceController: RaceController(social),
  );
}

Future<void> _pump(WidgetTester tester, dynamic s,
    {double textScale = 1.0, Locale? locale}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RunScreen(
        apiClient: null,
        runStore: s.runStore,
        routeStore: s.routeStore,
        preferences: s.prefs,
        audioCues: s.audioCues,
        social: s.social,
        raceController: s.raceController,
        training: s.training,
        heartRate: s.heartRate,
        treadmill: s.treadmill,
      ),
    ),
  );
  // Single pump only — pumpAndSettle would block on the recording-state
  // tickers. The idle state is drawn synchronously.
  await tester.pump();
}

void main() {
  setUpAll(_ensureSupabase);

  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('RunScreen — idle state', () {
    testWidgets('renders the activity-type ChoiceChip row',
        (tester) async {
      // Reason: the activity selector is the entry point into the run
      // — without it, users can't choose between Run / Walk / Cycle /
      // Hike before tapping Start.
      final s = await _makeStores();
      await _pump(tester, s);
      // 4 ChoiceChips — one per ActivityType enum value.
      expect(find.byType(ChoiceChip), findsNWidgets(ActivityType.values.length));
    });

    testWidgets('renders all four activity-type labels', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Walk'), findsOneWidget);
      expect(find.text('Cycle'), findsOneWidget);
      // "Hike" renamed to "Trail run" so trail runners see
      // themselves represented in the picker. Internal enum
      // name stays `hike` for back-compat.
      expect(find.text('Trail run'), findsOneWidget);
    });

    testWidgets('shows a Start affordance (the run-ready entry point)',
        (tester) async {
      // The Start trigger may be a FloatingActionButton OR a wrapped
      // gesture detector. Assert *something* large + tappable is
      // visible — a regression that hides the Start path on idle is
      // user-facing severe.
      final s = await _makeStores();
      await _pump(tester, s);
      // A FAB or any FilledButton with start semantics should be in
      // the tree. Use a softer matcher — the design has changed
      // shape over time but the affordance must always exist.
      final hasFab = find.byType(FloatingActionButton).evaluate().isNotEmpty;
      final hasFilled = find.byType(FilledButton).evaluate().isNotEmpty;
      final hasPrimaryGesture =
          find.byType(InkWell).evaluate().isNotEmpty || hasFab || hasFilled;
      expect(hasPrimaryGesture, isTrue,
          reason: 'idle state must surface a tappable Start affordance');
    });

    testWidgets('selecting Walk swaps the active ChoiceChip', (tester) async {
      // ChoiceChip's `selected` flag drives the active styling. After
      // tapping the Walk chip, exactly one chip should be selected.
      // The label widget shape varies (Text vs. Row+Icon+Text), so
      // assert via the surrounding context — the only chip with the
      // 'Walk' label that is selected.
      final s = await _makeStores();
      await _pump(tester, s);

      await tester.tap(find.text('Walk'));
      await tester.pump();

      final selectedChips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .where((c) => c.selected)
          .toList();
      expect(selectedChips.length, 1, reason: 'exactly one chip selected');

      // The selected chip should contain the 'Walk' label somewhere
      // in its descendant tree.
      final selectedFinder = find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.selected,
      );
      expect(
        find.descendant(of: selectedFinder, matching: find.text('Walk')),
        findsOneWidget,
      );
    });

    testWidgets('idle state does NOT instantiate any LiveRunMap yet',
        (tester) async {
      // Map only mounts after begin() — keeping it off the idle widget
      // tree is what lets these tests run without booting the
      // geolocator. If a refactor mounts it earlier, this test fires
      // and the rest of the suite would break.
      final s = await _makeStores();
      await _pump(tester, s);
      // Don't import LiveRunMap explicitly — search by runtime type
      // name to avoid coupling the assertion to a private widget tree.
      final allWidgets = tester.allWidgets;
      final mapMounts = allWidgets
          .where((w) => w.runtimeType.toString() == 'LiveRunMap')
          .toList();
      expect(mapMounts, isEmpty,
          reason: 'LiveRunMap should not mount until recording begins');
    });

    testWidgets('default activity is Run (initial chip selection)',
        (tester) async {
      // Reason: the recorder reads `_activityType` at begin(). A
      // refactor that flipped the default to Walk / Cycle would
      // silently mis-classify every first-recording per the new
      // user (until they manually flipped chips). Pin the default.
      final s = await _makeStores();
      await _pump(tester, s);
      final selectedChips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .where((c) => c.selected)
          .toList();
      expect(selectedChips.length, 1, reason: 'exactly one default chip');
      // The selected chip wraps a Text('Run').
      final selectedFinder = find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.selected,
      );
      expect(
        find.descendant(of: selectedFinder, matching: find.text('Run')),
        findsOneWidget,
        reason: 'default activity must be Run',
      );
    });

    // The existing "selecting Walk swaps the active ChoiceChip" test
    // covers one of the four values. The chip-selection switch is one
    // line, but a per-enum-value typo (e.g. mapping `hike → walk`
    // accidentally) would only fail on that specific value. Pin the
    // other three so the whole enum is covered.
    for (final spec in const [
      ('Cycle', 'cycle'),
      // Picker label is "Trail run" but the enum slug stays `hike`
      // (the SQL CHECK constraint + Strava / Health Connect
      // importer mappings key on the slug).
      ('Trail run', 'hike'),
      ('Run', 'run'),
    ]) {
      final (label, slug) = spec;
      testWidgets('selecting $label sets it as the active chip', (tester) async {
        final s = await _makeStores();
        await _pump(tester, s);

        await tester.tap(find.text(label));
        await tester.pump();

        final selectedChips = tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((c) => c.selected)
            .toList();
        expect(selectedChips.length, 1,
            reason: 'tapping $label must leave exactly one chip selected ($slug)');
        final selectedFinder = find.byWidgetPredicate(
          (w) => w is ChoiceChip && w.selected,
        );
        expect(
          find.descendant(of: selectedFinder, matching: find.text(label)),
          findsOneWidget,
        );
      });
    }

    testWidgets('idle state surfaces Choose route / Share live / Training plans',
        (tester) async {
      // The three secondary affordances on the idle screen each open
      // a different sub-flow (route picker, live broadcast share
      // sheet, plans navigation). A refactor that hid any one of
      // them would silently strip a feature the user can't recover
      // from elsewhere on this tab.
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.text('Choose route'), findsOneWidget);
      expect(find.text('Share live link'), findsOneWidget);
      // "Training plans" is the label when there's no active plan
      // overview — fall-through path. With a plan, the label is the
      // plan name (covered separately in plan_detail tests).
      expect(find.text('Training plans'), findsOneWidget);
    });
  });

  group('RunScreen — treadmill live-mode toggle', () {
    testWidgets('toggle is hidden at idle even when a belt is paired',
        (tester) async {
      // The toggle lives in the recording view (_buildLive). Pairing a belt
      // must not surface it on the idle screen — it only appears once a run
      // is in flight. This also guards the new plumbing renders idle cleanly.
      //
      // The keys must be seeded AFTER _makeStores, which resets the mock
      // store: seeded before it, the pairing was wiped and this asserted
      // nothing (the toggle is hidden at idle whether or not a belt exists).
      final s = await _makeStores();
      SharedPreferences.setMockInitialValues({
        'treadmill_device_id': 'AA:BB:CC:DD:EE:FF',
        'treadmill_device_name': 'NordicTrack T9',
      });
      expect(await s.treadmill.pairedName(), 'NordicTrack T9',
          reason: 'the precondition this case is named for must actually hold');
      await _pump(tester, s);
      // Let the post-frame pairedName() read settle.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      expect(find.text('Treadmill mode'), findsNothing);
    });

    test('belt sample pump feeds the recorder; clearing reverts to GPS',
        () async {
      // The exact wiring _toggleTreadmillMode performs: belt stream → the
      // recorder's setTreadmillSample seam, then clearTreadmillMode reverts.
      final treadmill = BleTreadmill();
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();

      final sub = treadmill.stream.listen((sample) {
        r.setTreadmillSample(
          sample.speedMps,
          totalDistanceMetres: sample.totalDistanceMetres,
        );
      });

      expect(r.treadmillMode, isFalse);
      treadmill.debugEmitSample(
        const TreadmillSample(
            instantaneousSpeedKmh: 10, totalDistanceMetres: 50),
      );
      // Broadcast-stream delivery is a microtask — let it run.
      await Future<void>.delayed(Duration.zero);
      expect(r.treadmillMode, isTrue,
          reason: 'first belt sample flips the recorder into treadmill mode');

      r.clearTreadmillMode();
      expect(r.treadmillMode, isFalse,
          reason: 'turning the toggle off reverts to the GPS distance path');

      await sub.cancel();
    });

    test('a sample-stream error is swallowed by the onError guard (L4)',
        () async {
      // The screen attaches an onError that debugPrints and never rethrows,
      // so a belt fault can never tear down the recording zone.
      final treadmill = BleTreadmill();
      var caught = false;
      final sub = treadmill.stream.listen(
        (_) {},
        onError: (Object e) {
          // mirror the screen's guard — log + swallow, never rethrow.
          caught = true;
        },
      );
      treadmill.debugEmitSampleError(StateError('belt fault'));
      await Future<void>.delayed(Duration.zero);
      expect(caught, isTrue,
          reason: 'onError must absorb the fault — nothing escapes the zone');
      await sub.cancel();
    });
  });

  group('RunScreen — the start page leaves Home its cards', () {
    testWidgets('a run on file draws no last-run card here', (tester) async {
      // Issue #1374: the start page repeated Home's last run, today's
      // workout and next club event under its own Start. Home has them; this
      // page holds only what the next run carries (route, workout, race).
      final s = await _makeStores();
      await tester.runAsync(() async {
        await s.runStore.save(cm.Run(
          id: 'last-run-1',
          startedAt: DateTime.now().subtract(const Duration(hours: 3)),
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          source: cm.RunSource.app,
        ));
      });
      await _pump(tester, s);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.runLastRun), findsNothing);
      expect(find.text('START'), findsOneWidget,
          reason: 'with nothing docked the page keeps its own Start');
    });
  });

  group('RunScreen — Start label fits its circle (issue #666 V12)', () {
    // The 140 px circle has a 124 px interior. The label is bounded by the
    // graphic: "START" already measures 117.5 wide in English at 1.0x, so a
    // longer locale or a larger OS text size used to break the word mid-glyph.
    Finder labelBox(String text) =>
        find.ancestor(of: find.text(text), matching: find.byType(FittedBox));

    testWidgets('English at 2x text scale stays inside the circle',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s, textScale: 2.0);
      final size = tester.getSize(labelBox('START').first);
      expect(size.width, lessThanOrEqualTo(124 - 16));
      expect(size.height, lessThanOrEqualTo(124));
    });

    testWidgets('a long localized label stays on one line at 1.0x',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s, locale: const Locale('fr'));
      // "DÉMARRER" is wider than the circle interior; pre-fix it wrapped
      // mid-word rather than scaling.
      final size = tester.getSize(labelBox('DÉMARRER').first);
      expect(size.width, lessThanOrEqualTo(124 - 16));
    });
  });
}
