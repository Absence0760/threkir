import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/pr_card.dart';
import '../lib/preferences.dart';
import '../lib/privacy.dart';
import '../lib/share_look.dart';
import '../lib/widgets/run_share_card.dart';
import '../lib/widgets/run_share_overlays.dart';

Run _run({List<Waypoint> track = const []}) => Run(
      id: 'r1',
      startedAt: DateTime.utc(2026, 4, 15, 8, 0),
      duration: const Duration(minutes: 24),
      distanceMetres: 5000,
      source: RunSource.app,
      track: track,
      metadata: const {'title': 'Morning run', 'activity_type': 'run'},
    );

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

const _improved = PrCardEntry(distance: '5k', timeS: 1440, previousS: 1482, kind: PrCardKind.improved);
const _first = PrCardEntry(distance: '10k', timeS: 2900, previousS: null, kind: PrCardKind.first);
const _held = PrCardEntry(distance: 'marathon', timeS: 12000, previousS: null, kind: PrCardKind.held);

const _home = PrivacyZone(lat: 51.44, lng: -0.27, radiusM: 200);
final _track = [
  const Waypoint(lat: 51.44, lng: -0.27),
  const Waypoint(lat: 51.4405, lng: -0.27),
  for (var i = 1; i <= 3; i++) Waypoint(lat: 51.44, lng: -0.27 + i * 0.01),
];

void main() {
  group('RunPrShareCard', () {
    Future<void> pumpCard(WidgetTester tester, PrCardEntry record,
        {RunShareLook look = const RunShareLook(), List<Waypoint> track = const []}) async {
      // Fitted as the share sheet fits it, so the canvas keeps its own size
      // inside a test window shorter than a story.
      await tester.pumpWidget(_app(FittedBox(
        child: MediaQuery.withNoTextScaling(
          child: RunPrShareCard(run: _run(track: track), record: record, privacyZones: const [_home], look: look),
        ),
      )));
      await tester.pump();
    }

    testWidgets('prints the record, the time it beat and how much faster', (tester) async {
      await pumpCard(tester, _improved);
      expect(find.text('NEW PERSONAL RECORD'), findsOneWidget);
      expect(find.text('5K'), findsOneWidget);
      expect(find.text('24:00'), findsOneWidget);
      expect(find.text('00:42 faster'), findsOneWidget);
      expect(find.text('Previous best 24:42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a first record says so and prints no improvement', (tester) async {
      await pumpCard(tester, _first);
      expect(find.text('First 10K on record'), findsOneWidget);
      expect(find.textContaining('faster'), findsNothing);
    });

    testWidgets('a record from before the log is a plain personal record', (tester) async {
      await pumpCard(tester, _held);
      expect(find.text('PERSONAL RECORD'), findsOneWidget);
      expect(find.textContaining('Previous best'), findsNothing);
      expect(find.textContaining('on record'), findsNothing);
    });

    for (final aspect in RunPhotoAspect.values) {
      for (final ink in RunShareInk.values) {
        testWidgets('${aspect.name} in ${ink.name} is the photo canvas and lays out without overflow',
            (tester) async {
          await pumpCard(tester, _improved,
              look: RunShareLook(aspect: aspect, ink: ink), track: _track);
          expect(tester.getSize(find.byType(RunPrShareCard)), RunPhotoShareCard.canvasFor(aspect));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the route outline withholds the privacy zone', (tester) async {
      await pumpCard(tester, _improved, track: _track);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<RunRouteOutlinePainter>()
          .single;
      expect(painter.points.any((p) => p.lat == 51.4405), isFalse);
    });

    testWidgets('each ink sits on the ground its contrast was measured on', (tester) async {
      expect(prCardGround(RunShareInk.dark), Colors.white);
      expect(prCardGround(RunShareInk.light), isNot(Colors.white));
      expect(prCardGround(RunShareInk.brand), prCardGround(RunShareInk.light));
    });
  });

  group('share sheet', () {
    Future<void> openSheet(
      WidgetTester tester, {
      List<PrCardEntry> records = const [],
      RunShareStyle initialStyle = RunShareStyle.card,
    }) async {
      tester.view.physicalSize = const Size(1200, 3300);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final preferences = Preferences();
      await preferences.init();
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showRunShareSheet(
                context,
                run: _run(),
                preferences: preferences,
                title: 'Morning run',
                privacyZones: const [],
                records: records,
                initialStyle: initialStyle,
                pickPhotoOverride: () async => null,
                saveImageOverride: (_, __) async {},
                openUrlOverride: (_) async => true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a run that set no record is offered no PR card', (tester) async {
      await openSheet(tester);
      expect(find.text('PR card'), findsNothing);
    });

    testWidgets('asking for the PR card with no record opens the map card', (tester) async {
      await openSheet(tester, initialStyle: RunShareStyle.pr);
      expect(find.byType(RunShareCard), findsOneWidget);
      expect(find.byType(RunPrShareCard), findsNothing);
    });

    testWidgets('opens on the PR card with its hint, colour and size, and no layout or stats',
        (tester) async {
      await openSheet(tester, records: const [_improved], initialStyle: RunShareStyle.pr);
      expect(find.byType(RunPrShareCard), findsOneWidget);
      expect(find.textContaining('record times stay private'), findsOneWidget);
      for (final label in ['Colour', 'Size']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['Layout', 'Stats', 'Record']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a run with several records picks between them', (tester) async {
      await openSheet(tester, records: const [_first, _improved], initialStyle: RunShareStyle.pr);
      expect(find.text('Record'), findsOneWidget);
      expect(find.text('First 10K on record'), findsOneWidget);
      await tester.ensureVisible(find.text('5K').last);
      await tester.tap(find.text('5K').last);
      await tester.pumpAndSettle();
      expect(find.text('00:42 faster'), findsOneWidget);
    });

    testWidgets('the PR chip is offered beside the other styles', (tester) async {
      await openSheet(tester, records: const [_improved]);
      expect(find.byType(RunShareCard), findsOneWidget);
      await tester.ensureVisible(find.text('PR card'));
      await tester.tap(find.text('PR card'));
      await tester.pumpAndSettle();
      expect(find.byType(RunPrShareCard), findsOneWidget);
    });
  });
}
