import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../lib/local_run_store.dart';
import '../../lib/main.dart';
import '../app_harness.dart';
import 'demo_data.dart';
import 'store_selectors.dart';

// The store-listing screenshots, captured from the real app on seeded demo
// data (issue #1375). Not a `*_test.dart` file on purpose: it signs in to a
// seeded local Supabase stack that the `mobile-android-e2e` job does not
// start, so `flutter test integration_test` must not load it. It runs only
// through `flutter drive` from `.github/workflows/store-screenshots.yml`:
//
//   flutter drive --profile -d <device> \
//     --driver integration_test/store/store_screenshots_driver.dart \
//     --target integration_test/store/store_screenshots_capture.dart \
//     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
//     --dart-define=DEV_USER_EMAIL=store-demo@threkir.test \
//     --dart-define=DEV_USER_PASSWORD=storedemo \
//     --dart-define=WEB_BASE_URL=http://10.0.2.2:7777
//
// The app signs itself in through its own dev auto-login, which only fires
// against a loopback SUPABASE_URL (dev_auto_login.dart). The account, its
// plan and its coach thread come from assets/store/demo/store_demo_seed.sql;
// the runs are written into the device's run store here, before launch,
// because their tracks are files the SQL cannot seed. The app pushes them on
// sign-in, the server links each to its plan session, and the workflow's job
// worker map-matches them (passthrough, no OSRM), so the capture waits for
// all three before it photographs anything. WEB_BASE_URL points at
// a loopback port where nothing listens, so the capability read the coach
// makes fails closed instead of reaching production. Every screen is dark
// (the app's default) except the training plan, which is the one light panel.
//
// Each capture is named for its panel in assets/store/panels.json, which is
// what the renderer composes from.

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
    final hero = runs.firstWhere((r) => r.id == kHeroRunId);

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
    // The record panel's map reads the run's map-match row once, when it
    // opens, so the row must have left `pending` first or the map carries a
    // "Snapping to roads" pill. The workflow's job worker settles it.
    RunMatchInfo? match;
    await pumpUntilAsync(tester, () async {
      match = await api.fetchRunMatchedTrack(kHeroRunId);
      return match != null && match!.status != MatchStatus.pending;
    }, describe: 'the job worker to map-match the hero run (is it running?)');
    if (match!.status != MatchStatus.matched) {
      fail('the hero run was map-matched as ${match!.status.name}, not '
          'matched: the record panel would show that status on its map');
    }

    // Android draws Flutter into an image view so the binding can read it
    // back; iOS reads the layer directly.
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
    }

    themeModeNotifier.value = ThemeMode.dark;
    for (final ready in StoreSelectors.todayReady) {
      await pumpUntilFound(tester, ready, describe: 'Today to draw $ready');
    }
    await pumpUntil(tester, () => StoreSelectors.todayMissedPrompt.evaluate().isEmpty,
        describe: 'Today to re-read the plan once the server linked the runs');
    await settle(tester);
    await binding.takeScreenshot('today');

    final navigator = tester.state<NavigatorState>(
        find.descendant(of: find.byType(MaterialApp), matching: find.byType(Navigator)).first);

    Future<void> capture(String name, Widget screen, Finder ready,
        {ThemeMode theme = ThemeMode.dark,
        Duration settleFor = const Duration(seconds: 3),
        Finder? absent}) async {
      themeModeNotifier.value = theme;
      navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
      await pumpUntilFound(tester, ready, describe: 'the $name screen to load');
      await settle(tester, settleFor);
      if (absent != null) {
        expect(absent, findsNothing,
            reason: 'the $name screen still shows $absent after settling');
      }
      await binding.takeScreenshot(name);
      navigator.pop();
      themeModeNotifier.value = ThemeMode.dark;
      await settle(tester, const Duration(seconds: 1));
    }

    final fullHero = await app.runStore.runById(hero.id) ?? hero;
    // Map tiles arrive over the network after the map is laid out.
    await capture('record', StoreSelectors.runDetail(app, fullHero),
        StoreSelectors.runDetailReady,
        settleFor: const Duration(seconds: 10),
        absent: StoreSelectors.matchPill(
            l10nOf(tester, StoreSelectors.shell)));
    await capture('train', StoreSelectors.planDetail(app),
        StoreSelectors.planDetailReady,
        theme: ThemeMode.light);
    await capture('coach', StoreSelectors.coach(app), StoreSelectors.coachReady);
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

/// Pump real frames while polling [condition], an async read such as a
/// server row, about once a second; fails with [describe] at [timeout].
Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required String describe,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    var met = false;
    try {
      met = await condition();
    } catch (e) {
      debugPrint('store capture: waiting for $describe: $e');
    }
    if (met) return;
    if (!DateTime.now().isBefore(deadline)) {
      fail('timed out after ${timeout.inSeconds} s waiting for $describe');
    }
    await settle(tester, const Duration(seconds: 1));
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
