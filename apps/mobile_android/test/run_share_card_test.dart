import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/preferences.dart';
import '../lib/privacy.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/run_share_stats.dart';
import '../lib/share_look.dart';
import '../lib/share_sheet.dart' show XFile;
import '../lib/widgets/run_share_card.dart';
import '../lib/widgets/run_share_overlays.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pump_until.dart';

Run _run({
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 25),
  List<Waypoint> track = const [],
  String title = 'Morning run',
  Map<String, dynamic> extra = const {},
}) =>
    Run(
      id: 'r1',
      startedAt: DateTime.utc(2026, 4, 15, 8, 0),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      track: track,
      metadata: {'title': title, 'activity_type': 'run', ...extra},
    );

Future<Preferences> _makePrefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

Future<void> _pump(
  WidgetTester tester,
  Run run,
  Preferences prefs, {
  List<PrivacyZone> zones = const [],
}) async {
  await tester.pumpWidget(
    _app(
      SizedBox(
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
  );
  await tester.pump();
  await tester.pump(Duration.zero);
}

const _home = PrivacyZone(lat: 51.44, lng: -0.27, radiusM: 200);
// ~55 m north of home: inside the 200 m zone.
const _nearHome = Waypoint(lat: 51.4405, lng: -0.27);
// 0.01 deg of longitude at 51.44 N is ~694 m: every one of these is out.
Waypoint _away(int i) => Waypoint(lat: 51.44, lng: -0.27 + i * 0.01);

final _zoneTrack = [
  const Waypoint(lat: 51.44, lng: -0.27),
  _nearHome,
  _away(1),
  _away(2),
  _away(3),
];

/// A track with ~150 m of climb, so the climb stat is offered.
final _hillTrack = [
  for (var i = 0; i < 6; i++)
    Waypoint(
      lat: 51.44 + i * 0.002,
      lng: -0.27,
      elevationMetres: 20.0 + i * 30,
      timestamp: DateTime.utc(2026, 4, 15, 8, i),
    ),
];

// A 1x1 PNG: the photo only has to be an ImageProvider here, the layout over
// it is what is under test.
final _photo = MemoryImage(Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x60, 0x60,
  0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0xA5, 0xF6, 0x45, 0x40, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]));

List<Waypoint> _outline(WidgetTester tester) {
  final paints = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<RunRouteOutlinePainter>()
      .toList();
  expect(paints, hasLength(1), reason: 'expected exactly one route outline');
  return paints.single.points;
}

bool _hasOutline(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((p) => p.painter is RunRouteOutlinePainter);

/// Lays [card] out unconstrained, at its own canvas size, the way the sheet
/// does inside its FittedBox.
Future<void> _pumpCanvas(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(2400, 3000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(Center(child: UnconstrainedBox(child: card))),
  );
  await tester.pump();
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RunShareCard', () {
    testWidgets('renders the run title and date', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, _run(), prefs);
      expect(find.text('Morning run'), findsOneWidget);
      expect(find.textContaining('Apr 15, 2026'), findsOneWidget);
    });

    testWidgets('renders Distance, Time, and Pace stat labels', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, _run(), prefs);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('PACE'), findsOneWidget);
    });

    testWidgets('is signed with the Threkir mark and wordmark', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, _run(), prefs);
      expect(find.text('THREKIR'), findsOneWidget);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .any((p) => p.painter is ThrekirMarkPainter),
        isTrue,
      );
    });

    testWidgets(
        'renders directions_run icon instead of a map when track has fewer '
        'than 2 points', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, _run(track: const []), prefs);
      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('renders formatted distance in km for km preference',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, _run(distanceMetres: 5000), prefs);
      expect(
        find.textContaining(UnitFormat.distanceValue(5000, DistanceUnit.km)),
        findsOneWidget,
      );
    });

    // The CI failure this pins: at the width the sheet gave it on a 360 dp
    // phone the stats row ran 47 px past the card. It is now laid out at a
    // fixed canvas and each stat scales down inside its third.
    testWidgets('a long run fits the stats row at the canvas width',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpCanvas(
        tester,
        SizedBox.fromSize(
          size: RunShareCard.canvas,
          child: RunShareCard(
            run: _run(
              distanceMetres: 162000,
              duration: const Duration(hours: 31, minutes: 12, seconds: 9),
            ),
            preferences: prefs,
            title: 'A very long ultra across three valleys and a pass',
            privacyZones: const [],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // The PNG is posted where anyone can read it, so the line it draws must be
  // trimmed by the owner's zones exactly as `clip_track_for_user` trims the
  // same run for a non-owner (migration 20270719000005): leading / trailing
  // fixes whose raw OR smoothed position is in a zone are not drawn.
  group('privacy zones', () {
    List<PolylineLayer> lines(WidgetTester tester) =>
        tester.widgetList<PolylineLayer>(find.byType(PolylineLayer)).toList();

    testWidgets('a start inside a privacy zone is not drawn', (tester) async {
      await _pump(tester, _run(track: _zoneTrack), await _makePrefs(),
          zones: const [_home]);

      final layers = lines(tester);
      expect(layers, isNotEmpty, reason: 'the card draws no line at all');
      for (final layer in layers) {
        final pts = layer.polylines.single.points;
        expect(pts.length, 3);
        expect(pts.first.longitude, closeTo(_away(1).lng, 1e-9));
        for (final p in pts) {
          expect(isInAnyZone(p.latitude, p.longitude, const [_home]), isFalse,
              reason: 'a drawn vertex sits inside the privacy zone');
        }
      }
      final markers =
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
      for (final m in markers) {
        expect(isInAnyZone(m.point.latitude, m.point.longitude, const [_home]),
            isFalse,
            reason: 'an endpoint dot sits inside the privacy zone');
      }
    });

    testWidgets(
        'a start whose smoothed position is in the zone is not drawn, '
        'though its raw fix is outside it', (tester) async {
      final track = [
        Waypoint(
          lat: _away(1).lat,
          lng: _away(1).lng,
          smoothedLat: _home.lat,
          smoothedLng: _home.lng,
        ),
        _away(2),
        _away(3),
      ];
      await _pump(tester, _run(track: track), await _makePrefs(),
          zones: const [_home]);

      for (final layer in lines(tester)) {
        final pts = layer.polylines.single.points;
        expect(pts.length, 2);
        expect(pts.first.longitude, closeTo(_away(2).lng, 1e-9));
      }
    });

    testWidgets('a track wholly inside a zone draws the glyph, not a map',
        (tester) async {
      final run = _run(track: const [
        Waypoint(lat: 51.44, lng: -0.27),
        _nearHome,
      ]);
      expect(runShareCardHasMap(run, const [_home]), isFalse);
      expect(runShareCardHasMap(run, const []), isTrue);
      await _pump(tester, run, await _makePrefs(), zones: const [_home]);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('with no zones the whole track is drawn', (tester) async {
      final track = [
        const Waypoint(lat: 51.44, lng: -0.27),
        _away(1),
        _away(2),
      ];
      await _pump(tester, _run(track: track), await _makePrefs());
      for (final layer in lines(tester)) {
        expect(layer.polylines.single.points.length, 3);
      }
    });

    test('an interior pass through the zone is kept, as the server keeps it',
        () {
      final track = [_away(1), _nearHome, _away(2)];
      expect(runShareCardTrack(_run(track: track), const [_home]), track);
    });

    test('an off-track fix is never drawn, in a zone or out of one', () {
      // Distance input the recorder stored for the server replay; the public
      // run page never serves one, so the posted image must not either. One
      // just outside the zone must not end the clip early.
      final a2 = _away(2);
      final a4 = _away(4);
      final track = [
        _nearHome,
        _away(1).withOffTrack(true),
        _nearHome,
        a2,
        _away(3).withOffTrack(true),
        a4,
      ];
      expect(runShareCardTrack(_run(track: track), const [_home]), [a2, a4]);
      expect(runShareCardTrack(_run(track: track), const []),
          [_nearHome, _nearHome, a2, a4]);
    });
  });

  group('sticker', () {
    for (final layout in RunStickerLayout.values) {
      for (final ink in RunShareInk.values) {
        testWidgets('${layout.name} in ${ink.name} lays out without overflow',
            (tester) async {
          await _pumpCanvas(
            tester,
            RunStickerShareCard(
              run: _run(
                track: _hillTrack,
                distanceMetres: 42195,
                duration: const Duration(hours: 3, minutes: 58, seconds: 41),
                extra: const {'avg_bpm': 162},
              ),
              preferences: await _makePrefs(),
              privacyZones: const [],
              look: RunShareLook(
                layout: layout,
                ink: ink,
                stats: const [
                  RunShareStatKind.distance,
                  RunShareStatKind.pace,
                  RunShareStatKind.time,
                  RunShareStatKind.heartRate,
                ],
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('THREKIR'), findsOneWidget);
          expect(find.text('DISTANCE'), findsOneWidget);
        });
      }
    }

    testWidgets('prints the stats the look picks, climb and heart rate too',
        (tester) async {
      await _pumpCanvas(
        tester,
        RunStickerShareCard(
          run: _run(track: _hillTrack, extra: const {'avg_bpm': 151}),
          preferences: await _makePrefs(),
          privacyZones: const [],
          look: const RunShareLook(stats: [
            RunShareStatKind.distance,
            RunShareStatKind.climb,
            RunShareStatKind.heartRate,
          ]),
        ),
      );
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('CLIMB'), findsOneWidget);
      expect(find.text('AVG HR'), findsOneWidget);
      expect(find.text('151'), findsOneWidget);
      expect(find.text('PACE'), findsNothing);
      expect(find.text('TIME'), findsNothing);
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
      await _pumpCanvas(
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

    testWidgets('the outline withholds the privacy zone', (tester) async {
      await _pumpCanvas(
        tester,
        RunStickerShareCard(
          run: _run(track: _zoneTrack),
          preferences: await _makePrefs(),
          privacyZones: const [_home],
        ),
      );
      final pts = _outline(tester);
      expect(pts.first.lng, closeTo(_away(1).lng, 1e-9));
      for (final p in pts) {
        expect(isInAnyZone(p.lat, p.lng, const [_home]), isFalse);
      }
    });

    testWidgets('a track wholly inside a zone draws no outline',
        (tester) async {
      await _pumpCanvas(
        tester,
        RunStickerShareCard(
          run: _run(track: const [Waypoint(lat: 51.44, lng: -0.27), _nearHome]),
          preferences: await _makePrefs(),
          privacyZones: const [_home],
        ),
      );
      expect(_hasOutline(tester), isFalse);
    });

    // The whole point of the sticker: a story editor can only place it if
    // the PNG is transparent around the figures. Read the real pixels.
    testWidgets('rasterises onto a transparent ground', (tester) async {
      final key = GlobalKey();
      const look = RunShareLook(layout: RunStickerLayout.strip);
      await _pumpCanvas(
        tester,
        RepaintBoundary(
          key: key,
          child: RunStickerShareCard(
            run: _run(track: _zoneTrack),
            preferences: await _makePrefs(),
            privacyZones: const [],
            look: look,
          ),
        ),
      );
      final ratio =
          shareImageExportWidthPx / RunStickerShareCard.canvasWidth(look);
      final rgba = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: ratio);
        final data =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return (image.width, image.height, data!);
      });
      final (width, height, data) = rgba!;
      expect(width, shareImageExportWidthPx.round());
      int alphaAt(int x, int y) => data.getUint8((y * width + x) * 4 + 3);
      expect(alphaAt(0, 0), 0, reason: 'top-left corner is painted');
      expect(alphaAt(width - 1, height - 1), 0,
          reason: 'bottom-right corner is painted');
      var opaque = 0;
      for (var i = 3; i < data.lengthInBytes; i += 4) {
        if (data.getUint8(i) > 0) opaque++;
      }
      expect(opaque, greaterThan(0), reason: 'the sticker drew nothing');
    });
  });

  group('photo', () {
    for (final aspect in RunPhotoAspect.values) {
      for (final layout in RunStickerLayout.values) {
        testWidgets('${layout.name} on a ${aspect.name} fits the canvas',
            (tester) async {
          await _pumpCanvas(
            tester,
            RunPhotoShareCard(
              run: _run(track: _hillTrack, extra: const {'avg_bpm': 148}),
              preferences: await _makePrefs(),
              title: 'Sunrise hill repeats with the club',
              privacyZones: const [],
              photo: _photo,
              look: RunShareLook(
                layout: layout,
                aspect: aspect,
                stats: const [
                  RunShareStatKind.distance,
                  RunShareStatKind.pace,
                  RunShareStatKind.time,
                  RunShareStatKind.climb,
                ],
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(RunPhotoShareCard)),
            RunPhotoShareCard.canvasFor(aspect),
          );
        });
      }
    }

    testWidgets('prints the title and stats over the photo', (tester) async {
      await _pumpCanvas(
        tester,
        RunPhotoShareCard(
          run: _run(track: _zoneTrack),
          preferences: await _makePrefs(),
          title: 'Morning run',
          privacyZones: const [],
          photo: _photo,
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Morning run'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('THREKIR'), findsOneWidget);
      expect(_outline(tester), hasLength(_zoneTrack.length));
    });

    testWidgets('the outline withholds the privacy zone', (tester) async {
      await _pumpCanvas(
        tester,
        RunPhotoShareCard(
          run: _run(track: _zoneTrack),
          preferences: await _makePrefs(),
          title: 'Morning run',
          privacyZones: const [_home],
          photo: _photo,
        ),
      );
      final pts = _outline(tester);
      expect(pts, hasLength(3));
      for (final p in pts) {
        expect(isInAnyZone(p.lat, p.lng, const [_home]), isFalse,
            reason: 'a drawn vertex sits inside the privacy zone');
      }
    });
  });

  group('share sheet', () {
    Future<void> openSheet(
      WidgetTester tester, {
      Future<XFile?> Function()? pick,
      RunShareImageSaver? save,
      RunShareUrlOpener? openUrl,
      Run? run,
      Map<String, Object> prefs = const {},
    }) async {
      tester.view.physicalSize = const Size(1200, 3300);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final preferences = await _makePrefs(prefs);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showRunShareSheet(
                context,
                run: run ?? _run(),
                preferences: preferences,
                title: 'Morning run',
                privacyZones: const [],
                pickPhotoOverride: pick ?? () async => null,
                saveImageOverride: save ?? (_, __) async {},
                openUrlOverride: openUrl ?? (_) async => true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    ButtonStyleButton button(WidgetTester tester, String label) =>
        tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ));

    Future<void> tapChip(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the map card with save and share enabled',
        (tester) async {
      await openSheet(tester);
      expect(find.byType(RunShareCard), findsOneWidget);
      expect(find.text('Map card'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Sticker'), findsOneWidget);
      expect(button(tester, 'Image').enabled, isTrue);
      expect(button(tester, 'Save to Photos').enabled, isTrue);
      // The map card has no look to edit.
      expect(find.text('Layout'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'choosing Photo opens the picker; cancelling it leaves save and share '
        'disabled until a photo is chosen', (tester) async {
      var picks = 0;
      await openSheet(tester, pick: () async {
        picks++;
        return null;
      });
      await tapChip(tester, 'Photo');
      expect(picks, 1);
      expect(find.byType(RunPhotoShareCard), findsNothing);
      expect(find.text('Choose a photo'), findsOneWidget);
      expect(button(tester, 'Image').enabled, isFalse);
      expect(button(tester, 'Save to Photos').enabled, isFalse);

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
      expect(button(tester, 'Image').enabled, isFalse);
      // Let the banner's dismiss timer run out so none is left pending.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the sticker shows its hint and the look controls',
        (tester) async {
      await openSheet(tester);
      await tapChip(tester, 'Sticker');
      expect(find.byType(RunStickerShareCard), findsOneWidget);
      expect(find.byType(RunShareCard), findsNothing);
      expect(find.textContaining('Transparent background'), findsOneWidget);
      for (final label in ['Layout', 'Colour', 'Stats', 'Stack', 'Strip']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Size is the photo's choice; a sticker is cropped to its content.
      expect(find.text('Size'), findsNothing);
      expect(button(tester, 'Image').enabled, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a look change redraws the sticker and is kept for next time',
        (tester) async {
      await openSheet(tester);
      await tapChip(tester, 'Sticker');
      await tapChip(tester, 'Strip');
      await tapChip(tester, 'Black');
      final sticker =
          tester.widget<RunStickerShareCard>(find.byType(RunStickerShareCard));
      expect(sticker.look.layout, RunStickerLayout.strip);
      expect(sticker.look.ink, RunShareInk.dark);

      final stored = (await SharedPreferences.getInstance())
          .getString(shareLookPrefsKey);
      expect(stored, isNotNull);
      final json = jsonDecode(stored!) as Map<String, dynamic>;
      expect(json['layout'], 'strip');
      expect(json['ink'], 'dark');
    });

    testWidgets('opens with the look saved on this device', (tester) async {
      await openSheet(tester, prefs: {
        shareLookPrefsKey: jsonEncode(const RunShareLook(
          layout: RunStickerLayout.hero,
          ink: RunShareInk.brand,
        ).toJson()),
      });
      await tapChip(tester, 'Sticker');
      final sticker =
          tester.widget<RunStickerShareCard>(find.byType(RunStickerShareCard));
      expect(sticker.look.layout, RunStickerLayout.hero);
      expect(sticker.look.ink, RunShareInk.brand);
    });

    testWidgets(
        'offers only the stats the run has, and never lets the last one go',
        (tester) async {
      await openSheet(tester);
      await tapChip(tester, 'Sticker');
      FilterChip chip(String label) => tester.widget<FilterChip>(
          find.ancestor(of: find.text(label), matching: find.byType(FilterChip)));
      expect(find.widgetWithText(FilterChip, 'Climb'), findsNothing,
          reason: 'a run with no track has no climb to print');
      expect(find.widgetWithText(FilterChip, 'Avg HR'), findsNothing);

      await tapChip(tester, 'Time');
      await tapChip(tester, 'Pace');
      expect(chip('Distance').selected, isTrue);
      expect(chip('Distance').onSelected, isNull,
          reason: 'the only stat left must not be removable');
    });

    testWidgets(
        'a saved look counts only the stats this run can print toward the cap',
        (tester) async {
      // Saved on a hill run with a strap; this run has neither, so only two
      // of the four print and a third must still be addable.
      await openSheet(tester, prefs: {
        shareLookPrefsKey: jsonEncode(const RunShareLook(stats: [
          RunShareStatKind.distance,
          RunShareStatKind.pace,
          RunShareStatKind.climb,
          RunShareStatKind.heartRate,
        ]).toJson()),
      });
      await tapChip(tester, 'Sticker');
      final time = tester.widget<FilterChip>(
          find.ancestor(of: find.text('Time'), matching: find.byType(FilterChip)));
      expect(time.selected, isFalse);
      expect(time.onSelected, isNotNull,
          reason: 'stats the run cannot print were counted toward the cap');
      await tapChip(tester, 'Time');
      final sticker =
          tester.widget<RunStickerShareCard>(find.byType(RunStickerShareCard));
      expect(sticker.look.stats, [
        RunShareStatKind.distance,
        RunShareStatKind.pace,
        RunShareStatKind.time,
      ]);
    });

    testWidgets('offers climb and heart rate when the run measured them',
        (tester) async {
      await openSheet(tester,
          run: _run(track: _hillTrack, extra: const {'avg_bpm': 150}));
      await tapChip(tester, 'Sticker');
      expect(find.widgetWithText(FilterChip, 'Climb'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Avg HR'), findsOneWidget);
    });

    testWidgets('Save writes the sticker PNG to the photo library',
        (tester) async {
      Uint8List? saved;
      String? savedName;
      await openSheet(tester, save: (png, name) async {
        saved = png;
        savedName = name;
      });
      await tapChip(tester, 'Sticker');
      await tester.ensureVisible(find.text('Save to Photos'));
      await tester.runAsync(() => tester.tap(find.text('Save to Photos')));
      await pumpUntil(
        tester,
        () => find.text('Saved to your photos').evaluate().isNotEmpty,
        describe: 'the saved banner',
      );
      expect(savedName, contains('sticker'));
      expect(saved!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47],
          reason: 'the saver was not handed a PNG');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refused photo permission says how to grant it',
        (tester) async {
      await openSheet(tester,
          save: (_, __) async => throw const ShareSaveDenied());
      await tester.ensureVisible(find.text('Save to Photos'));
      await tester.runAsync(() => tester.tap(find.text('Save to Photos')));
      await pumpUntil(
        tester,
        () => find
            .text('Allow photo access in Settings to save images')
            .evaluate()
            .isNotEmpty,
        describe: 'the permission banner',
      );
      expect(button(tester, 'Save to Photos').enabled, isTrue,
          reason: 'a refused save must not leave the sheet stuck busy');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a run with no line to draw is offered no Video style',
        (tester) async {
      await openSheet(tester);
      expect(find.text('Sticker'), findsOneWidget);
      expect(find.text('Video'), findsNothing);
    });

    testWidgets(
        'Video explains the web export and opens this run in the browser',
        (tester) async {
      final opened = <Uri>[];
      await openSheet(
        tester,
        run: _run(track: [_away(1), _away(2), _away(3)]),
        openUrl: (url) async {
          opened.add(url);
          return true;
        },
      );
      await tapChip(tester, 'Video');
      expect(find.textContaining('vertical 3D flyover video'), findsOneWidget);
      expect(find.text('Image'), findsNothing);
      expect(find.text('Save to Photos'), findsNothing);
      expect(find.text('Layout'), findsNothing);

      await tester.tap(find.text('Open video export'));
      await tester.pump();
      expect(opened, [Uri.parse('https://threkir.com/runs/r1?video=1')]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a browser that will not open says so', (tester) async {
      await openSheet(
        tester,
        run: _run(track: [_away(1), _away(2), _away(3)]),
        openUrl: (_) async => false,
      );
      await tapChip(tester, 'Video');
      await tester.tap(find.text('Open video export'));
      await pumpUntil(
        tester,
        () => find
            .text("Couldn't open the browser. Try again.")
            .evaluate()
            .isNotEmpty,
        describe: 'the browser-error banner',
      );
      await tester.pump(const Duration(seconds: 5));
    });

    test('the export URL names the run on the configured web origin', () {
      expect(runVideoExportUrl('abc 1', webBase: 'https://preview.example/'),
          Uri.parse('https://preview.example/runs/abc%201?video=1'));
    });
  });
}
