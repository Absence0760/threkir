import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../basemap_credits.dart' show tileEnv;
import '../geo.dart' show unwrapLonDeg;
import '../preferences.dart' show activeMapStyle;
import '../route_simplify.dart' show simplifyTrack;
import 'live_run_map.dart'
    show currentBasemapIsDark, mapTrackLine, resolveStaticMapUrl;

/// Compact static thumbnail of a GPS track. Mirrors
/// `apps/web/src/lib/components/TrackPreview.svelte` so a route saved on
/// the web shows the same shape on the mobile list. No tiles, no
/// interaction — just a polyline with start (green) / end (red) caps and
/// a few directional chevrons so out-and-backs and overlapping loops
/// stay readable at thumbnail scale.
///
/// The basemap behind it is the one every live map resolves — the user's
/// `map_style` under the app theme, through [resolveStaticMapUrl] — and the
/// line colour is keyed on that ground, so a thumbnail never shows a dark
/// street map to a runner whose maps are light (decisions § 1749).
class TrackPreview extends StatelessWidget {
  final List<Waypoint> points;
  final double aspect;

  /// Module-level guard so the diagnostic log fires only once per
  /// process lifetime — a list of 20 thumbnails shouldn't print
  /// 20 identical lines on scroll.
  static bool _loggedKeyState = false;

  const TrackPreview({
    super.key,
    required this.points,
    this.aspect = 2.4,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const _Placeholder();
    }
    // Map-backed preview. We hit a SINGLE PNG endpoint that bakes
    // basemap + path-overlay into one image, then render it with
    // `Image.network` + Flutter's built-in image cache. Pre-fix,
    // the thumbnails mounted a full `FlutterMap` at 72×40 —
    // `flutter_map` has known rendering quirks at sub-100-px sizes
    // (tiles either don't load or load partially-cropped). The
    // static-image path is bulletproof at any size.
    return _StaticMapPreview(
      points: points,
      darkBasemap: currentBasemapIsDark(context),
      brightness: Theme.of(context).brightness,
    );
  }
}

/// Static-image track preview — one PNG with the basemap and the path
/// baked together, from MapTiler's Static Maps API or the local
/// tileserver-gl's `/styles/{id}/static/auto` endpoint, whichever
/// [resolveStaticMapUrl] picks. With neither configured it paints the
/// polyline-only fallback directly; a loading or failed image falls back
/// to the same paint so the thumbnail never reads as a blank box.
class _StaticMapPreview extends StatelessWidget {
  final List<Waypoint> points;
  final bool darkBasemap;
  final Brightness brightness;

  const _StaticMapPreview({
    required this.points,
    required this.darkBasemap,
    required this.brightness,
  });

  /// MapTiler's Static Maps URL has a practical length cap around
  /// ~8 KB. For a typical run (1000+ track points × 16 chars per
  /// point) we'd blow past that on the first kilometre. Simplify
  /// the polyline first — Ramer-Douglas-Peucker preserves the
  /// shape but drops noise. 60 points is enough resolution for a
  /// 72-px wide thumbnail (each polyline edge averaging ~1 px).
  static const int _maxPolylinePoints = 60;

  List<Waypoint> _simplifiedPath() {
    if (points.length <= _maxPolylinePoints) return points;
    // Bump epsilon until the count drops below the cap. Starting
    // at 10 m (the recorder's default) and doubling keeps the loop
    // bounded — 6 iterations cover 10 m → 320 m which is enough
    // for any sensible polyline.
    var epsilon = 10.0;
    var simplified = simplifyTrack(points, epsilonMetres: epsilon);
    for (var i = 0; i < 6 && simplified.length > _maxPolylinePoints; i++) {
      epsilon *= 2;
      simplified = simplifyTrack(points, epsilonMetres: epsilon);
    }
    return simplified;
  }

  /// The `path=` overlay. `auto` centre + zoom in the URL means the server
  /// fits the path bbox — no client-side projection math.
  ///
  /// Encoding subtlety: the path param expects LITERAL pipes (`|`) and
  /// commas (`,`) as its grammar. `Uri.encodeQueryComponent` turned those
  /// into `%7C` / `%2C`, which MapTiler's parser doesn't decode back, so
  /// every request 4xx'd and the list showed only the fallback. Only `#`
  /// (the HTTP fragment delimiter) is encoded, as `%23`.
  ///
  /// Fill is a fully-transparent hex8 (`#ffffff00`) rather than `none` —
  /// the path syntax doesn't recognise `none`, so closed loops got the
  /// default black polygon fill and a "hole" inside the loop.
  String _pathParam() {
    final stroke = (mapTrackLine(darkBasemap: darkBasemap).toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    final pathParam = StringBuffer(
      'fill:%23ffffff00|stroke:%23$stroke|width:3',
    );
    for (final p in _simplifiedPath()) {
      // lng,lat per the API (MapTiler reverses the typical Leaflet
      // lat,lng order).
      pathParam.write('|${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}');
    }
    return pathParam.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth.round().clamp(40, 1024)
              : 256;
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight.round().clamp(40, 1024)
              : 144;
          final url = resolveStaticMapUrl(
            tileEnv(),
            mapStyle: activeMapStyle,
            brightness: brightness,
            width: w,
            height: h,
            path: _pathParam(),
          );
          if (!TrackPreview._loggedKeyState) {
            TrackPreview._loggedKeyState = true;
            debugPrint(
              'TrackPreview build: points=${points.length}, '
              'source=${url == null ? 'fallback' : Uri.parse(url).host}',
            );
          }
          if (url == null) return TrackPreviewFallback(points: points);
          return Image.network(
            url,
            width: w.toDouble(),
            height: h.toDouble(),
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return TrackPreviewFallback(points: points);
            },
            errorBuilder: (context, error, stack) {
              // The URL goes to the device log so a fallback-only list can
              // be diagnosed by pasting it into a browser and reading the
              // server's 4xx body.
              debugPrint(
                'TrackPreview: static-map failed → $error\n  url: $url',
              );
              return TrackPreviewFallback(points: points);
            },
          );
        },
      ),
    );
  }
}

/// The polyline drawn on the theme's own surface — no basemap configured,
/// the image still loading, or the image failed. Both the box and the line
/// come from the theme: the box is `surfaceContainerHighest` so the card
/// reads as a map slot in either theme, and the line is [mapTrackLine] keyed
/// on that surface's luminance, the same rung it takes over a basemap of the
/// same luminance. It used to be a fixed slate-800 box, which in the light
/// theme was a near-black hole in a light list.
@visibleForTesting
class TrackPreviewFallback extends StatelessWidget {
  final List<Waypoint> points;

  const TrackPreviewFallback({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: CustomPaint(
          painter: _TrackPreviewPainter(
            points: points,
            color: mapTrackLine(
              darkBasemap: theme.brightness == Brightness.dark,
            ),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.map_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _TrackPreviewPainter extends CustomPainter {
  static const double _pad = 4;
  // Two arrows is plenty of direction cue on a list-sized thumbnail —
  // four crowded the line into noise.
  static const int _arrowCount = 2;
  // Stroke widths and marker sizes are expressed in the same "viewBox
  // units" the web SVG uses (short axis = 100), then scaled to the
  // canvas. The projection geometry (projectTrack) stays identical to
  // web, but the line is deliberately drawn thinner here than web's
  // 4.5/2.6: at the small size these thumbnails render on the routes
  // list a 2.6%-of-width stroke reads as a solid blob, so mobile uses
  // a slimmer line that reads as a route. Web keeps its thicker line.
  static const double _viewBoxShort = 100;

  final List<Waypoint> points;
  final Color color;

  _TrackPreviewPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;

    final aspect = size.width / size.height;
    final vbW = aspect >= 1 ? _viewBoxShort * aspect : _viewBoxShort;
    final vbH = aspect < 1 ? _viewBoxShort / aspect : _viewBoxShort;
    final pxPerVb = size.width / vbW;
    // Projection lives in projectTrack so the cos(midLat) correction can
    // be unit-tested without instantiating a Flutter canvas.
    final projected = [
      for (final o in projectTrack(points, vbW, vbH, pad: _pad))
        Offset(o.dx * pxPerVb, o.dy * pxPerVb),
    ];

    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (int i = 1; i < projected.length; i++) {
      path.lineTo(projected[i].dx, projected[i].dy);
    }

    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * pxPerVb
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawPath(path, casing);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * pxPerVb
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, line);

    if (projected.length >= 4) {
      for (int i = 1; i <= _arrowCount; i++) {
        final t = i / (_arrowCount + 1);
        final idx = max(1, (projected.length * t).floor());
        if (idx >= projected.length) continue;
        final a = projected[idx - 1];
        final b = projected[idx];
        final angle = atan2(b.dy - a.dy, b.dx - a.dx);
        _drawChevron(canvas, b, angle, pxPerVb);
      }
    }

    final startCap = Paint()..color = const Color(0xFF22C55E);
    final endCap = Paint()..color = const Color(0xFFEF4444);
    final capBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * pxPerVb
      ..color = Colors.white;
    canvas.drawCircle(projected.first, 1.9 * pxPerVb, startCap);
    canvas.drawCircle(projected.first, 1.9 * pxPerVb, capBorder);
    canvas.drawCircle(projected.last, 1.9 * pxPerVb, endCap);
    canvas.drawCircle(projected.last, 1.9 * pxPerVb, capBorder);
  }

  void _drawChevron(Canvas canvas, Offset at, double angle, double pxPerVb) {
    final cos_ = cos(angle);
    final sin_ = sin(angle);
    Offset rot(double x, double y) => Offset(
          at.dx + (x * cos_ - y * sin_) * pxPerVb,
          at.dy + (x * sin_ + y * cos_) * pxPerVb,
        );
    final p = Path()
      ..moveTo(rot(-1.3, -1.3).dx, rot(-1.3, -1.3).dy)
      ..lineTo(rot(1.2, 0).dx, rot(1.2, 0).dy)
      ..lineTo(rot(-1.3, 1.3).dx, rot(-1.3, 1.3).dy)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 * pxPerVb
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackPreviewPainter old) =>
      old.points != points || old.color != color;
}

/// Project `points` into a `[0, vbW] × [0, vbH]` viewBox with the
/// `cos(midLat)` longitude correction of `decisions.md § 51`. Pure helper
/// so the projection can be unit-tested without spinning up a Flutter
/// canvas, and so every track thumbnail in the app draws the same shape
/// for the same run — `run_screen`'s spark cards project through it too.
/// Mirrors `apps/web/src/lib/components/TrackPreview.svelte` — keep them
/// in lockstep.
List<Offset> projectTrack(List<Waypoint> points, double vbW, double vbH,
    {double pad = 4}) {
  if (points.length < 2) return const [];
  // Longitudes are expressed on the first point's side of the antimeridian,
  // so a track that crosses it spans its own width instead of ~360° (which
  // collapsed the fitted scale to a dot). Identity inside a hemisphere.
  final refLng = points.first.lng;
  double minLat = points.first.lat, maxLat = points.first.lat;
  double minLng = refLng, maxLng = refLng;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    final lng = unwrapLonDeg(refLng, p.lng);
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }
  final midLat = (minLat + maxLat) / 2;
  final lngScale = cos(midLat * pi / 180).abs();
  // A degenerate or non-finite span collapses to the epsilon rather than
  // producing an absurd scale. `max(span, 1e-6)` alone propagated NaN (Dart's
  // max returns NaN for it), while the web twin's falsy-only `|| 1e-6` absorbed
  // NaN but let a 1e-7 span through at a 10x different scale. Both sides now
  // clamp AND reject non-finite.
  final dLat = _spanOrEpsilon(maxLat - minLat);
  final dLng = _spanOrEpsilon((maxLng - minLng) * lngScale);
  final scaleX = (vbW - pad * 2) / dLng;
  final scaleY = (vbH - pad * 2) / dLat;
  final scale = min(scaleX, scaleY);
  final offX = pad + ((vbW - pad * 2) - dLng * scale) / 2;
  final offY = pad + ((vbH - pad * 2) - dLat * scale) / 2;
  return [
    for (final p in points)
      Offset(
        offX + (unwrapLonDeg(refLng, p.lng) - minLng) * lngScale * scale,
        offY + (maxLat - p.lat) * scale,
      ),
  ];
}

/// Bounding-box diagonal a track must exceed before it is worth drawing
/// at thumbnail scale. Named rather than spelled at the comparison
/// because two other rails hold the same number — web's
/// `MIN_RENDERABLE_SPAN_M` and the firmware's — and
/// `scripts/check_watch_wire_vectors.mjs` reads a rail by the NAME of
/// its constant, so an unnamed one cannot be registered and the three
/// drift unwatched.
const double kMinRenderableSpanM = 5.0;

/// True iff the track's bounding-box diagonal exceeds
/// [kMinRenderableSpanM] — large enough to be
/// worth drawing at thumbnail scale — catches GPS jitter from a runner
/// standing still without throwing away genuinely tiny laps.
/// Longitudes are unwrapped onto the first fix's side of the
/// antimeridian first: a raw min/max reads a stationary jitter cluster
/// AT the line as a 359.99° span, defeating the gate for exactly the
/// case it exists to catch. Mirrors `isTrackRenderable` in web's
/// `routes/track_projection.ts` — keep in lockstep.
bool isTrackRenderable(List<Waypoint> track) {
  if (track.length < 2) return false;
  final refLng = track.first.lng;
  double minLat = track.first.lat, maxLat = track.first.lat;
  double minLng = refLng, maxLng = refLng;
  for (final p in track) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    final lng = unwrapLonDeg(refLng, p.lng);
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }
  final dLatM = (maxLat - minLat) * 111320;
  final dLngM = (maxLng - minLng) * 111320 * cos(minLat * pi / 180);
  return sqrt(dLatM * dLatM + dLngM * dLngM) > kMinRenderableSpanM;
}

/// A positive, finite span for the projection scale. Mirrors `spanOrEpsilon`
/// in `track_projection.ts`.
double _spanOrEpsilon(double v) => v.isFinite && v > 1e-6 ? v : 1e-6;
