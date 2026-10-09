import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/preferences.dart';
import '../lib/privacy.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Run _run({
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 25),
  List<Waypoint> track = const [],
  String title = 'Morning run',
}) =>
    Run(
      id: 'r1',
      startedAt: DateTime.utc(2026, 4, 15, 8, 0),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      track: track,
      metadata: {'title': title, 'activity_type': 'run'},
    );

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(
  WidgetTester tester,
  Run run,
  Preferences prefs, {
  List<PrivacyZone> zones = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 500, // 4:5 ratio
          child: RunShareCard(
            run: run,
            preferences: prefs,
            title: run.metadata?['title'] as String? ?? 'Run',
            privacyZones: zones,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RunShareCard', () {
    testWidgets('renders the run title and date', (tester) async {
      final prefs = await _makePrefs();
      final run = _run();
      await _pump(tester, run, prefs);
      expect(find.text('Morning run'), findsOneWidget);
      expect(find.textContaining('Apr 15, 2026'), findsOneWidget);
    });

    testWidgets('renders Distance, Time, and Pace stat labels', (tester) async {
      final prefs = await _makePrefs();
      final run = _run();
      await _pump(tester, run, prefs);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('PACE'), findsOneWidget);
    });

    testWidgets('renders the run-app brand label', (tester) async {
      final prefs = await _makePrefs();
      final run = _run();
      await _pump(tester, run, prefs);
      expect(find.text('RUN'), findsOneWidget);
    });

    testWidgets('renders directions_run icon instead of a map when track has fewer than 2 points',
        (tester) async {
      final prefs = await _makePrefs();
      final run = _run(track: const []);
      await _pump(tester, run, prefs);
      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('renders formatted distance in km for km preference',
        (tester) async {
      final prefs = await _makePrefs();
      final run = _run(distanceMetres: 5000);
      await _pump(tester, run, prefs);
      // km format: "5.00"
      expect(
        find.textContaining(
          UnitFormat.distanceValue(5000, DistanceUnit.km),
        ),
        findsOneWidget,
      );
    });
  });

  // The PNG is posted where anyone can read it, so the line it draws must be
  // trimmed by the owner's zones exactly as `clip_track_for_user` trims the
  // same run for a non-owner (migration 20270719000005): leading / trailing
  // fixes whose raw OR smoothed position is in a zone are not drawn.
  group('privacy zones', () {
    const home = PrivacyZone(lat: 51.44, lng: -0.27, radiusM: 200);

    // ~55 m north of home: inside the 200 m zone.
    const nearHome = Waypoint(lat: 51.4405, lng: -0.27);
    // 0.01 deg of longitude at 51.44 N is ~694 m: every one of these is out.
    Waypoint away(int i) => Waypoint(lat: 51.44, lng: -0.27 + i * 0.01);

    List<PolylineLayer> lines(WidgetTester tester) =>
        tester.widgetList<PolylineLayer>(find.byType(PolylineLayer)).toList();

    testWidgets('a start inside a privacy zone is not drawn', (tester) async {
      final track = [
        const Waypoint(lat: 51.44, lng: -0.27),
        nearHome,
        away(1),
        away(2),
        away(3),
      ];
      await _pump(tester, _run(track: track), await _makePrefs(),
          zones: const [home]);

      final layers = lines(tester);
      expect(layers, isNotEmpty, reason: 'the card draws no line at all');
      for (final layer in layers) {
        final pts = layer.polylines.single.points;
        expect(pts.length, 3);
        expect(pts.first.longitude, closeTo(away(1).lng, 1e-9));
        for (final p in pts) {
          expect(isInAnyZone(p.latitude, p.longitude, const [home]), isFalse,
              reason: 'a drawn vertex sits inside the privacy zone');
        }
      }
      final markers =
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
      for (final m in markers) {
        expect(isInAnyZone(m.point.latitude, m.point.longitude, const [home]),
            isFalse,
            reason: 'an endpoint dot sits inside the privacy zone');
      }
    });

    testWidgets(
        'a start whose smoothed position is in the zone is not drawn, '
        'though its raw fix is outside it', (tester) async {
      final track = [
        Waypoint(
          lat: away(1).lat,
          lng: away(1).lng,
          smoothedLat: home.lat,
          smoothedLng: home.lng,
        ),
        away(2),
        away(3),
      ];
      await _pump(tester, _run(track: track), await _makePrefs(),
          zones: const [home]);

      for (final layer in lines(tester)) {
        final pts = layer.polylines.single.points;
        expect(pts.length, 2);
        expect(pts.first.longitude, closeTo(away(2).lng, 1e-9));
      }
    });

    testWidgets('a track wholly inside a zone draws the glyph, not a map',
        (tester) async {
      final run = _run(track: const [
        Waypoint(lat: 51.44, lng: -0.27),
        nearHome,
      ]);
      expect(runShareCardHasMap(run, const [home]), isFalse);
      expect(runShareCardHasMap(run, const []), isTrue);
      await _pump(tester, run, await _makePrefs(), zones: const [home]);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('with no zones the whole track is drawn', (tester) async {
      final track = [
        const Waypoint(lat: 51.44, lng: -0.27),
        away(1),
        away(2),
      ];
      await _pump(tester, _run(track: track), await _makePrefs());
      for (final layer in lines(tester)) {
        expect(layer.polylines.single.points.length, 3);
      }
    });

    test('an interior pass through the zone is kept, as the server keeps it',
        () {
      final track = [away(1), nearHome, away(2)];
      expect(runShareCardTrack(_run(track: track), const [home]), track);
    });
  });
}
