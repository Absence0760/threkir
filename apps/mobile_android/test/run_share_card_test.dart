import 'dart:io';
import 'dart:typed_data';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/preferences.dart';
import '../lib/privacy.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/share_sheet.dart' show XFile;
import '../lib/widgets/run_share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pump_until.dart';

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

    test('an off-track fix is never drawn, in a zone or out of one', () {
      // Distance input the recorder stored for the server replay; the public
      // run page never serves one, so the posted image must not either. One
      // just outside the zone must not end the clip early.
      final a2 = away(2);
      final a4 = away(4);
      final track = [
        nearHome,
        away(1).withOffTrack(true),
        nearHome,
        a2,
        away(3).withOffTrack(true),
        a4,
      ];
      expect(runShareCardTrack(_run(track: track), const [home]), [a2, a4]);
      expect(runShareCardTrack(_run(track: track), const []),
          [nearHome, nearHome, a2, a4]);
    });
  });

  group('photo and sticker styles', () {
    const home = PrivacyZone(lat: 51.44, lng: -0.27, radiusM: 200);
    const nearHome = Waypoint(lat: 51.4405, lng: -0.27);
    Waypoint away(int i) => Waypoint(lat: 51.44, lng: -0.27 + i * 0.01);

    // A 1x1 PNG: the photo only has to be an ImageProvider here, the layout
    // over it is what is under test.
    final photo = MemoryImage(Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x60, 0x60,
      0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0xA5, 0xF6, 0x45, 0x40, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]));

    Future<void> pumpOverlay(WidgetTester tester, Widget card) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 400, height: 500, child: card),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    List<Waypoint> outline(WidgetTester tester) {
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<RunRouteOutlinePainter>()
          .toList();
      expect(paints, hasLength(1), reason: 'expected exactly one outline');
      return paints.single.points;
    }

    bool hasOutline(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((p) => p.painter is RunRouteOutlinePainter);

    final track = [
      const Waypoint(lat: 51.44, lng: -0.27),
      nearHome,
      away(1),
      away(2),
      away(3),
    ];

    testWidgets('the photo card prints the title and stats over the photo',
        (tester) async {
      final run = _run(track: track);
      await pumpOverlay(
        tester,
        RunPhotoShareCard(
          run: run,
          preferences: await _makePrefs(),
          title: 'Morning run',
          privacyZones: const [],
          photo: photo,
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Morning run'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('PACE'), findsOneWidget);
      expect(find.text('RUN'), findsOneWidget);
      expect(outline(tester), hasLength(track.length));
    });

    testWidgets('the photo card outline withholds the privacy zone',
        (tester) async {
      await pumpOverlay(
        tester,
        RunPhotoShareCard(
          run: _run(track: track),
          preferences: await _makePrefs(),
          title: 'Morning run',
          privacyZones: const [home],
          photo: photo,
        ),
      );
      final pts = outline(tester);
      expect(pts, hasLength(3));
      for (final p in pts) {
        expect(isInAnyZone(p.lat, p.lng, const [home]), isFalse,
            reason: 'a drawn vertex sits inside the privacy zone');
      }
    });

    testWidgets('the sticker paints no ground of its own', (tester) async {
      await pumpOverlay(
        tester,
        RunStickerShareCard(
          run: _run(track: track),
          preferences: await _makePrefs(),
          privacyZones: const [],
        ),
      );
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('PACE'), findsOneWidget);
      // The PNG keeps its alpha only if nothing inside the card fills it.
      final sticker = find.byType(RunStickerShareCard);
      for (final c in tester.widgetList<Container>(
          find.descendant(of: sticker, matching: find.byType(Container)))) {
        expect(c.color, isNull);
        expect(c.decoration, isNull);
      }
      expect(
          find.descendant(of: sticker, matching: find.byType(ColoredBox)),
          findsNothing);
      expect(
          find.descendant(of: sticker, matching: find.byType(DecoratedBox)),
          findsNothing);
      expect(find.descendant(of: sticker, matching: find.byType(Image)),
          findsNothing);
    });

    testWidgets('the sticker outline withholds the privacy zone',
        (tester) async {
      await pumpOverlay(
        tester,
        RunStickerShareCard(
          run: _run(track: track),
          preferences: await _makePrefs(),
          privacyZones: const [home],
        ),
      );
      final pts = outline(tester);
      expect(pts.first.lng, closeTo(away(1).lng, 1e-9));
      for (final p in pts) {
        expect(isInAnyZone(p.lat, p.lng, const [home]), isFalse);
      }
    });

    testWidgets('a track wholly inside a zone draws no outline on either',
        (tester) async {
      final run = _run(track: const [
        Waypoint(lat: 51.44, lng: -0.27),
        nearHome,
      ]);
      final prefs = await _makePrefs();
      await pumpOverlay(
        tester,
        RunStickerShareCard(
            run: run, preferences: prefs, privacyZones: const [home]),
      );
      expect(hasOutline(tester), isFalse);
      await pumpOverlay(
        tester,
        RunPhotoShareCard(
          run: run,
          preferences: prefs,
          title: 'Morning run',
          privacyZones: const [home],
          photo: photo,
        ),
      );
      expect(hasOutline(tester), isFalse);
    });

    testWidgets('a speed activity prints speed rather than pace',
        (tester) async {
      final run = Run(
        id: 'r2',
        startedAt: DateTime.utc(2026, 4, 15, 8, 0),
        duration: const Duration(hours: 1),
        distanceMetres: 30000,
        source: RunSource.app,
        metadata: const {'activity_type': 'cycle'},
      );
      await pumpOverlay(
        tester,
        RunStickerShareCard(
          run: run,
          preferences: await _makePrefs(),
          privacyZones: const [],
        ),
      );
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('PACE'), findsNothing);
    });
  });

  group('share sheet styles', () {
    Future<void> openSheet(
      WidgetTester tester, {
      required Future<XFile?> Function() pick,
    }) async {
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final prefs = await _makePrefs();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRunShareSheet(
                  context,
                  run: _run(),
                  preferences: prefs,
                  title: 'Morning run',
                  privacyZones: const [],
                  pickPhotoOverride: pick,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    ButtonStyleButton shareImageButton(WidgetTester tester) =>
        tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Image'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ));

    testWidgets('opens on the map card with the image share enabled',
        (tester) async {
      await openSheet(tester, pick: () async => null);
      expect(find.byType(RunShareCard), findsOneWidget);
      expect(find.text('Map card'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Sticker'), findsOneWidget);
      expect(shareImageButton(tester).enabled, isTrue);
    });

    testWidgets(
        'choosing Photo opens the picker; cancelling it leaves the image '
        'share disabled until a photo is chosen', (tester) async {
      var picks = 0;
      await openSheet(tester, pick: () async {
        picks++;
        return null;
      });
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(find.byType(RunPhotoShareCard), findsNothing);
      expect(find.text('Choose a photo'), findsOneWidget);
      expect(shareImageButton(tester).enabled, isFalse);

      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(picks, 2);
    });

    testWidgets(
        'a photo that cannot be decoded shows the error and stays unshareable',
        (tester) async {
      // precacheImage completes normally on a decode failure; the sheet has to
      // catch it itself or it shows a blank photo the runner can share.
      late File bad;
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('share_photo');
        bad = File('${dir.path}/bad.jpg');
        await bad.writeAsBytes(const [1, 2, 3, 4, 5]);
      });
      addTearDown(() => bad.parent.deleteSync(recursive: true));

      await openSheet(tester, pick: () async => XFile(bad.path));
      await tester.tap(find.text('Photo'));
      await pumpUntil(
        tester,
        () => find.text('Could not open that photo').evaluate().isNotEmpty,
        describe: 'the photo-error banner',
      );
      expect(find.byType(RunPhotoShareCard), findsNothing);
      expect(shareImageButton(tester).enabled, isFalse);
      // Let the banner's dismiss timer run out so none is left pending.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('choosing Sticker shows the transparent card and its hint',
        (tester) async {
      await openSheet(tester, pick: () async => null);
      await tester.tap(find.text('Sticker'));
      await tester.pumpAndSettle();
      expect(find.byType(RunStickerShareCard), findsOneWidget);
      expect(find.byType(RunShareCard), findsNothing);
      expect(find.textContaining('Transparent background'), findsOneWidget);
      expect(shareImageButton(tester).enabled, isTrue);
    });
  });
}
