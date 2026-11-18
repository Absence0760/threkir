import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../lib/local_run_store.dart';
import '../../lib/main.dart';
import '../../lib/screens/plan_detail_screen.dart';
import '../../lib/screens/progress_screen.dart';
import '../../lib/screens/run_detail_screen.dart';
import '../../lib/widgets/disclosure_section.dart';
import '../app_harness.dart';
import 'demo_data.dart';
import 'store_capture_kit.dart';
import 'store_numbers.dart';
import 'store_selectors.dart';

// The store-listing screenshots, captured from the real app on seeded demo
// data (issue #1375). Not a `*_test.dart` file on purpose: it signs in to a
// seeded local Supabase stack that the `mobile-android-e2e` job does not
// start, so `flutter test integration_test` must not load it. It runs only
// through `flutter drive` from `.github/workflows/store-screenshots.yml`:
//
//   bash assets/store/capture.sh <device-id> <output dir>
//
// which runs `flutter drive` in profile mode on the Android emulator and in
// debug on an iOS simulator (which cannot run a profile build), with the
// dart-defines for the local stack listed there.
//
// The app signs itself in through its own dev auto-login, which only fires
// against a loopback SUPABASE_URL (dev_auto_login.dart). The account, its
// plan and its coach thread come from assets/store/demo/store_demo_seed.sql;
// the runs are written into the device's run store here, before launch,
// because their tracks are files the SQL cannot seed. The app pushes them on
// sign-in and the server links each to its plan session, so the capture
// waits for both before it photographs anything. WEB_BASE_URL points at
// a loopback port where nothing listens, so the capability read the coach
// makes fails closed instead of reaching production.
//
// Each capture is named for what assets/store/panels.json crops from it
// (run-zones, run-splits, run-pacing, progress, plan, coach) and is the
// pushed screen's own layer rather than a platform screenshot
// (store_capture_kit.dart), so the Android emulator and the iOS simulator
// produce the same files: the PNGs, bounds.json (where each section sits)
// and numbers.json (what the screens say, store_numbers.dart). The run
// detail and Progress are laid out 320 dp wide at the panel's pixel ratio;
// the plan and the coach keep the device's width. The run captures and the
// coach are dark, the predictor and the plan light, as their panels are.

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the store listing screens', (tester) async {
    final runs = demoRuns(DateTime.now());
    final seeded = LocalRunStore();
    await seeded.init();
    for (final run in runs) {
      await seeded.save(run);
    }
    await seeded.debugWritesSettled();

    await launchApp(onboarded: true);
    await pumpUntilFound(tester, StoreSelectors.shell,
        describe: 'the cold launch to reach the Home shell');

    final app = tester.widget<RunApp>(find.byType(RunApp));
    final api = app.apiClient;
    if (api == null) {
      fail('the app started without a Supabase client: pass SUPABASE_URL and '
          'SUPABASE_ANON_KEY for the local stack as --dart-define');
    }
    await pumpUntil(tester, () => api.userId != null,
        describe: 'the dev auto-login to sign in as $kDemoEmail');

    // The sign-in sync pushes the seeded runs; asking again is a no-op while
    // that push is in flight and a retry if it failed.
    unawaited(app.syncService.triggerSync('manual'));
    await pumpUntil(tester, () => runs.every((r) => app.runStore.isSynced(r.id)),
        describe: 'the ${runs.length} seeded runs to reach the server');
    final onDevice = app.runStore.summaryRuns.length;
    if (onDevice != runs.length) {
      fail('the device holds $onDevice runs where ${runs.length} were seeded: '
          'every count on Today and Progress would be off');
    }

    final l10n = l10nOf(tester, StoreSelectors.shell);
    themeModeNotifier.value = ThemeMode.dark;
    for (final ready in StoreSelectors.todayReady) {
      await pumpUntilFound(tester, ready, describe: 'Today to draw $ready');
    }
    // The plan panel's week grid ticks a session only once the server has
    // linked its run, which Today shows by dropping its "missed" prompt.
    await pumpUntil(tester, () => StoreSelectors.todayMissedPrompt.evaluate().isEmpty,
        describe: 'Today to re-read the plan once the server linked the runs');

    // The device's own size, for the plan and coach captures, and the
    // 320 dp column the run-detail and Progress captures are laid out at.
    final deviceDpr = tester.view.devicePixelRatio;
    final deviceDp = tester.view.physicalSize / deviceDpr;
    if (Platform.isIOS &&
        (deviceDp.width.round() != 440 || deviceDpr.round() != 3)) {
      fail('the App Store 6.9" set needs a 440 pt @3x simulator (1320 x 2868, '
          'an iPhone Pro Max class); this one is ${deviceDp.width} pt @${deviceDpr}x');
    }
    final columnDpr = (Platform.isIOS ? 1173.0 : 960.0) / kColumnDp;

    final navigator = tester.state<NavigatorState>(
        find.descendant(of: find.byType(MaterialApp), matching: find.byType(Navigator)).first);
    final boundary = GlobalKey();
    final shots = StoreCaptureSet();

    /// Push [screen] in [theme], optionally laid out [columnDp] wide at the
    /// column's pixel ratio, at a text scale, or taller than the device.
    Future<void> open(Widget screen, Finder ready,
        {required ThemeMode theme,
        bool column = false,
        double textScale = 1,
        double? heightDp,
        Duration settleFor = const Duration(seconds: 3)}) async {
      themeModeNotifier.value = theme;
      final dpr = column ? columnDpr : deviceDpr;
      final width = column ? kColumnDp : deviceDp.width;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize =
          Size(width, math.max(heightDp ?? 0, deviceDp.height)) * dpr;
      if (textScale != 1) {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
      }
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => captureBoundary(boundary, screen)));
      await pumpUntilFound(tester, ready, describe: 'the screen with $ready to load');
      await settle(tester, settleFor);
    }

    Future<void> close() async {
      navigator.pop();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      themeModeNotifier.value = ThemeMode.dark;
      await settle(tester, const Duration(seconds: 1));
    }

    /// Scroll [target] into the screen's list, then to just below its top.
    Future<Rect> reveal(Type screen, Finder target) async {
      await tester.scrollUntilVisible(target, 300,
          scrollable: find
              .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
              .first,
          maxScrolls: 200);
      await revealNearTop(tester, target);
      await settle(tester, const Duration(seconds: 1));
      return viewportOf(tester, target);
    }

    Map<String, Rect> inside(Rect viewport, Iterable<String> names) =>
        {for (final n in names) n: viewport};

    // ---- run detail, 320 dp, dark: the zones, then the splits.
    final hero = (await app.runStore.runById(kHeroRunId)) ??
        runs.firstWhere((r) => r.id == kHeroRunId);
    final run = <String, Object?>{};
    await open(StoreSelectors.runDetail(app, hero), StoreSelectors.runDetailReady,
        theme: ThemeMode.dark, column: true);
    var viewport = await reveal(RunDetailScreen, StoreSelectors.hrZonesTitle);
    run.addAll(zoneNumbers(tester, hero, l10n));
    shots.captures.add(await captureScreen(tester,
        name: 'run-zones',
        boundary: boundary,
        pixelRatio: columnDpr,
        sections: {
          'hr-zones': [StoreSelectors.hrZonesTitle, StoreSelectors.hrZonesLegend],
        },
        viewports: inside(viewport, ['hr-zones'])));

    viewport = await reveal(RunDetailScreen, StoreSelectors.splitsTitle);
    run.addAll(splitNumbers(tester, hero, l10n));
    final kms = (run['splits']! as List).length;
    final splitSections = {
      'splits-title': [StoreSelectors.splitsTitle],
      'pacing-card': [StoreSelectors.pacingCard],
      'gap-header': [StoreSelectors.gapHeader],
      for (var km = 1; km <= kms; km++)
        'split-row-$km': [StoreSelectors.splitRow(km)],
      'splits-hint': [StoreSelectors.splitsHint],
    };
    shots.captures.add(await captureScreen(tester,
        name: 'run-splits',
        boundary: boundary,
        pixelRatio: columnDpr,
        sections: splitSections,
        viewports: inside(viewport, splitSections.keys),
        colourAt: {'pacing-card': ('pacing-card', const Offset(40, 4))}));
    await close();

    // ---- run detail at text scale 1.5: the app lays the pacing card out
    // larger itself (spec C4), rather than the renderer scaling pixels.
    await open(StoreSelectors.runDetail(app, hero), StoreSelectors.runDetailReady,
        theme: ThemeMode.dark, column: true, textScale: 1.5);
    viewport = await reveal(RunDetailScreen, StoreSelectors.splitsTitle);
    final pacingSections = {
      'splits-title': [StoreSelectors.splitsTitle],
      'pacing-card': [StoreSelectors.pacingCard],
      'gap-header': [StoreSelectors.gapHeader],
      'split-row-1': [StoreSelectors.splitRow(1)],
      'split-row-2': [StoreSelectors.splitRow(2)],
    };
    shots.captures.add(await captureScreen(tester,
        name: 'run-pacing',
        boundary: boundary,
        pixelRatio: columnDpr,
        sections: pacingSections,
        viewports: inside(viewport, pacingSections.keys),
        colourAt: {'pacing-card': ('pacing-card', const Offset(40, 4))}));
    await close();

    // ---- Progress, 320 dp, light: the Race-time predictor.
    await open(StoreSelectors.progress(app), find.byType(ProgressScreen),
        theme: ThemeMode.light, column: true);
    viewport = await reveal(ProgressScreen, StoreSelectors.predictorCard);
    final predictor = predictorNumbers(
        tester, app.runStore.summaryRuns, DateTime.now(), l10n);
    final rungSections = {
      'predictor-card': [StoreSelectors.predictorCard],
      for (final (name, metres) in const [
        ('5k', 5000.0),
        ('10k', 10000.0),
        ('half', 21097.5),
        ('marathon', 42195.0),
      ])
        'predictor-row-$name': [StoreSelectors.predictorRow(metres)],
    };
    shots.captures.add(await captureScreen(tester,
        name: 'progress',
        boundary: boundary,
        pixelRatio: columnDpr,
        sections: rungSections,
        viewports: inside(viewport, rungSections.keys),
        colourAt: {
          'predictor-row-half': ('predictor-row-half', const Offset(1, 3)),
        }));
    await close();

    // ---- the plan, device width, light, with "Plan progress" open (spec
    // open issue 3). Taller than the device, so the progress card is on
    // screen with the header; the crops take the sections, not the height.
    await open(StoreSelectors.planDetail(app), StoreSelectors.planDetailReady,
        theme: ThemeMode.light, heightDp: 1600);
    await tester.scrollUntilVisible(StoreSelectors.planProgress, 300,
        scrollable: find
            .descendant(
                of: find.byType(PlanDetailScreen), matching: find.byType(Scrollable))
            .first);
    if (!tester.widget<DisclosureSection>(StoreSelectors.planProgress).open) {
      await tester.tap(find.descendant(
          of: StoreSelectors.planProgress,
          matching: find.text(l10n.planDetailSectionProgressTitle)));
      await settle(tester, const Duration(seconds: 1));
    }
    await revealNearTop(tester, StoreSelectors.planTitle, marginDp: 0);
    await settle(tester, const Duration(seconds: 1));
    viewport = viewportOf(tester, StoreSelectors.planHeroCard);
    final plan = await planNumbers(tester, app.training, kDemoPlanId);
    final planSections = {
      'plan-header': [StoreSelectors.planTitle, StoreSelectors.planHeroCard],
      'plan-week': [StoreSelectors.planWeek],
      'plan-progress': [StoreSelectors.planProgress],
    };
    shots.captures.add(await captureScreen(tester,
        name: 'plan',
        boundary: boundary,
        pixelRatio: deviceDpr,
        sections: planSections,
        viewports: inside(viewport, planSections.keys)));
    await close();

    // ---- the coach, device width, dark: the context chips and the last
    // exchange. The usage banner and a typing indicator must sit outside
    // both crops; the capture fails rather than hide them in the app.
    await open(StoreSelectors.coach(app), StoreSelectors.coachReady,
        theme: ThemeMode.dark);
    final question = tester.getRect(StoreSelectors.coachLastQuestion);
    final answer = tester.getRect(StoreSelectors.coachLastAnswer);
    if (answer.top <= question.bottom) {
      fail('the thread does not end on an answer to "$kDemoCoachPhrase"');
    }
    shots.captures.add(await captureScreen(tester,
        name: 'coach',
        boundary: boundary,
        pixelRatio: deviceDpr,
        sections: {
          'coach-context': [StoreSelectors.coachContext],
          'coach-last-exchange': [
            StoreSelectors.coachLastQuestion,
            StoreSelectors.coachLastAnswer,
          ],
        },
        viewports: {
          'coach-last-exchange': viewportOf(tester, StoreSelectors.coachLastAnswer),
        },
        forbidden: StoreSelectors.coachForbidden));
    await close();

    // The same read the coach uses to pick its daily allowance.
    final tier = await api.isPro() ? 'pro' : 'free';

    binding.reportData = shots.reportData({
      'schema': 1,
      'tier': tier,
      'labels': {'grade_adj': l10n.runDetailGapColumn},
      'run': run,
      'predictor': predictor,
      'plan': plan,
    });
  });
}

/// Pump real frames for [duration], so loads that finish after the ready
/// finder matched (images, map tiles, a second fetch) are on screen.
/// `pumpAndSettle` would never return: the map and the dashboard animate.
Future<void> settle(WidgetTester tester,
    [Duration duration = const Duration(seconds: 3)]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pump real frames until [condition] holds, failing with [describe] at
/// [timeout]. The non-widget sibling of `pumpUntilFound`.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String describe,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('timed out after ${timeout.inSeconds} s waiting for $describe');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
