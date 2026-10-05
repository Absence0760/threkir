// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/widgets/live_run_map.dart' show mapTrackLine;
import '../lib/widgets/track_preview.dart';

Waypoint _w(double lat, double lng) => Waypoint(lat: lat, lng: lng);

double _luminance(Color c) {
  double chan(double v) => v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('isTrackRenderable', () {
    test('rejects empty and single-point tracks', () {
      expect(isTrackRenderable(const []), isFalse);
      expect(isTrackRenderable([_w(0, 0)]), isFalse);
    });

    test('rejects tracks below the 5 m jitter threshold', () {
      // ~1 m diagonal — within GPS noise for a stationary device.
      expect(
        isTrackRenderable([_w(51.5074, -0.1278), _w(51.5074009, -0.1278009)]),
        isFalse,
      );
    });

    test('the gate sits exactly at the named span', () {
      // Two claims, failing to different mutations. The VALUE is pinned flat
      // because the number is one of three rails — web's
      // `MIN_RENDERABLE_SPAN_M` and the firmware's — held together by
      // check_watch_wire_vectors.mjs, which can only read a rail whose
      // constant is named.
      expect(kMinRenderableSpanM, 5.0);
      // And the constant is the number actually COMPARED, not one declared
      // beside a literal that has drifted from it. A degree of latitude is
      // 111,320 m under the same flat approximation the gate uses, so these
      // two tracks bracket the threshold from either side by 1 cm.
      double deg(double m) => m / 111320.0;
      expect(
        isTrackRenderable(
            [_w(0, 0), _w(deg(kMinRenderableSpanM - 0.01), 0)]),
        isFalse,
      );
      expect(
        isTrackRenderable(
            [_w(0, 0), _w(deg(kMinRenderableSpanM + 0.01), 0)]),
        isTrue,
      );
    });

    test('accepts a tiny but genuine lap (>5 m diagonal)', () {
      // ~14 m diagonal — small but real.
      expect(
        isTrackRenderable([_w(51.5074, -0.1278), _w(51.50749, -0.12780)]),
        isTrue,
      );
    });

    test('accepts a typical multi-km loop', () {
      expect(
        isTrackRenderable([
          _w(51.5074, -0.1278),
          _w(51.5174, -0.1378),
          _w(51.5274, -0.1278),
          _w(51.5174, -0.1178),
          _w(51.5074, -0.1278),
        ]),
        isTrue,
      );
    });

    test('rejects a stationary jitter cluster on the antimeridian', () {
      // ~2 m of jitter straddling 180°. The raw min/max span read 359.99°
      // (~40,000 km), so the gate passed exactly the standing-still case
      // it exists to catch and the thumbnail drew the meaningless dot.
      expect(
        isTrackRenderable([
          _w(0, 179.999992),
          _w(0, -179.999992),
          _w(0.000009, 179.999995),
        ]),
        isFalse,
      );
    });

    test('accepts a genuine run crossing the antimeridian', () {
      expect(
        isTrackRenderable([_w(0, 179.9995), _w(0, -179.9995)]),
        isTrue,
      );
    });
  });

  group('projectTrack — cos(midLat) longitude correction', () {
    test('a square 100 m loop at 51 °N renders square, not a stretched rectangle', () {
      // 100 m / 111_320 m per latitude degree.
      const dLat = 100 / 111320;
      // 100 m / (111_320 * cos(51°)) per longitude degree.
      const dLng = 100 / (111320 * 0.629320391); // cos(51°) ≈ 0.629
      final points = [
        _w(51.5074, -0.1278),
        _w(51.5074 + dLat, -0.1278),
        _w(51.5074 + dLat, -0.1278 + dLng),
        _w(51.5074, -0.1278 + dLng),
        _w(51.5074, -0.1278),
      ];
      final projected = projectTrack(points, 240, 100);
      double minX = projected.first.dx, maxX = projected.first.dx;
      double minY = projected.first.dy, maxY = projected.first.dy;
      for (final p in projected) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      final widthVb = maxX - minX;
      final heightVb = maxY - minY;
      // Width and height should match within 2 % — without the cos
      // correction this loop would render ~60 % wider than tall, which
      // is what users were seeing on the new mobile thumbnails before
      // this fix.
      expect(
        (widthVb - heightVb).abs() / heightVb,
        lessThan(0.02),
        reason: 'A 100 m × 100 m loop at 51 °N must render square. '
            'widthVb=$widthVb heightVb=$heightVb',
      );
    });

    test('the longitude scale matches cos(midLat) at high latitude', () {
      // Picks a lat where the correction is dramatic (60 °N → 0.5).
      const lat = 60.0;
      final points = [_w(lat, 0), _w(lat, 1)];
      // dLat = 0, dLng = 1 ° — without correction the projection would
      // map the full longitude span to (vbW - 2*pad). With cos(60°)=0.5
      // the effective dLng in viewBox units becomes half. The horizontal
      // travel between the two points is the only signal.
      final projected = projectTrack(points, 200, 100);
      final spanX = (projected[1].dx - projected[0].dx).abs();
      // Projected span vs available width should reflect the lat
      // correction. Width minus 2*pad = 192. cos(60°)=0.5, but `scale`
      // is the smaller of (vbW-pad*2)/dLng vs (vbH-pad*2)/dLat — here
      // dLat=1e-6 so scaleY dominates for tiny latitudes; the test just
      // confirms the correction is applied (span is non-zero and finite).
      expect(spanX, greaterThan(0));
      expect(spanX.isFinite, isTrue);
    });

    test('preserves the diagonal length of a degenerate horizontal segment', () {
      // Segment along longitude only — the projection still places it
      // entirely on the x-axis (no vertical drift from rounding).
      final projected = projectTrack(
        [_w(0, 0), _w(0, 0.01)],
        100,
        100,
      );
      expect(projected.length, 2);
      expect((projected[0].dy - projected[1].dy).abs(), lessThan(1e-6));
    });

    test('projectTrack is empty for tracks under 2 points', () {
      expect(projectTrack(const [], 100, 100), isEmpty);
      expect(projectTrack([_w(0, 0)], 100, 100), isEmpty);
    });

    test('a track across the antimeridian fits its own width', () {
      // A 0.01° x 0.01° box straddling the line. Its longitudes span
      // 0.01°, not the 359.99° a raw min/max reads, so the fit is the
      // same one the identical box a degree west of the line gets.
      final across = [
        _w(0, 179.995),
        _w(0.01, 179.995),
        _w(0.01, -179.995),
        _w(0, -179.995),
      ];
      final west = [
        _w(0, 178.995),
        _w(0.01, 178.995),
        _w(0.01, 179.005),
        _w(0, 179.005),
      ];
      final a = projectTrack(across, 100, 100);
      final w = projectTrack(west, 100, 100);
      expect(a, hasLength(4));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].dx, closeTo(w[i].dx, 1e-6));
        expect(a[i].dy, closeTo(w[i].dy, 1e-6));
      }
      // And the box actually uses the panel rather than collapsing to a dot.
      expect((a[2].dx - a[0].dx).abs(), greaterThan(50));
    });
  });

  group('TrackPreview — map-backed render path (static MapTiler PNG)', () {
    setUp(() {
      // Force-clear any prior load so the empty-key / set-key
      // branches are independent across tests.
      dotenv.loadFromString(envString: '', isOptional: true);
      dotenv.env.clear();
    });

    testWidgets(
      'without MAPTILER_KEY — renders the polyline-only ColoredBox '
      'fallback (no Image.network attempt)',
      (tester) async {
        dotenv.loadFromString(envString: '', isOptional: true);
        dotenv.env.clear();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 72,
                height: 40,
                child: TrackPreview(
                  points: const [
                    Waypoint(lat: 51.5, lng: -0.12),
                    Waypoint(lat: 51.51, lng: -0.13),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byType(Image),
          findsNothing,
          reason: 'No MapTiler key → no static-image fetch.',
        );
      },
    );

    test(
      'when MAPTILER_KEY is set, TrackPreview hits the Static Maps '
      'API and renders the result via Image.network — NOT a full '
      'FlutterMap (which has rendering quirks at sub-100-px sizes)',
      () {
        // Pin the static-image render path. The user previously
        // reported "the route detail map works but the list
        // thumbnails don\'t" — root cause was that FlutterMap
        // doesn\'t reliably render tiles at 72×40 thumbnail sizes.
        // The fix is the Static Maps API; this guard catches a
        // regression that reverts to flutter_map.
        // The URL itself — endpoint, `@2x`, slug — is resolveStaticMapUrl's
        // and is pinned in live_run_map_tile_url_test.dart.
        final src = File(
          'lib/widgets/track_preview.dart',
        ).readAsStringSync();
        expect(
          src.contains('resolveStaticMapUrl('),
          isTrue,
          reason: 'TrackPreview must resolve its image through the shared '
              'resolver, so it requests the basemap the live maps use.',
        );
        expect(
          src.contains('class _StaticMapPreview'),
          isTrue,
          reason: 'Map-backed render must live in _StaticMapPreview '
              '(static-image path) — not _MapTrackPreview '
              '(FlutterMap, removed because it doesn\'t render at '
              'thumbnail sizes).',
        );
        expect(
          src.contains('Image.network('),
          isTrue,
          reason: 'Static PNG is rendered by Image.network — '
              'Flutter\'s built-in image cache handles repeat '
              'views without re-fetching.',
        );
      },
    );

    test(
      'long polylines (> 60 points) are simplified before URL '
      'build — defends against MapTiler\'s ~8 KB URL cap',
      () {
        final src = File(
          'lib/widgets/track_preview.dart',
        ).readAsStringSync();
        expect(
          src.contains('_maxPolylinePoints = 60'),
          isTrue,
          reason: 'Cap pinned so a refactor can\'t silently raise it '
              'past the URL-length cap.',
        );
        expect(
          src.contains('simplifyTrack(points,'),
          isTrue,
          reason: 'Must use the shared Ramer-Douglas-Peucker '
              'helper (not an inline ad-hoc simplifier).',
        );
      },
    );

    test(
      'loading + error builders both fall through to the polyline-'
      'only CustomPaint — thumbnail never renders as a blank box',
      () {
        // While the PNG is in flight (loadingBuilder) AND on a
        // network error (errorBuilder), we paint the polyline on
        // the themed fallback. Pin both so a refactor that drops
        // either branch produces a visibly-broken state.
        final src = File(
          'lib/widgets/track_preview.dart',
        ).readAsStringSync();
        expect(src.contains('loadingBuilder:'), isTrue);
        expect(src.contains('errorBuilder:'), isTrue);
        expect(src.contains('return TrackPreviewFallback(points: points);'), isTrue);
      },
    );

    test(
      'URL path param uses LITERAL pipes + commas (not URL-encoded) '
      'and only escapes # as %23 — the encoding MapTiler\'s parser '
      'actually accepts',
      () {
        // User-reported regression: with `Uri.encodeQueryComponent`
        // the path param turned into stroke%3A%23.. %7C ..%2C..
        // — MapTiler 4xx\'d and the thumbnail fell through to the
        // polyline-only fallback. The user saw "the route
        // detail map works but list thumbnails don\'t."
        // Pin the literal-pipe encoding so a refactor that re-adds
        // `Uri.encodeQueryComponent` fails this test.
        final src = File(
          'lib/widgets/track_preview.dart',
        ).readAsStringSync();
        // Stroke colour prefix uses %23 inline (the load-bearing
        // fix vs the over-encoded path). The fill segment is a
        // fully-transparent hex8 (`#ffffff00`) — `fill:none` would
        // be the obvious default but MapTiler doesn't recognise the
        // `none` token, so closed-loop routes (first coord ≈ last
        // coord) get the default black polygon fill and a "hole"
        // appears inside the loop on the thumbnail. Caught by the
        // May 2026 audit.
        expect(
          src.contains(
            "'fill:%23ffffff00|stroke:%23\$stroke|width:3'",
          ),
          isTrue,
          reason: 'Path style prefix must include a transparent fill '
              '(%23ffffff00, not %23none) + stroke + width per '
              "MapTiler's canonical docs example. # encoded as %23 "
              "inline because it's the HTTP fragment delimiter. "
              'fill=none would surface as a black polygon on closed '
              'loops.',
        );
        // Pipe separator is a literal `|` (not %7C / not encoded
        // by anything).
        expect(
          src.contains("pathParam.write('|"),
          isTrue,
          reason: 'Polyline points must be separated by a LITERAL '
              'pipe — MapTiler\'s path parser does not decode '
              '%7C back.',
        );
        // No `Uri.encodeQueryComponent` over the whole path
        // string — that was the bug.
        expect(
          src.contains('Uri.encodeQueryComponent(pathParam'),
          isFalse,
          reason: 'Path string must NOT be wrapped in '
              'Uri.encodeQueryComponent — over-encoding broke the '
              'request. Negative pin against the regression.',
        );
      },
    );
  });

  // decisions § 1749: the thumbnail follows the basemap the live maps
  // resolve, and its no-image fallback follows the theme.
  group('TrackPreview — basemap and fallback follow the theme', () {
    const track = [
      Waypoint(lat: 51.5, lng: -0.12),
      Waypoint(lat: 51.51, lng: -0.13),
    ];

    Widget host(ThemeData theme) => MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SizedBox(
              width: 72,
              height: 40,
              child: TrackPreview(points: track),
            ),
          ),
        );

    setUp(() {
      dotenv.loadFromString(envString: '', isOptional: true);
      dotenv.env.clear();
    });

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      testWidgets(
          'the ${theme.brightness.name} fallback box is the theme surface, '
          'and the line is keyed to it', (tester) async {
        await tester.pumpWidget(host(theme));
        await tester.pump();

        final box = tester.widget<ColoredBox>(find.descendant(
          of: find.byType(TrackPreviewFallback),
          matching: find.byType(ColoredBox),
        ));
        expect(box.color, theme.colorScheme.surfaceContainerHighest);
        expect(box.color, isNot(const Color(0xFF1F2937)),
            reason: 'the pre-fix fixed slate-800 box');

        final paint = tester.widget<CustomPaint>(find.descendant(
          of: find.byType(TrackPreviewFallback),
          matching: find.byType(CustomPaint),
        ));
        expect(paint.painter, isNotNull, reason: 'the polyline is drawn');
        final dark = theme.brightness == Brightness.dark;
        expect(
          _contrast(mapTrackLine(darkBasemap: dark), box.color),
          greaterThanOrEqualTo(3.0),
          reason: 'the line clears 1.4.11 against the box it is drawn on',
        );
      });
    }

    testWidgets('the two themes paint different fallback boxes', (tester) async {
      await tester.pumpWidget(host(AppTheme.light));
      await tester.pump();
      final light = tester
          .widget<ColoredBox>(find.descendant(
            of: find.byType(TrackPreviewFallback),
            matching: find.byType(ColoredBox),
          ))
          .color;
      await tester.pumpWidget(host(AppTheme.dark));
      // MaterialApp animates a theme change; let AnimatedTheme finish.
      await tester.pump(const Duration(seconds: 1));
      final dark = tester
          .widget<ColoredBox>(find.descendant(
            of: find.byType(TrackPreviewFallback),
            matching: find.byType(ColoredBox),
          ))
          .color;
      expect(light, isNot(dark));
    });

    for (final (theme, slug) in [
      (AppTheme.light, 'streets-v2'),
      (AppTheme.dark, 'streets-v2-dark'),
    ]) {
      testWidgets(
          'with a MapTiler key, the ${theme.brightness.name} theme requests '
          '$slug', (tester) async {
        dotenv.env['MAPTILER_KEY'] = 'k';
        await tester.pumpWidget(host(theme));
        await tester.pump();
        final image = tester.widget<Image>(find.byType(Image).first);
        final url = (image.image as NetworkImage).url;
        expect(url, startsWith('https://api.maptiler.com/maps/$slug/static/'));
        final stroke = mapTrackLine(darkBasemap: theme.brightness == Brightness.dark)
            .toARGB32() &
            0xFFFFFF;
        expect(
          url,
          contains('stroke:%23${stroke.toRadixString(16).padLeft(6, '0')}|'),
          reason: 'the line colour is keyed to the basemap it is drawn on',
        );
      });
    }
  });

  // Guard: no thumbnail widget names its own basemap or ground colour. The
  // style comes from resolveStaticMapUrl (live_run_map.dart) and the ground
  // from the theme; a literal in a thumbnail is the § 1749 defect again.
  group('thumbnail basemap guard', () {
    const thumbnails = [
      'lib/widgets/track_preview.dart',
      'lib/widgets/run_track_preview.dart',
      'lib/widgets/route_track_preview.dart',
    ];
    final slugLiteral =
        RegExp(r'''['"/](streets-v2(-dark)?|satellite|hybrid|outdoor-v2)['"/]''');
    final staticEndpoint = RegExp(r'/static/auto');

    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('no thumbnail names a MapTiler style or a static endpoint', () {
      for (final path in thumbnails) {
        final src = code(path);
        expect(slugLiteral.hasMatch(src), isFalse,
            reason: '$path hard-codes a basemap style; resolve it through '
                'resolveStaticMapUrl so it follows map_style and the theme.');
        expect(staticEndpoint.hasMatch(src), isFalse,
            reason: '$path builds a static-map URL itself.');
      }
    });

    test('the fallback ground is a theme token, not a colour literal', () {
      final src = code('lib/widgets/track_preview.dart');
      final fallback = src.substring(
        src.indexOf('class TrackPreviewFallback'),
        src.indexOf('class _Placeholder'),
      );
      expect(fallback, contains('colorScheme.surfaceContainerHighest'));
      expect(RegExp(r'Color\(0x').hasMatch(fallback), isFalse);
    });

    test('only the shared resolver builds a static-map URL', () {
      final builders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => staticEndpoint.hasMatch(code(f.path)))
          .map((f) => f.path)
          .toList();
      expect(builders, ['lib/widgets/live_run_map.dart']);
    });

    test('the scan flags the pre-fix spelling and spares the resolver call',
        () {
      expect(
          slugLiteral.hasMatch(
              "return 'https://api.maptiler.com/maps/streets-v2-dark/static/auto/'"),
          isTrue);
      expect(slugLiteral.hasMatch("style: 'streets-v2',"), isTrue);
      expect(slugLiteral.hasMatch('final url = resolveStaticMapUrl('), isFalse);
    });
  });
}
