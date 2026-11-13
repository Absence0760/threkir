import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show PageHeading;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/recap_card_layout.dart';
import '../lib/screens/recap_screen.dart';
import '../lib/widgets/recap_share_card.dart';
import 'pump_until.dart';
import 'worst_case_layout.dart';

/// A year that is always safely in the past, so "next period" is enabled and
/// the recap window never lands on a future month.
final int pastYear = DateTime.now().year - 1;

typedef _ParkRow = ({String parkId, String parkName, String regionCode, String courseId});

class _ParkApi extends ApiClient {
  final List<_ParkRow> rows;
  final bool fail;
  _ParkApi(this.rows, {this.fail = false});

  @override
  String? get userId => 'me';

  @override
  Future<List<_ParkRow>> fetchRecapParkCourses(DateTime start, DateTime end) async {
    if (fail) throw Exception('offline');
    return rows;
  }
}

Directory? _dir;

Run _run(String id, DateTime startedAt, {double distanceMetres = 5000}) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: distanceMetres,
      source: RunSource.app,
    );

Future<({LocalRunStore runStore, Preferences prefs})> _seed(
    List<Run> runs) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _dir = Directory.systemTemp.createTempSync('recap_screen_test_');
  final seed = LocalRunStore();
  await seed.init(overrideDirectory: _dir!);
  for (final r in runs) {
    await seed.save(r);
  }
  // Fresh store over the same directory so _loadAll has the runs in memory
  // before the screen's first frame.
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _dir!);
  return (runStore: runStore, prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester, {
  required LocalRunStore runStore,
  required Preferences prefs,
  int? year,
  int? month,
  ApiClient? api,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RecapScreen(
        runStore: runStore,
        preferences: prefs,
        year: year,
        month: month,
        api: api,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  tearDown(() {
    if (_dir != null && _dir!.existsSync()) _dir!.deleteSync(recursive: true);
    _dir = null;
  });

  testWidgets('a month arg opens the monthly recap scoped to that month',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([
        _run('march', DateTime(pastYear, 3, 12, 8)),
        _run('july', DateTime(pastYear, 7, 4, 8)),
      ]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 3);

    expect(find.widgetWithText(PageHeading, 'Month in running'), findsOneWidget);
    expect(find.text('March $pastYear'), findsOneWidget);
    // Only the March run counts — the July one belongs to another month.
    expect(find.text('across 1 run'), findsOneWidget);
  });

  testWidgets('the period toggle switches month to the whole year',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([
        _run('march', DateTime(pastYear, 3, 12, 8)),
        _run('july', DateTime(pastYear, 7, 4, 8)),
      ]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 3);
    expect(find.text('across 1 run'), findsOneWidget);

    await tester.tap(find.text('Year'));
    await tester.pump();

    expect(find.widgetWithText(PageHeading, 'Year in running'), findsOneWidget);
    expect(find.text('$pastYear'), findsOneWidget);
    expect(find.text('across 2 runs'), findsOneWidget);
  });

  testWidgets('a month with no activity renders the empty state',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([_run('march', DateTime(pastYear, 3, 12, 8))]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 4);

    expect(
      find.text('No runs in April $pastYear yet. Log one to see your recap.'),
      findsOneWidget,
    );
    expect(find.text('across 1 run'), findsNothing);
  });

  testWidgets('the previous-month chevron steps across the year boundary',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed(const <Run>[]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 1);
    expect(find.text('January $pastYear'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();

    expect(find.text('December ${pastYear - 1}'), findsOneWidget);
  });

  testWidgets('the next chevron is disabled on the current month',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed(const <Run>[]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    final now = DateTime.now();
    await _pump(tester,
        runStore: runStore, prefs: prefs, year: now.year, month: now.month);

    final next = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.chevron_right),
      matching: find.byType(IconButton),
    ));
    expect(next.onPressed, isNull);
  });
  testWidgets('share opens the image sheet, square first, with a story option',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([
        _run('march', DateTime(pastYear, 3, 12, 8)),
        _run('july', DateTime(pastYear, 7, 4, 8)),
      ]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester, runStore: runStore, prefs: prefs, year: pastYear);
    await tester.tap(find.byTooltip('Share recap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Share your recap'), findsOneWidget);
    expect(find.text('Share image'), findsOneWidget);
    expect(find.text('Share as text'), findsOneWidget);
    final card = find.byType(RecapShareCard);
    expect(tester.widget<RecapShareCard>(card).aspect, RecapCardAspect.square);
    expect(tester.widget<RecapShareCard>(card).text.kicker,
        'MY $pastYear IN RUNNING');
    expect(tester.widget<RecapShareCard>(card).text.subhead, 'across 2 runs');
    expect(tester.getSize(card), const Size(1080, 1080));

    await tester.tap(find.text('Story'));
    await tester.pump();
    expect(tester.widget<RecapShareCard>(card).aspect, RecapCardAspect.story);
    expect(tester.getSize(card), const Size(1080, 1920));
  });

  test('the video export URL names the recap period on the web', () {
    expect(recapVideoExportUrl(2026, webBase: 'https://preview.example/'),
        Uri.parse('https://preview.example/recap/2026?video=1'));
    expect(recapVideoExportUrl(2026, month: 3, webBase: 'https://preview.example'),
        Uri.parse('https://preview.example/recap/2026/3?video=1'));
  });

  testWidgets(
      'the Video option explains the browser export and opens the recap page',
      (tester) async {
    final opened = <Uri>[];
    var succeed = true;
    final videoUrl = recapVideoExportUrl(pastYear,
        month: 3, webBase: 'https://preview.example');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRecapShareSheet(
                context,
                text: const RecapCardText(
                  kicker: 'MY MARCH IN RUNNING',
                  hero: '42 km',
                  subhead: 'across 6 runs',
                  cells: [],
                  footer: 'threkir.com',
                ),
                fileStem: 'threkir-recap',
                subject: 'My March in running',
                shareText: () async {},
                videoUrl: videoUrl,
                openUrl: (url) async {
                  opened.add(url);
                  return succeed;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Open video export'), findsNothing);
    await tester.tap(find.text('Video'));
    await tester.pump();
    expect(find.byType(RecapShareCard), findsNothing);
    expect(find.text('Share image'), findsNothing);
    expect(find.textContaining('made in your browser on threkir.com'),
        findsOneWidget);
    expect(find.text('Share as text'), findsOneWidget);

    await tester.tap(find.text('Open video export'));
    await tester.pump();
    expect(opened, [videoUrl]);
    expect(find.text("Couldn't open the browser. Try again."), findsNothing);

    succeed = false;
    await tester.tap(find.text('Open video export'));
    await tester.pump();
    expect(opened, [videoUrl, videoUrl]);
    expect(find.text("Couldn't open the browser. Try again."), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('park courses run in the period show a card and the parks list',
      (tester) async {
    // Tall enough that the park card, which sits under the stat cards, is
    // built by the lazy list without a scroll.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final seeded = await _seed([_run('a', DateTime(pastYear, 5, 2, 8))]);
      runStore = seeded.runStore;
      prefs = seeded.prefs;
    });
    final api = _ParkApi(const [
      (parkId: 'p1', parkName: 'Pocahontas State Park', regionCode: 'US-VA', courseId: 'c1'),
      (parkId: 'p1', parkName: 'Pocahontas State Park', regionCode: 'US-VA', courseId: 'c2'),
      (parkId: 'p2', parkName: 'Great Falls Park', regionCode: 'US-VA', courseId: 'c3'),
    ]);
    await _pump(tester, runStore: runStore, prefs: prefs, year: pastYear, api: api);
    await pumpUntil(tester,
        () => find.byKey(const Key('recap-park-courses')).evaluate().isNotEmpty,
        describe: 'the park course card');

    expect(find.text('in 2 parks'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Great Falls Park'), 200);
    expect(find.text('Parks you ran'), findsOneWidget);
    expect(find.text('Pocahontas State Park'), findsOneWidget);
    expect(find.text('2 courses'), findsOneWidget);
    expect(find.text('1 course'), findsOneWidget);
  });

  testWidgets('a failed park read leaves the recap without the park card',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final seeded = await _seed([_run('a', DateTime(pastYear, 5, 2, 8))]);
      runStore = seeded.runStore;
      prefs = seeded.prefs;
    });
    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, api: _ParkApi(const [], fail: true));
    await tester.pump();

    expect(find.byKey(const Key('recap-park-courses')), findsNothing);
    expect(find.text('Parks you ran'), findsNothing);
  });

  // The recap's cards are ListCards (issue #1374).
  worstCaseTestWidgets('Recap', (tester, locale) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([
        _run('march', DateTime(pastYear, 3, 12, 8)),
        _run('march-2', DateTime(pastYear, 3, 20, 8), distanceMetres: 21097),
      ]);
      runStore = s.runStore;
      prefs = s.prefs;
    });
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: RecapScreen(
          runStore: runStore, preferences: prefs, year: pastYear, month: 3),
    ));
    await tester.pump();
    await walkScrollable(tester, primaryScrollable(), 'Recap');
  });
}
