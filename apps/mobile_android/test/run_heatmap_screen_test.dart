// Widget tests for RunHeatmapScreen — the mobile mirror of web
// /runs/heatmap. The runs + track downloads are supplied through the
// fetchRunsFn / fetchTrackFn test seams so the chain (runs → track
// download → cell aggregation → render) is exercised without the
// network. flutter_map tile fetches fail under the test runner (same
// constraint the routes-heatmap test deals with); we pin the chrome +
// the data path + the legend / empty states, not tile-load success.

import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show PageHeading;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/screens/run_heatmap_screen.dart';
import '../lib/widgets/live_run_map.dart' show mapHeatOpacity, mapHeatRamp;
import '../lib/widgets/map_attribution.dart';
import 'pump_until.dart';
import 'worst_case_layout.dart';

/// The screen reads the viewer id to decide whether to fetch server
/// runs at all, so a fake must declare it rather than falling through
/// to a real (uninitialised) Supabase read.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.viewerId = 'u-viewer'});
  final String? viewerId;
  @override
  String? get userId => viewerId;
}

cm.Run _run(String id, {String? trackUrl}) => cm.Run(
      id: id,
      startedAt: DateTime.utc(2026, 1, 1),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: cm.RunSource.app,
      metadata: trackUrl == null ? null : {'track_url': trackUrl},
    );

cm.Run _localRun(String id) => cm.Run(
      id: id,
      startedAt: DateTime.utc(2026, 1, 2),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: cm.RunSource.app,
      track: _track(),
    );

List<cm.Waypoint> _track() => const [
      cm.Waypoint(lat: 51.5, lng: -0.12),
      cm.Waypoint(lat: 51.5001, lng: -0.1201),
      cm.Waypoint(lat: 51.5002, lng: -0.1202),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<cm.Run>> Function() fetchRunsFn,
  required Future<List<cm.Waypoint>> Function(String) fetchTrackFn,
  ApiClient? api,
  LocalRunStore? runStore,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunHeatmapScreen(
        api: api ?? _FakeApiClient(),
        runStore: runStore,
        fetchRunsFn: fetchRunsFn,
        fetchTrackFn: fetchTrackFn,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

// A map that reaches the screen bottom drew its credit under the system
// navigation bar (route builder field report; same root cause here).
void simulateNavBar(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(bottom: 48);
  addTearDown(tester.view.reset);
}

void expectCreditsAboveNavBar(WidgetTester tester) =>
    expectCreditsAboveNavBarAt(tester, 780);

void expectCreditsAboveNavBarAt(WidgetTester tester, double height) {
  final credits = find.descendant(
      of: find.byType(MapAttribution), matching: find.byType(Text));
  expect(credits, findsWidgets);
  for (final credit in credits.evaluate()) {
    final rect = tester.getRect(find.byWidget(credit.widget));
    expect(rect.bottom, lessThanOrEqualTo(height - 48),
        reason: 'credit $rect is under the navigation bar');
  }
}

void main() {
  testWidgets('the map credit stays above the navigation bar',
      (tester) async {
    simulateNavBar(tester);
    await _pump(
      tester,
      fetchRunsFn: () async => [_run('a', trackUrl: 'u/a.json.gz')],
      fetchTrackFn: (_) async => _track(),
    );
    expectCreditsAboveNavBar(tester);
  });

  testWidgets('renders the heatmap chrome', (tester) async {
    await _pump(
      tester,
      fetchRunsFn: () async => [_run('a', trackUrl: 'u/a.json.gz')],
      fetchTrackFn: (_) async => _track(),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.widgetWithText(AppBar, l10n.runHeatmapTitle), findsOneWidget);
  });


  testWidgets('aggregates downloaded tracks and shows the legend',
      (tester) async {
    var trackCalls = 0;
    await _pump(
      tester,
      fetchRunsFn: () async => [
        _run('a', trackUrl: 'u/a.json.gz'),
        _run('b', trackUrl: 'u/b.json.gz'),
      ],
      fetchTrackFn: (_) async {
        trackCalls++;
        return _track();
      },
    );
    // Let the bounded-concurrency downloads + aggregation settle.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(trackCalls, 2);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // Both tracks aggregated → the two-run legend summary, distinct from
    // the AppBar/legend title (which share the "Your heatmap" string).
    expect(find.text(l10n.runHeatmapLegendSummary(2)), findsOneWidget);
  });

  testWidgets('cells and legend paint the basemap\'s heat ramp, not one '
      'fixed set', (tester) async {
    await _pump(
      tester,
      fetchRunsFn: () async => [_run('a', trackUrl: 'u/a.json.gz')],
      fetchTrackFn: (_) async => _track(),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pumpUntil(
      tester,
      () => find.text(l10n.runHeatmapLegendSummary(1)).evaluate().isNotEmpty,
      describe: 'the one-run legend',
    );
    final ramps = [
      mapHeatRamp(darkBasemap: false),
      mapHeatRamp(darkBasemap: true),
    ];
    final legend = tester.widget<Container>(
        find.byKey(const Key('runHeatmapLegendScale')));
    final stops =
        ((legend.decoration! as BoxDecoration).gradient! as LinearGradient)
            .colors;
    expect(
        ramps.map((r) => [for (final c in r) c.withValues(alpha: mapHeatOpacity)]),
        anyElement(orderedEquals(stops)));
    final opaque = [for (final c in stops) c.withValues(alpha: 1)];
    final cells = tester
        .widgetList<CircleLayer>(find.byType(CircleLayer))
        .expand((l) => l.circles);
    expect(cells, isNotEmpty);
    for (final cell in cells) {
      expect(opaque, contains(cell.color.withValues(alpha: 1)));
      expect(cell.color.a, lessThanOrEqualTo(mapHeatOpacity + 1e-9));
    }
  });

  testWidgets('shows the empty state when no run carries a track',
      (tester) async {
    await _pump(
      tester,
      fetchRunsFn: () async => [_run('a'), _run('b')],
      fetchTrackFn: (_) async => const [],
    );
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.runHeatmapEmptyTitle), findsOneWidget);
  });

  testWidgets('a failed runs fetch shows a retryable error, not the empty state',
      (tester) async {
    // A thrown fetch means we never learned whether the runner has mapped
    // runs — the screen must surface a distinct error + retry, NOT the
    // "No mapped runs yet" empty state (which would tell an active runner
    // they've never run anywhere). Retry recovers.
    var fail = true;
    await _pump(
      tester,
      fetchRunsFn: () async {
        if (fail) {
          fail = false;
          throw Exception('simulated failure');
        }
        return [_run('a', trackUrl: 'u/a.json.gz')];
      },
      fetchTrackFn: (_) async => _track(),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.runHeatmapErrorTitle), findsOneWidget);
    expect(find.text(l10n.runHeatmapEmptyTitle), findsNothing);

    // Retry — the second fetch succeeds, so the error clears and the legend
    // renders (never stuck on the error).
    await tester.tap(find.text(l10n.runHeatmapRetry));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l10n.runHeatmapErrorTitle), findsNothing);
    expect(find.text(l10n.runHeatmapLegendSummary(1)), findsOneWidget);
  });

  group('MapFirstPage states (issue #1374)', () {
    void expectAboveNavBar(WidgetTester tester, Finder finder) {
      expect(finder, findsWidgets);
      for (final e in finder.evaluate()) {
        final rect = tester.getRect(find.byWidget(e.widget));
        expect(rect.bottom, lessThanOrEqualTo(780 - 48),
            reason: '$rect is under the navigation bar');
      }
    }

    testWidgets('loading shows the progress pill over the map',
        (tester) async {
      final pending = Completer<List<cm.Run>>();
      await _pump(
        tester,
        fetchRunsFn: () => pending.future,
        fetchTrackFn: (_) async => _track(),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.runHeatmapLoading), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(l10n.runHeatmapEmptyTitle), findsNothing);
      pending.complete(const []);
      await tester.pump();
    });

    testWidgets('the empty state clears a 48 dp nav bar', (tester) async {
      simulateNavBar(tester);
      await _pump(
        tester,
        fetchRunsFn: () async => [_run('a')],
        fetchTrackFn: (_) async => const [],
      );
      await tester.pump(const Duration(milliseconds: 50));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expectAboveNavBar(tester, find.text(l10n.runHeatmapEmptyTitle));
      expectAboveNavBar(tester, find.text(l10n.runHeatmapEmptyBody));
      expectCreditsAboveNavBar(tester);
    });

    testWidgets('the error state and its retry clear a 48 dp nav bar',
        (tester) async {
      simulateNavBar(tester);
      await _pump(
        tester,
        fetchRunsFn: () async => throw Exception('simulated failure'),
        fetchTrackFn: (_) async => _track(),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expectAboveNavBar(tester, find.text(l10n.runHeatmapErrorTitle));
      expectAboveNavBar(
          tester, find.widgetWithText(FilledButton, l10n.runHeatmapRetry));
      expectCreditsAboveNavBar(tester);
    });

    testWidgets('in landscape the pill and the credit clear a side nav bar',
        (tester) async {
      tester.view.physicalSize = const Size(780, 360);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(left: 48);
      tester.view.viewPadding = const FakeViewPadding(left: 48);
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        fetchRunsFn: () async => [_run('a', trackUrl: 'u/a.json.gz')],
        fetchTrackFn: (_) async => _track(),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final heading = find.descendant(
          of: find.byType(PageHeading),
          matching: find.text(l10n.runHeatmapLegendTitle));
      expect(tester.getRect(heading).left, greaterThanOrEqualTo(48));
      final credits = find.descendant(
          of: find.byType(MapAttribution), matching: find.byType(Text));
      for (final credit in credits.evaluate()) {
        expect(tester.getRect(find.byWidget(credit.widget)).left,
            greaterThanOrEqualTo(48));
      }
    });

    // The bar title is cut at 2x on 320 dp in most locales; the pill over
    // the map says it in full, so the harness's title check passes on the
    // in-body heading, in every state the page can open in.
    for (final (state, fetchRunsFn, fetchTrackFn) in [
      (
        'the legend',
        () async => [_run('a', trackUrl: 'u/a.json.gz')],
        (String _) async => _track(),
      ),
      ('the empty state', () async => [_run('a')], (String _) async => <cm.Waypoint>[]),
      (
        'the error state',
        () async => throw Exception('simulated failure'),
        (String _) async => _track(),
      ),
    ]) {
      worstCaseTestWidgets('Your heatmap, $state', (tester, locale) async {
        await tester.pumpWidget(worstCaseApp(
          locale: locale,
          home: RunHeatmapScreen(
            api: _FakeApiClient(),
            fetchRunsFn: fetchRunsFn,
            fetchTrackFn: fetchTrackFn,
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        final l10n = l10nFor(locale);
        final heading = find.descendant(
            of: find.byType(PageHeading),
            matching: find.text(l10n.runHeatmapLegendTitle));
        expect(heading, findsOneWidget);
        expect(
            tester.renderObject<RenderParagraph>(heading).didExceedMaxLines,
            isFalse);
        expect(tester.getRect(heading).right, lessThanOrEqualTo(320));
        expectCreditsAboveNavBarAt(tester, 640);
      }, layoutOnly: true);
    }
  });

  // Issue #239: signed-out recording is a supported flow, so the local
  // store is a first-class source. Reading only the server told a runner
  // with plenty of local GPS tracks that they had never run anywhere.
  group('local tracks (issue #239)', () {
    late Directory dir;
    late LocalRunStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('heatmap_runs_');
      store = LocalRunStore();
      await store.init(overrideDirectory: dir);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('a signed-out viewer\'s local runs still light up the map',
        (tester) async {
      await tester.runAsync(() => store.save(_localRun('local-1')));
      var serverFetches = 0;
      await _pump(
        tester,
        api: _FakeApiClient(viewerId: null),
        runStore: store,
        fetchRunsFn: () async {
          serverFetches++;
          return const <cm.Run>[];
        },
        fetchTrackFn: (_) async => _track(),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // The cells rendered from the local track alone...
      expect(find.text('No mapped runs yet'), findsNothing);
      expect(find.text('Sign in to see your synced heatmap'), findsNothing);
      // ...and signed out we never asked the server for owner-only rows.
      expect(serverFetches, 0);
    });

    testWidgets('signed out with nothing local says sign in, not "never ran"',
        (tester) async {
      await _pump(
        tester,
        api: _FakeApiClient(viewerId: null),
        runStore: store,
        fetchRunsFn: () async => const <cm.Run>[],
        fetchTrackFn: (_) async => _track(),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Sign in to see your synced heatmap'), findsOneWidget);
      // The old copy claimed a fact we can't know while signed out.
      expect(find.text('No mapped runs yet'), findsNothing);
    });

    testWidgets('a synced run is not downloaded twice — local copy wins',
        (tester) async {
      await tester.runAsync(() => store.save(_localRun('shared-1')));
      final downloaded = <String>[];
      await _pump(
        tester,
        runStore: store,
        fetchRunsFn: () async => [_run('shared-1', trackUrl: 'u/shared-1.gz')],
        fetchTrackFn: (p) async {
          downloaded.add(p);
          return _track();
        },
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(downloaded, isEmpty);
    });

    testWidgets('signed in, local and server tracks are unioned',
        (tester) async {
      await tester.runAsync(() => store.save(_localRun('local-1')));
      final downloaded = <String>[];
      await _pump(
        tester,
        runStore: store,
        fetchRunsFn: () async => [_run('server-1', trackUrl: 'u/server-1.gz')],
        fetchTrackFn: (p) async {
          downloaded.add(p);
          return _track();
        },
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(downloaded, ['u/server-1.gz']);
      expect(find.text('No mapped runs yet'), findsNothing);
    });
  });
}
