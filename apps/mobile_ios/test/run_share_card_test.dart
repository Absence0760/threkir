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
import '../lib/flyover_video_flag.dart';
import '../lib/preferences.dart';
import '../lib/privacy.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/run_share_stats.dart';
import '../lib/park_courses.dart' show RunParkCourseTime;
import '../lib/share_look.dart';
import '../lib/share_placement.dart';
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

    testWidgets('with the mark turned off carries no Threkir signature',
        (tester) async {
      await tester.pumpWidget(_app(SizedBox(
        width: 400,
        height: 500,
        child: RunShareCard(
          run: _run(),
          preferences: await _makePrefs(),
          title: 'Morning run',
          privacyZones: const [],
          mark: false,
        ),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('THREKIR'), findsNothing);
      expect(find.byType(ThrekirShareBrand), findsNothing);
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

    for (final layout in RunStickerLayout.values) {
      testWidgets('${layout.name} with the mark off draws no signature',
          (tester) async {
        await _pumpCanvas(
          tester,
          RunStickerShareCard(
            run: _run(track: _hillTrack),
            preferences: await _makePrefs(),
            privacyZones: const [],
            look: RunShareLook(layout: layout, mark: false),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('THREKIR'), findsNothing);
        expect(find.text('DISTANCE'), findsOneWidget);
      });
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

  group('occasion sticker', () {
    SplitsStickerBody splitsBody(int n) => SplitsStickerBody('$n splits', [
          for (var i = 0; i < n; i++)
            SplitsStickerEntry(
              '${i + 1}',
              '5:${(i % 50 + 10).toString().padLeft(2, '0')}',
              SplitsStickerRow(
                  paceSecPerKm: 300.0 + (i * 7) % 23, metres: 1000),
            ),
        ]);

    final bodies = <String, RunOccasionBody>{
      'splits': splitsBody(5),
      'pr': prStickerBody(
        headline: 'New personal record',
        distance: '5K',
        time: '22:41',
        improvement: '18s faster',
        hasRoute: true,
      ),
      'streak': streakStickerBody(
          kicker: 'Streak', days: '147', caption: 'days in a row'),
      'race timed': raceStickerBody(
          name: 'Richmond Marathon',
          finisher: 'Finisher',
          time: '3:41:07',
          hasRoute: true),
      'race untimed': raceStickerBody(
          name: 'Richmond Marathon', finisher: 'Finisher', hasRoute: false),
      'badge': badgeStickerBody(
          kicker: 'Badge earned', name: 'Marathon finisher', tier: 'Gold'),
      'course ranked': courseStickerBody(
          kicker: 'Park course time',
          name: 'Beaver Lake Trail, the long way round the north shore',
          park: 'Pocahontas State Park',
          time: '24:12',
          rank: '#3 in 2027',
          hasRoute: true),
      'course unranked': courseStickerBody(
          kicker: 'Park course time',
          name: 'Beaver Lake Trail',
          park: 'Pocahontas State Park',
          time: '24:12',
          hasRoute: false),
      'route': routeStickerBody(),
    };

    for (final MapEntry(key: name, value: body) in bodies.entries) {
      for (final ink in RunShareInk.values) {
        testWidgets('$name in ${ink.name} lays out without overflow, signed',
            (tester) async {
          await _pumpCanvas(
            tester,
            RunStickerShareCard(
              run: _run(track: _hillTrack),
              preferences: await _makePrefs(),
              privacyZones: const [],
              look: RunShareLook(kind: RunStickerKind.splits, ink: ink),
              occasion: body,
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('THREKIR'), findsOneWidget);
          expect(find.byType(RunStickerContent), findsNothing);
          expect(
              tester.getSize(find.byType(RunStickerShareCard)).width,
              RunStickerShareCard.canvasWidth(const RunShareLook(),
                  occasion: true));
        });
      }
    }

    testWidgets('with the mark off an occasion draws no signature',
        (tester) async {
      await _pumpCanvas(
        tester,
        RunStickerShareCard(
          run: _run(track: _hillTrack),
          preferences: await _makePrefs(),
          privacyZones: const [],
          look: const RunShareLook(mark: false),
          occasion: bodies['streak'],
        ),
      );
      expect(find.text('THREKIR'), findsNothing);
      expect(find.text('147'), findsOneWidget);
    });

    testWidgets(
        'a full column and a full pair of columns fit the splits budget, and '
        'one more row changes form', (tester) async {
      final cap = OccasionLayout.splitsCapacity(22);
      expect(cap, greaterThan(0));
      final budget = splitsStickerMaxHeight(22);
      for (final n in [cap, cap + 1, cap * 2, cap * 2 + 1, 120]) {
        await _pumpCanvas(
          tester,
          RunStickerShareCard(
            run: _run(),
            preferences: await _makePrefs(),
            privacyZones: const [],
            occasion: splitsBody(n),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$n rows');
        final h = tester.getSize(find.byType(RunStickerShareCard)).height;
        expect(h, lessThanOrEqualTo(budget), reason: '$n rows: $h');
        final bars = find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is SplitBarsPainter);
        expect(bars, n > cap * 2 ? findsOneWidget : findsNothing,
            reason: '$n rows');
      }
    });

    testWidgets('the fastest split takes the accent', (tester) async {
      await _pumpCanvas(
        tester,
        RunStickerShareCard(
          run: _run(),
          preferences: await _makePrefs(),
          privacyZones: const [],
          occasion: splitsBody(6),
        ),
      );
      final accent = RunShareInkSpec.of(RunShareInk.light).accent;
      final first = tester.widget<Text>(find.text('1'));
      expect(first.style?.color, accent);
      final second = tester.widget<Text>(find.text('2'));
      expect(second.style?.color, isNot(accent));
    });

    testWidgets('an occasion sticker rasterises onto a transparent ground',
        (tester) async {
      final key = GlobalKey();
      await _pumpCanvas(
        tester,
        RepaintBoundary(
          key: key,
          child: RunStickerShareCard(
            run: _run(track: _zoneTrack),
            preferences: await _makePrefs(),
            privacyZones: const [],
            occasion: bodies['race timed'],
          ),
        ),
      );
      final ratio = shareImageExportWidthPx /
          RunStickerShareCard.canvasWidth(const RunShareLook(), occasion: true);
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
      expect(alphaAt(0, 0), 0);
      expect(alphaAt(width - 1, height - 1), 0);
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

    testWidgets(
        'the default block sits centred on the frame bottom, clear of the '
        'story reply bar', (tester) async {
      final probe = SharePlacementProbe();
      await _pumpCanvas(
        tester,
        RunPhotoShareCard(
          run: _run(track: _zoneTrack),
          preferences: await _makePrefs(),
          title: 'Morning run',
          privacyZones: const [],
          photo: _photo,
          probe: probe,
        ),
      );
      final card = tester.getRect(find.byType(RunPhotoShareCard));
      final content = tester.getRect(find.byType(RunStickerContent));
      expect(content.bottom - card.top, closeTo(640 * 0.87, 0.5));
      expect(content.center.dx - card.left, closeTo(180, 0.5));
      expect(probe.placed!.scale, 1);
    });

    testWidgets('a placement moves and scales the whole block inside the frame',
        (tester) async {
      Future<(Rect, Rect, Rect)> pumpAt(SharePlacement placement) async {
        await _pumpCanvas(
          tester,
          RunPhotoShareCard(
            run: _run(track: _zoneTrack),
            preferences: await _makePrefs(),
            title: 'Morning run',
            privacyZones: const [],
            photo: _photo,
            look: const RunShareLook().withPlacement(placement),
          ),
        );
        final card = tester.getRect(find.byType(RunPhotoShareCard));
        return (
          card,
          tester.getRect(find.text('Morning run')).shift(-card.topLeft),
          tester.getRect(find.byType(RunStickerContent)).shift(-card.topLeft),
        );
      }

      final (_, title, full) =
          await pumpAt(const SharePlacement(x: 0.5, y: 0.5, scale: 1));
      final (_, smallTitle, half) =
          await pumpAt(const SharePlacement(x: 0.5, y: 0.5, scale: 0.5));
      expect(half.width, closeTo(full.width / 2, 0.5));
      expect(smallTitle.height, closeTo(title.height / 2, 0.5));
      for (final corner in [
        const SharePlacement(x: 0, y: 0, scale: 0.5),
        const SharePlacement(x: 1, y: 1, scale: 0.5),
      ]) {
        final (_, t, c) = await pumpAt(corner);
        expect(t.top, greaterThanOrEqualTo(20 - 0.5));
        expect(c.left, greaterThanOrEqualTo(20 - 0.5));
        expect(c.right, lessThanOrEqualTo(340 + 0.5));
        expect(c.bottom, lessThanOrEqualTo(640 * 0.87 + 0.5));
      }
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
    setUp(() => dotenv.env[kFlyoverVideoEnvKey] = 'true');
    tearDown(() => dotenv.env.remove(kFlyoverVideoEnvKey));

    Future<void> openSheet(
      WidgetTester tester, {
      Future<XFile?> Function()? pick,
      RunShareImageSaver? save,
      RunShareUrlOpener? openUrl,
      Run? run,
      Map<String, Object> prefs = const {},
      RunShareCourseLoader? courseLoad,
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
                courseLoad: courseLoad,
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

    testWidgets('a park course time is offered as a sticker and prints its rank',
        (tester) async {
      await openSheet(tester,
          courseLoad: () async => const RunParkCourseTime(
              courseName: 'Beaver Lake Trail',
              parkName: 'Pocahontas State Park',
              timeSeconds: 1452,
              season: 2027,
              seasonRank: 3));
      await tapChip(tester, 'Sticker');
      await tapChip(tester, 'Park course');
      expect(find.text('Beaver Lake Trail'), findsOneWidget);
      expect(find.text('Pocahontas State Park'), findsOneWidget);
      expect(find.text('#3 in 2027'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed course read leaves the course sticker unoffered',
        (tester) async {
      await openSheet(tester, courseLoad: () async => throw Exception('offline'));
      await tapChip(tester, 'Sticker');
      expect(find.text('Park course'), findsNothing);
      expect(tester.takeException(), isNull);
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

    testWidgets('the mark switch drops the signature and is kept for next '
        'time', (tester) async {
      await openSheet(tester);
      await tapChip(tester, 'Sticker');
      final markSwitch = find.byKey(const ValueKey('share-mark'));
      await tester.ensureVisible(markSwitch);
      expect(tester.widget<Switch>(markSwitch).value, isTrue);
      await tester.tap(markSwitch);
      await tester.pumpAndSettle();

      final sticker =
          tester.widget<RunStickerShareCard>(find.byType(RunStickerShareCard));
      expect(sticker.look.mark, isFalse);
      final json = jsonDecode((await SharedPreferences.getInstance())
          .getString(shareLookPrefsKey)!) as Map<String, dynamic>;
      expect(json['mark'], isFalse);

      await tapChip(tester, 'Map card');
      expect(
          tester.widget<RunShareCard>(find.byType(RunShareCard)).mark, isFalse);
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

    testWidgets(
        'offers an occasion sticker only when the run has its data, and keeps '
        'the kind for next time', (tester) async {
      await openSheet(
        tester,
        run: _run(
          // ~3.3 km of timestamped fixes: three whole km splits.
          track: [
            for (var i = 0; i < 16; i++)
              Waypoint(
                lat: 51.44 + i * 0.002,
                lng: -0.27,
                timestamp: DateTime.utc(2026, 4, 15, 8, i),
              ),
          ],
          extra: const {'race_name': 'Riverside 5K', 'chip_time': '24:31'},
        ),
      );
      await tapChip(tester, 'Sticker');
      expect(find.text('Highlight'), findsOneWidget);
      for (final offered in ['Splits', 'Race']) {
        expect(find.widgetWithText(ChoiceChip, offered), findsOneWidget,
            reason: offered);
      }
      for (final hidden in ['PR', 'Streak', 'Badge']) {
        expect(find.widgetWithText(ChoiceChip, hidden), findsNothing,
            reason: hidden);
      }
      await tapChip(tester, 'Race');
      final sticker =
          tester.widget<RunStickerShareCard>(find.byType(RunStickerShareCard));
      expect(sticker.occasion, isA<OccasionLinesBody>());
      expect(find.text('24:31'), findsOneWidget);
      // The layouts and stat chips belong to the stats sticker.
      expect(find.text('Layout'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Distance'), findsNothing);
      expect(tester.takeException(), isNull);

      final stored = (await SharedPreferences.getInstance())
          .getString(shareLookPrefsKey);
      expect((jsonDecode(stored!) as Map<String, dynamic>)['kind'], 'race');
    });

    testWidgets('a remembered kind the run cannot print draws the stats',
        (tester) async {
      await openSheet(tester, prefs: {
        shareLookPrefsKey: jsonEncode(
            const RunShareLook(kind: RunStickerKind.race).toJson()),
      });
      await tapChip(tester, 'Sticker');
      final sticker =
          tester.widget<RunStickerShareCard>(find.byType(RunStickerShareCard));
      expect(sticker.occasion, isNull);
      expect(find.byType(RunStickerContent), findsOneWidget);
      expect(find.text('Highlight'), findsNothing);
    });

    testWidgets('offers climb and heart rate when the run measured them',
        (tester) async {
      await openSheet(tester,
          run: _run(track: _hillTrack, extra: const {'avg_bpm': 150}));
      await tapChip(tester, 'Sticker');
      expect(find.widgetWithText(FilterChip, 'Climb'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Avg HR'), findsOneWidget);
    });

    /// Opens the sheet on the Photo style with a decoded photo in it.
    Future<void> openPhoto(WidgetTester tester,
        {RunShareImageSaver? save, Map<String, Object> prefs = const {}}) async {
      late File file;
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('share_photo');
        file = File('${dir.path}/photo.png');
        await file.writeAsBytes(_photo.bytes);
      });
      addTearDown(() => file.parent.deleteSync(recursive: true));
      await openSheet(tester,
          pick: () async => XFile(file.path), save: save, prefs: prefs);
      await tester.tap(find.text('Photo'));
      await pumpUntil(
        tester,
        () => find.byType(RunPhotoShareCard).evaluate().isNotEmpty,
        describe: 'the photo card',
      );
      await tester.pumpAndSettle();
    }

    SharePlacement placementOf(WidgetTester tester) => tester
        .widget<RunPhotoShareCard>(find.byType(RunPhotoShareCard))
        .look
        .placement;

    Rect blockOf(WidgetTester tester) =>
        tester.getRect(find.byType(RunStickerContent));

    testWidgets(
        'dragging the photo stats moves them, and the placement is kept for '
        'next time', (tester) async {
      await openPhoto(tester);
      expect(placementOf(tester), SharePlacement.initial);
      final semantics = tester.getSemantics(
          find.bySemanticsLabel(RegExp(r'^Stats position')));
      expect(semantics.hint, contains('pinch'));
      final before = blockOf(tester);
      await tester.dragFrom(before.center, const Offset(0, -120));
      await tester.pumpAndSettle();
      final after = blockOf(tester);
      expect(after.top, lessThan(before.top - 60));
      expect(after.left, closeTo(before.left, 0.5));
      final moved = placementOf(tester);
      expect(moved.y, lessThan(0.8));

      final json = jsonDecode((await SharedPreferences.getInstance())
          .getString(shareLookPrefsKey)!) as Map<String, dynamic>;
      expect(SharePlacement.fromJson(json['placements']['story']), moved);
      expect(SharePlacement.fromJson(json['placements']['post']),
          SharePlacement.initial,
          reason: 'the post keeps its own placement');
    });

    testWidgets('a drag off the preview, not on the stats, leaves them put',
        (tester) async {
      await openPhoto(tester);
      final card = tester.getRect(find.byType(RunPhotoShareCard));
      await tester.dragFrom(card.topCenter + const Offset(0, 10),
          const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(placementOf(tester), SharePlacement.initial);
    });

    testWidgets('a pinch resizes the stats within the scale bounds',
        (tester) async {
      await openPhoto(tester);
      Future<void> pinch(double from, double to) async {
        final c = blockOf(tester).center;
        final a = await tester.startGesture(c - Offset(from, 0), pointer: 1);
        final b = await tester.startGesture(c + Offset(from, 0), pointer: 2);
        for (var i = 1; i <= 6; i++) {
          final d = from + (to - from) * i / 6;
          await a.moveTo(c - Offset(d, 0));
          await b.moveTo(c + Offset(d, 0));
          await tester.pump();
        }
        await a.up();
        await b.up();
        await tester.pumpAndSettle();
      }

      final full = blockOf(tester).width;
      await pinch(60, 45);
      final pinched = placementOf(tester).scale;
      expect(pinched, closeTo(0.75, 0.05));
      expect(blockOf(tester).width, closeTo(full * pinched, 1));
      // Far past either bound, the scale stops at it.
      await pinch(60, 2);
      expect(placementOf(tester).scale, 0.5);
      await pinch(10, 200);
      expect(placementOf(tester).scale, SharePlacement.maxScale);
    });

    testWidgets('a double tap on the stats puts them back, and so does Reset',
        (tester) async {
      await openPhoto(tester);
      final reset = find.byKey(const ValueKey('share-placement-reset'));
      expect(tester.widget<ButtonStyleButton>(reset).enabled, isFalse);
      await tester.dragFrom(blockOf(tester).center, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(placementOf(tester), isNot(SharePlacement.initial));
      expect(tester.widget<ButtonStyleButton>(reset).enabled, isTrue);

      final c = blockOf(tester).center;
      await tester.tapAt(c);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(c);
      await tester.pumpAndSettle();
      expect(placementOf(tester), SharePlacement.initial);

      await tester.dragFrom(blockOf(tester).center, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(placementOf(tester), SharePlacement.initial);
    });

    testWidgets('a drag past the bottom stops clear of the story reply bar',
        (tester) async {
      await openPhoto(tester, prefs: {
        shareLookPrefsKey: jsonEncode(const RunShareLook()
            .withPlacement(const SharePlacement(x: 0.5, y: 0.4, scale: 0.6))
            .toJson()),
      });
      expect(placementOf(tester),
          const SharePlacement(x: 0.5, y: 0.4, scale: 0.6),
          reason: 'the saved placement was not restored');
      await tester.dragFrom(blockOf(tester).center, const Offset(0, 900));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(RunPhotoShareCard));
      final k = card.height / 640;
      expect(blockOf(tester).bottom,
          lessThanOrEqualTo(card.top + 640 * 0.87 * k + 0.5));
      expect(blockOf(tester).bottom,
          greaterThan(card.top + 640 * 0.8 * k),
          reason: 'the drag did not reach the frame bottom');
    });

    testWidgets('the exported PNG draws the stats where the sheet shows them',
        (tester) async {
      Uint8List? saved;
      await openPhoto(tester, save: (png, _) async => saved = png, prefs: {
        shareLookPrefsKey: jsonEncode(const RunShareLook()
            .withPlacement(const SharePlacement(x: 0.3, y: 0.3, scale: 0.5))
            .toJson()),
      });
      final card = tester.getRect(find.byType(RunPhotoShareCard));
      final k = card.width / 360;
      final shown = blockOf(tester).shift(-card.topLeft);
      await tester.ensureVisible(find.text('Save to Photos'));
      await tester.runAsync(() => tester.tap(find.text('Save to Photos')));
      await pumpUntil(tester, () => saved != null, describe: 'the saved PNG');
      final decoded = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(saved!);
        final image = (await codec.getNextFrame()).image;
        final data =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return (image.width, image.height, data!);
      });
      final (width, height, data) = decoded!;
      expect([width, height], [1080, 1920]);
      // The white ink's box: the title, stats and signature, all inside the
      // block, and nothing of the dark photo.
      var (l, t, r, b) = (width, height, -1, -1);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          if (data.getUint8(i) > 245 &&
              data.getUint8(i + 1) > 245 &&
              data.getUint8(i + 2) > 245) {
            if (x < l) l = x;
            if (x > r) r = x;
            if (y < t) t = y;
            if (y > b) b = y;
          }
        }
      }
      final px = 1080 / 360;
      expect(r, greaterThan(l), reason: 'no white ink in the export');
      // The block in the export is the block the sheet shows, in canvas px.
      final block = Rect.fromLTRB(shown.left / k, shown.top / k,
          shown.right / k, shown.bottom / k);
      expect(l / px, greaterThanOrEqualTo(block.left - 2));
      expect(r / px, lessThanOrEqualTo(block.right + 2));
      expect(b / px, lessThanOrEqualTo(block.bottom + 2));
      expect(t / px, lessThan(block.top),
          reason: 'the title sits above the stats');
      expect(r / px, lessThan(360 / 2 + 1),
          reason: 'the block was exported at the default, not where it sits');
      await tester.pump(const Duration(seconds: 5));
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
        'a run with a line is offered no Video style while the web export is off',
        (tester) async {
      dotenv.env.remove(kFlyoverVideoEnvKey);
      await openSheet(tester, run: _run(track: [_away(1), _away(2), _away(3)]));
      expect(find.text('Sticker'), findsOneWidget);
      expect(find.text('Video'), findsNothing);
    });

    testWidgets('a run with a line is offered the Video style with the flag on',
        (tester) async {
      await openSheet(tester, run: _run(track: [_away(1), _away(2), _away(3)]));
      expect(find.text('Video'), findsOneWidget);
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
